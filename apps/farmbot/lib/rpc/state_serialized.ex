defmodule Serialized do
  @moduledoc """
    The frontend expects a JSON version of this.
  """
  # TODO make these required keys.
  defstruct [
    # Hardware
    mcu_params: %{},
    location: [0,0,0],
    pins: %{},

    # configuration
    locks: [],
    configuration: %{},
    informational_settings: %{},

    # farm scheduler
    # farm_scheduler: %Farmbot.Scheduler.State.Serializer{}
  ]
  @type t :: %__MODULE__{
    locks: list(%{reason: String.t}),
    mcu_params: map,
    location: [number, ...], # i should change this to a tuple
    pins: %{},
    configuration: %{},
    informational_settings: %{},
    # farm_scheduler: Farmbot.Scheduler.State.Serializer.t,
  }
end
