defmodule Farmbot.RPC.Handler do
  @moduledoc """
    Handles RPC commands. This is @handler in config.
  """
  require Logger
  use GenEvent
  alias RPC.Spec.Notification, as: Notification
  alias RPC.Spec.Request, as: Request
  alias RPC.Spec.Response, as: Response
  alias Farmbot.BotState.Monitor
  # these are the actual actionable functions
  import Farmbot.RPC.Requests
  import Farmbot.CeleryScript.Conversion
  @transport Application.get_env(:json_rpc, :transport)

  @doc """
    an ack_msg with just an id is concidered a valid good we win packet

    Example:
      iex> ack_msg("super_long_uuid")
      "{\"result\":{\"OK\":\"OK\"},\"id\":\"super_long_uuid\",\"error\":null}"

    an ack_msg with an id, and an error ( {method, message} ) is a good valid
    error packet\n
    Example:
      iex> ack_msg("super_long_uuid", {"move_relative", "that didn't work!"})
      "{\"result\":null,\"id\":\"super_long_uuid\",
          \"error\":{\"name\":\"move_relative\",
          \"message\":\"that didn't work\"}}"
  """
  @spec ack_msg(String.t) :: binary
  def ack_msg(id) when is_bitstring(id) do
    Poison.encode!(
    %{id: id,
      error: nil,
      result: %{"OK" => "OK"}})
  end

  # JSON RPC RESPONSE ERROR
  @spec ack_msg(String.t, {String.t, String.t}) :: binary
  def ack_msg(id, {name, message}) do
    Poison.encode!(
    %{id: id,
      error: %{name: name,
               message: message},
      result: nil})
  end

  @spec do_handle(Request.t) :: :ok
  def do_handle(%Request{} = rpc) do
    Logger.debug ">> using old handler"
    case handle_request(rpc.method, rpc.params) do
      :ok ->
        @transport.emit(ack_msg(rpc.id))
      {:error, name, message} ->
        @transport.emit(ack_msg(rpc.id, {name, message}))
      unknown ->
        @transport.emit(ack_msg(rpc.id, {"unknown error", unknown}))
    end
  end

  # when a request message comes in, we send an ack that we got the message
  @spec handle_incoming(Request.t | Response.t | Notification.t) :: any
  def handle_incoming(%Request{} = rpc) do
    # if this rpc command can be converted to celery script, to that
    case rpc_to_celery_script(rpc) do
      :ok ->
        Logger.warn "#{rpc.method} was converted to a " <>
        "celery script (this is ok)"
        @transport.emit(ack_msg(rpc.id))
      _ -> do_handle(rpc)
    end
  end

  # The bot itself doesn't make requests so it shouldn't ever get a response.
  def handle_incoming(%Response{} = rpc) do
    Logger.warn(">> doesn't know what to do with this message:
                  #{inspect rpc}")
  end

  # The frontend doesn't send notifications so the
  # bot shouldn't get a notification.
  def handle_incoming(%Notification{} = rpc) do
    Logger.warn(">> doesn't know what to do with this message:
                  #{inspect rpc}")
  end

  # Just to be sure
  def handle_incoming(_), do: Logger.warn(">> got a malformed RPC message!")

  @doc """
    Builds a json to send to the frontend
  """
  @spec build_status(Monitor.State.t) :: binary
  def build_status(%Monitor.State{} = unserialized) do
    m = %Notification{
      id: nil,
      method: "status_update",
      params: [serialize_state(unserialized)]}
    Poison.encode!(m)
  end

  # @doc """
  #   Sends the status message over whatever transport.
  # """
  # @spec send_status :: :ok | {:error, atom}
  # def send_status do
  #   build_status |> @transport.emit
  # end

  @doc """
    Takes the cached bot state, and then
    serializes it into thr correct shape for the frontend
    to be sent over mqtt
  """
  @spec serialize_state(Monitor.State.t) :: Serialized.t
  def serialize_state(%Monitor.State{
    hardware: hardware, configuration: configuration, scheduler: _scheduler
  }) do
    %Serialized{
      mcu_params: hardware.mcu_params,
      location: hardware.location,
      pins: hardware.pins,

      # configuration
      locks: configuration.locks,
      configuration: configuration.configuration,
      informational_settings: configuration.informational_settings,

      # farm scheduler
      # farm_scheduler: scheduler
    }
  end

  # GENEVENT CALLBACKS DON'T EVEN WORRY ABOUT IT

  def handle_event({:dispatch, state}, old_state)
  when state == old_state do
    {:ok, state}
  end

  # Event from BotState.
  def handle_event({:dispatch, state}, _) do
    state |> build_status |> @transport.emit
    {:ok, state}
  end

  # Gets the most recent "cached" BotState
  def handle_call(:state, state) do
    {:ok, state, state}
  end

  def handle_call(:force_dispatch, state) do
    state |> build_status |> @transport.emit
    {:ok, :ok, state}
  end

  def start_link(_args) do
    Monitor.add_handler(__MODULE__)
    {:ok, self()}
  end
end
