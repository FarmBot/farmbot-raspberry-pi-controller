defmodule Farmbot.BotState.Transport.AMQP do
  @moduledoc "AMQP Bot State Transport."

  use GenStage
  use AMQP
  use Farmbot.Logger

  alias Farmbot.CeleryScript
  alias CeleryScript.AST

  import Farmbot.BotState.Utils

  alias Farmbot.System.ConfigStorage
  import ConfigStorage, only: [get_config_value: 3]

  @exchange "amq.topic"

  @doc false
  def start_link do
    GenStage.start_link(__MODULE__, [], [name: __MODULE__])
  end

  # GenStage callbacks

  defmodule State do
    @moduledoc false
    defstruct [:conn, :chan, :queue_name, :bot, :state_cache]
  end

  def init([]) do
    token = ConfigStorage.get_config_value(:string, "authorization", "token")

    import Farmbot.Jwt, only: [decode: 1]
    with {:ok, %{bot: device, mqtt: mqtt_host, vhost: vhost}} <- decode(token),
         {:ok, conn}  <- open_connection(token, device, mqtt_host, vhost),
         {:ok, chan}  <- AMQP.Channel.open(conn),
         q_name       <- Enum.join([device, UUID.uuid1()], "-"),
         :ok          <- Basic.qos(chan, []),
         {:ok, _}     <- AMQP.Queue.declare(chan, q_name, [auto_delete: true]),
         from_clients <- [routing_key: "bot.#{device}.from_clients"],
         sync         <- [routing_key: "bot.#{device}.sync.#"],
         :ok          <- AMQP.Queue.bind(chan, q_name, @exchange, from_clients),
         :ok          <- AMQP.Queue.bind(chan, q_name, @exchange, sync),
         {:ok, _tag}  <- Basic.consume(chan, q_name, [no_ack: true, consumer_tag: q_name ])
         opts         <- [conn: conn, chan: chan, queue_name: q_name, bot: device],
         state        <- struct(State, opts)
    do
      # Logger.success(3, "Connected to real time services.")
      {:consumer, state, subscribe_to: [Farmbot.BotState, Farmbot.Logger]}
    else
      {:error, {:auth_failure, msg}} = fail ->
        Farmbot.System.factory_reset(msg)
        {:stop, fail, :no_state}
      {:error, err} ->
        msg = "Got error authenticating with Real time services: #{inspect err}"
        Logger.error 1, msg

        # If the auth task is running, force it to reset.
        if Process.whereis(Farmbot.Bootstrap.AuthTask) do
          Farmbot.Bootstrap.AuthTask.force_refresh()
        end
        :ignore
    end
  end

  defp open_connection(token, device, mqtt_server, vhost) do
    opts = [
      host: mqtt_server,
      username: device,
      password: token,
      virtual_host: vhost || "/"]
    AMQP.Connection.open(opts)
  end

  def terminate(_reason, state) do
    # If a channel was still open, close it.
    if state.chan, do: AMQP.Channel.close(state.chan)

    # If the connection is still open, close it.
    if state.conn, do: AMQP.Connection.close(state.conn)

    # If the auth task is running, force it to reset.
    if Process.whereis(Farmbot.Bootstrap.AuthTask) do
      Farmbot.Bootstrap.AuthTask.force_refresh()
    end
  end

  def handle_events(events, {pid, _}, state) do
    case Process.info(pid)[:registered_name] do
      Farmbot.Logger -> handle_log_events(events, state)
      Farmbot.BotState -> handle_bot_state_events(events, state)
    end
  end

  def handle_log_events(logs, state) do
    for %Farmbot.Log{} = log <- logs do
      if should_log?(log.module, log.verbosity) do
        fb = %{position: %{x: -1, y: -1, z: -1}}
        location_data = Map.get(state.state_cache || %{}, :location_data, fb)
        meta = %{
          type: log.level,
          x: nil, y: nil, z: nil,
          verbosity: log.verbosity,
          major_version: log.version.major,
          minor_version: log.version.minor,
          patch_version: log.version.patch,
        }
        log_without_pos = %{
          created_at: log.time,
          meta: meta,
          channels: log.meta[:channels] || [],
          message: log.message
        }
        log = add_position_to_log(log_without_pos, location_data)
        push_bot_log(state.chan, state.bot, log)
      end
    end

    {:noreply, [], state}
  end

  def handle_bot_state_events([event | rest], state) do
    case event do
      {:emit, %AST{} = ast} ->
        emit_cs(state.chan, state.bot, ast)
        handle_bot_state_events(rest, state)
      new_bot_state ->
        unless new_bot_state == state.state_cache do
          push_bot_state(state.chan, state.bot, new_bot_state)
        end
        handle_bot_state_events(rest, %{state | state_cache: new_bot_state})
    end
  end

  def handle_bot_state_events([], state) do
    {:noreply, [], state}
  end

  # Confirmation sent by the broker after registering this process as a consumer
  def handle_info({:basic_consume_ok, _}, state) do
    {:noreply, [], state}
  end

  # Sent by the broker when the consumer is
  # unexpectedly cancelled (such as after a queue deletion)
  def handle_info({:basic_cancel, _}, state) do
    {:stop, :normal, state}
  end

  # Confirmation sent by the broker to the consumer process after a Basic.cancel
  def handle_info({:basic_cancel_ok, _}, state) do
    {:noreply, [], state}
  end

  def handle_info({:basic_deliver, payload, %{routing_key: key}}, state) do
    device = state.bot
    route = String.split(key, ".")
    case route do
      ["bot", ^device, "from_clients"] ->
        handle_celery_script(payload, state)
        {:noreply, [], state}
      ["bot", ^device, "sync", resource, _]
      when resource in ["Log", "User", "Image", "WebcamFeed"] ->
        {:noreply, [], state}
      ["bot", ^device, "sync", resource, id] ->
        handle_sync_cmd(resource, id, payload, state)
      ["bot", ^device, "logs"]        -> {:noreply, [], state}
      ["bot", ^device, "status"]      -> {:noreply, [], state}
      ["bot", ^device, "from_device"] -> {:noreply, [], state}
      _ ->
        Logger.warn 3, "got unknown routing key: #{key}"
        {:noreply, [], state}
    end
  end

  defp handle_celery_script(payload, _state) do
    case AST.decode(payload) do
      {:ok, ast} -> spawn CeleryScript, :execute, [ast]
      _ -> :ok
    end
  end

  defp handle_sync_cmd(kind, id, payload, state) do
    mod = Module.concat(["Farmbot", "Repo", kind])
    if Code.ensure_loaded?(mod) do
      %{
        "body" => body,
        "args" => %{"label" => uuid}
      } = Poison.decode!(payload, as: %{"body" => struct(mod)})

      Farmbot.Repo.register_sync_cmd(String.to_integer(id), kind, body)

      if get_config_value(:bool, "settings", "auto_sync") do
        Farmbot.Repo.flip()
      end

      AST.Node.RpcOk.execute(%{label: uuid}, [], struct(Macro.Env))
    else
      msg = "Unknown syncable: #{mod}: #{inspect Poison.decode!(payload)}"
      Logger.warn 2, msg
    end
    {:noreply, [], state}
  end

  defp push_bot_log(chan, bot, log) do
    json = Poison.encode!(log)
    :ok = AMQP.Basic.publish chan, @exchange, "bot.#{bot}.logs", json
  end

  defp emit_cs(chan, bot, cs) do
    with {:ok, map} <- AST.encode(cs),
         {:ok, json} <- Poison.encode(map)
    do
      :ok = AMQP.Basic.publish chan, @exchange, "bot.#{bot}.from_device", json
    end
  end

  defp push_bot_state(chan, bot, state) do
    json = Poison.encode!(state)
    :ok = AMQP.Basic.publish chan, @exchange, "bot.#{bot}.status", json
  end

  defp add_position_to_log(%{meta: meta} = log, %{position: pos}) do
    new_meta = Map.merge(meta, pos)
    %{log | meta: new_meta}
  end
end
