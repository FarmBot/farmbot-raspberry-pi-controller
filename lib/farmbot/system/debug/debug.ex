defmodule Farmbot.System.Debug do
  @moduledoc "Supervisor for Various debugging modules."
  use Supervisor
  alias Plug.Adapters.Cowboy

  def start_link(_, opts) do
    Supervisor.start_link(__MODULE__, [], opts)
  end

  def init([]) do
    options = [
      port: 5000,
      acceptors: 3,
      dispatch: [
        {:_, [
          {"/wobserver/ws", Wobserver.Web.Client, []},
          {:_, Cowboy.Handler, {Farmbot.System.DebugRouter, []}}
        ]}
      ],
    ]
    children = [
      Plug.Adapters.Cowboy.child_spec(:http, Farmbot.System.DebugRouter, [], options),
      worker(Farmbot.System.Updates.SlackUpdater, []),
      worker(Farmbot.System.Debug.SSDPServer, [])
    ]

    opts = [strategy: :one_for_one]
    supervise(children, opts)
  end
end
