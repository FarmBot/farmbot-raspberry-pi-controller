defmodule FarmbotExt.AMQP.ConnectionWorker do
  @moduledoc """
  Manages the AMQP socket lifecycle.
  """

  use GenServer
  require Logger
  alias FarmbotExt.JWT
  alias FarmbotCore.Project
  alias FarmbotExt.AMQP.ConnectionWorker

  defstruct [:opts, :conn]

  def start_link(args, opts \\ [name: __MODULE__]) do
    GenServer.start_link(__MODULE__, args, opts)
  end

  def connection do
    GenServer.call(__MODULE__, :connection)
  end

  def init(opts) do
    Process.flag(:sensitive, true)
    Process.flag(:trap_exit, true)
    {:ok, %ConnectionWorker{conn: nil, opts: opts}, 0}
  end

  def terminate(reason, %{conn: nil}) do
    Logger.info("AMQP connection not open: #{inspect(reason)}")
  end

  def terminate(reason, %{conn: conn}) do
    if Process.alive?(conn.pid) do
      try do
        Logger.info("Closing AMQP connection: #{inspect(reason)}")
        :ok = AMQP.Connection.close(conn)
      rescue
        ex ->
          message = Exception.message(ex)
          Logger.error("Could not close AMQP connection: #{message}")
      end
    end
  end

  def handle_info(:timeout, state) do
    token = Keyword.fetch!(state.opts, :token)
    email = Keyword.fetch!(state.opts, :email)
    jwt = JWT.decode!(token)

    case open_connection(token, email, jwt.bot, jwt.mqtt, jwt.vhost) do
      {:ok, conn} ->
        Process.link(conn.pid)
        Process.monitor(conn.pid)
        {:noreply, %{state | conn: conn}}

      err ->
        Logger.error("Error connecting to AMPQ: #{inspect(err)}")
        {:noreply, %{state | conn: nil}, 5000}
    end
  end

  def handle_info({:EXIT, _pid, reason}, conn) do
    Logger.error("Connection crash: #{inspect(reason)}")
    {:stop, reason, conn}
  end

  def handle_call(:connection, _, %{conn: conn} = state), do: {:reply, conn, state}

  def open_connection(token, email, bot, mqtt_server, vhost) do
    Logger.info("Opening new AMQP connection.")

    # Make sure the types of these fields are correct. If they are not
    # you timeouts will happen.
    # Specifically if anything is `nil` or _any_ other atom, encoded as
    # a `:longstr` or `:shortstr` they will _NOT_ be `to_string/1`ified.
    opts = [
      client_properties: [
        {"version", :longstr, Project.version()},
        {"commit", :longstr, Project.commit()},
        {"target", :longstr, to_string(Project.target())},
        {"opened", :longstr, to_string(DateTime.utc_now())},
        {"product", :longstr, "farmbot_os"},
        {"bot", :longstr, bot},
        {"email", :longstr, email},
        {"node", :longstr, to_string(node())}
      ],
      host: mqtt_server,
      username: bot,
      password: token,
      virtual_host: vhost
    ]

    AMQP.Connection.open(opts)
  end

  def network_impl() do
    mod = Application.get_env(:farmbot_ext, __MODULE__) || []
    Keyword.get(mod, :network_impl, FarmbotExt.AMQP.ConnectionWorker.Network)
  end

  def maybe_connect_autosync(jwt_bot_claim) do
    network_impl().maybe_connect_autosync(jwt_bot_claim)
  end

  def close_channel(channel) do
    network_impl().close_channel(channel)
  end

  def rpc_reply(chan, jwt_dot_bot, label) do
    network_impl().rpc_reply(chan, jwt_dot_bot, label)
  end
end
