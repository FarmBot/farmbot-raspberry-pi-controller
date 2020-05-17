defmodule FarmbotCore.Asset.Private do
  @moduledoc """
  Private Assets are those that are internal to
  Farmbot that _are not_ stored in the API, but
  _are_ stored in Farmbot's database.
  """
  require Logger
  require FarmbotCore.Logger

  alias FarmbotCore.{Asset.Repo,
    Asset.Private.LocalMeta,
  }

  import Ecto.Query, warn: false
  import Ecto.Changeset, warn: false

  @doc "Lists `module` objects that still need to be POSTed to the API."
  def list_local(module) do
    list = Repo.all(from(data in module, where: is_nil(data.id)))
    Enum.map(list, fn item ->
      if module == FarmbotCore.Asset.Point do
        msg = "list_local: Point#{item.id}.y = #{item.y || "nil"}"
        FarmbotCore.Logger.info(3, msg)
      end
      item
    end)
  end

  @doc "Lists `module` objects that have a `local_meta` object"
  def list_dirty(module) do
    table = table(module)
    q = from(lm in LocalMeta, where: lm.table == ^table, select: lm.asset_local_id)
    list = Repo.all(from(data in module, join: lm in subquery(q)))
    Enum.map(list, fn item ->
      if module == FarmbotCore.Asset.Point do
        msg = "list_dirty: Point#{item.id}.y = #{item.y || "nil"}"
        FarmbotCore.Logger.info(3, msg)
      end
      item
    end)
  end

  def maybe_get_local_meta(asset, table) do
    Repo.one(from(lm in LocalMeta, where: lm.asset_local_id == ^asset.local_id and lm.table == ^table))
  end

  @doc "Mark a document as `dirty` by creating a `local_meta` object"
  def mark_dirty!(asset, params \\ %{}) do
    table = table(asset)

    local_meta = maybe_get_local_meta(asset, table) || Ecto.build_assoc(asset, :local_meta)

    ## NOTE(Connor): 19/11/13
    # the try/catch here seems unneeded here, but because of how sqlite/ecto works, it is 100% needed.
    # Because sqlite can't test unique constraints before a transaction, if this function gets called for
    # the same asset more than once asyncronously, the asset can be marked dirty twice at the same time
    # causing the `unique constraint` error to happen in either `ecto` OR `sqlite`. I've
    # caught both errors here as they are both essentially the same thing, and can be safely
    # discarded. Doing an `insert_or_update/1` (without the bang) can still result in the sqlite
    # error being thrown.
    changeset = LocalMeta.changeset(local_meta, Map.merge(params, %{table: table, status: "dirty"}))
    try do
      Repo.insert_or_update!(changeset)
    catch
      :error,  %Sqlite.DbConnection.Error{
        message: "UNIQUE constraint failed: local_metas.table, local_metas.asset_local_id",
        sqlite: %{code: :constraint}
      } ->
        Logger.warn """
        Caught race condition marking data as dirty (sqlite)
        table: #{inspect(table)}
        id: #{inspect(asset.local_id)}
        """
        Ecto.Changeset.apply_changes(changeset)
      :error, %Ecto.InvalidChangesetError{
        changeset: %{
          action: :insert,
          errors: [
            table: {"LocalMeta already exists.", [
              validation: :unsafe_unique,
              fields: [:table, :asset_local_id]
            ]}
          ]}
        } ->
        Logger.warn """
        Caught race condition marking data as dirty (ecto)
        table: #{inspect(table)}
        id: #{inspect(asset.local_id)}
        """
        Ecto.Changeset.apply_changes(changeset)
      type, reason ->
        FarmbotCore.Logger.error 1, """
        Caught unexpected error marking data as dirty
        table: #{inspect(table)}
        id: #{inspect(asset.local_id)}
        error type: #{inspect(type)}
        reason: #{inspect(reason)}
        """
        Ecto.Changeset.apply_changes(changeset)
    end
  end

  @doc "Remove the `local_meta` record from an object."
  @spec mark_clean!(map) :: nil | map()
  def mark_clean!(data) do
    Repo.preload(data, :local_meta)
    |> Map.fetch!(:local_meta)
    |> case do
      nil -> nil
      local_meta -> Repo.delete!(local_meta)
    end
  end

  defp table(%module{}), do: table(module)
  defp table(module), do: module.__schema__(:source)
end
