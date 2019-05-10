defmodule FarmbotExt.AMQP.ConnectionWorker.Network do
  @moduledoc """
  Real-world implementation of AMQP socket IO handlers.
  """

  alias AMQP.{Basic, Channel, Queue}
  alias FarmbotCore.JSON
  @exchange "amq.topic"

  @doc "Cleanly close an AMQP channel"
  @callback close_channel(map()) :: nil
  def close_channel(chan) do
    Channel.close(chan)
  end

  @doc "Takes the 'bot' claim seen in the JWT and connects to the AMQP broker."
  @callback maybe_connect(String.t()) :: map()
  def maybe_connect(jwt_dot_bot) do
    bot = jwt_dot_bot
    auto_sync = bot <> "_auto_sync"
    route = "bot.#{bot}.sync.#"

    with %{} = conn <- FarmbotExt.AMQP.ConnectionWorker.connection(),
         {:ok, chan} <- Channel.open(conn),
         :ok <- Basic.qos(chan, global: true),
         {:ok, _} <- Queue.declare(chan, auto_sync, auto_delete: false),
         :ok <- Queue.bind(chan, auto_sync, @exchange, routing_key: route),
         {:ok, _} <- Basic.consume(chan, auto_sync, self(), no_ack: true) do
      %{conn: conn, chan: chan}
    else
      nil -> %{conn: nil, chan: nil}
      error -> error
    end
  end

  @doc "Respond with an OK message to a CeleryScript(TM) RPC message."
  @callback rpc_reply(map(), String.t(), String.t()) :: :ok
  def rpc_reply(chan, jwt_dot_bot, label) do
    json = JSON.encode!(%{args: %{label: label}, kind: "rpc_ok"})
    Basic.publish(chan, @exchange, "bot.#{jwt_dot_bot}.from_device", json)
  end
end
