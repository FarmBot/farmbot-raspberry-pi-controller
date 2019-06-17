defmodule FarmbotCore.Asset.Command do
  @moduledoc """
  A collection of functions that _write_ to the DB
  """
  require Logger
  alias FarmbotCore.{Asset, Asset.Repo}

  @typedoc "String kind that should be turned into an Elixir module."
  @type kind :: String.t()

  @typedoc "key/value map of changes"
  @type params :: map()

  @typedoc "remote database id"
  @type id :: integer()

  @doc """
  Will insert, update or delete data in the local database.
  This function will raise if error occur.
  """
  @callback update(kind, params, id) :: :ok | no_return()

  def update("Device", _id, params) do 
    Asset.update_device!(params)
    :ok
  end
  
  def update("FbosConfig", _id, params) do 
    Asset.update_fbos_config!(params)
    :ok
  end
  
  def update("FirmwareConfig", _id, params) do 
    Asset.update_firmware_config!(params)
    :ok
  end
  
  # Deletion use case:
  # TODO(Connor) put checks for deleting Device, FbosConfig and FirmwareConfig

  def update("FarmEvent", id, nil) do
    farm_event = Asset.get_farm_event(id)
    farm_event && Asset.delete_farm_event!(farm_event)
    :ok
  end

  def update("Regimen", id, nil) do
    regimen = Asset.get_regimen(id)
    regimen && Asset.delete_regimen!(regimen)
    :ok
  end

  def update(asset_kind, id, nil) do
    old = Repo.get_by(as_module!(asset_kind), id: id)
    old && Repo.delete!(old)
    :ok
  end

  def update("FarmwareEnv", id, params) do 
    Asset.upsert_farmware_env_by_id(id, params)
    :ok
  end
  
  def update("FarmwareInstallation", id, params) do 
    Asset.upsert_farmware_env_by_id(id, params)
    :ok
  end

  def update("FarmEvent", id, params) do
    old = Asset.get_farm_event(id)
    if old, 
      do: Asset.update_farm_event!(old, params), 
      else: Asset.new_farm_event!(params)
    
    :ok
  end

  def update("Regimen", id, params) do
    old = Asset.get_regimen(id)
    if old, 
      do: Asset.update_regimen!(old, params), 
      else: Asset.new_regimen!(params)
    
    :ok
  end

  def update("Sensor", id, params) do
    old = Asset.get_sensor(id)
    if old, 
      do: Asset.update_sensor!(old, params), 
      else: Asset.new_sensor!(params)
    
    :ok
  end

  def update("SensorReading", id, params) do
    old = Asset.get_sensor_reading(id)
    if old, 
      do: Asset.update_sensor_reading!(old, params), 
      else: Asset.new_sensor_reading!(params)
    
    :ok
  end

  def update("Sequence", id, params) do
    old = Asset.get_sequence(id)
    if old,
      do: Asset.update_sequence!(old, params),
      else: Asset.new_sequence!(params)

    :ok
  end

  # Catch-all use case:
  def update(asset_kind, id, params) do
    Logger.warn "Implement me: #{asset_kind}"
    mod = as_module!(asset_kind)
    case Repo.get_by(mod, id: id) do
      nil ->
        struct!(mod)
        |> mod.changeset(params)
        |> Repo.insert!()

      asset ->
        mod.changeset(asset, params)
        |> Repo.update!()
    end

    :ok
  end

  @doc "Returns a Ecto Changeset that can be cached or applied."
  @callback new_changeset(kind, id, params) :: Ecto.Changeset.t()
  def new_changeset(asset_kind, id, params) do
    mod = as_module!(asset_kind)
    asset = Repo.get_by(mod, id: id) || struct!(mod)
    mod.changeset(asset, params)
  end

  defp as_module!("Device"), do: Asset.Device 
  defp as_module!("DiagnosticDump"), do: Asset.DiagnosticDump 
  defp as_module!("FarmEvent"), do: Asset.FarmEvent 
  defp as_module!("FarmwareEnv"), do: Asset.FarmwareEnv 
  defp as_module!("FarmwareInstallation"), do: Asset.FarmwareInstallation 
  defp as_module!("FbosConfig"), do: Asset.FbosConfig 
  defp as_module!("FirmwareConfig"), do: Asset.FirmwareConfig 
  defp as_module!("Peripheral"), do: Asset.Peripheral 
  defp as_module!("PinBinding"), do: Asset.PinBinding 
  defp as_module!("Point"), do: Asset.Point 
  defp as_module!("Regimen"), do: Asset.Regimen 
  defp as_module!("Sensor"), do: Asset.Sensor 
  defp as_module!("SensorReading"), do: Asset.SensorReading 
  defp as_module!("Sequence"), do: Asset.Sequence 
  defp as_module!("Tool"), do: Asset.Tool 
  defp as_module!(kind) when is_binary(kind) do
    raise("""
    Unknown kind: #{kind}
    """)
  end
end
