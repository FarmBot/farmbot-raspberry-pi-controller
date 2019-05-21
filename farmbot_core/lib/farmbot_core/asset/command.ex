defmodule FarmbotCore.Asset.Command do
  @moduledoc """
  A collection of functions that _write_ to the DB
  """

  alias FarmbotCore.{
    Asset,
    Asset.Repo,
    Asset.Device
  }

  @type kind :: Device | FbosConfig | FwConfig
  @type return_type ::
          Device.t() | FbosConfig.t() | FwConfig.t()

  @callback update(kind, params :: map()) :: return_type
  def update(Device, params) do
    Asset.device()
    |> Device.changeset(params)
    |> Repo.update!()
  end
end
