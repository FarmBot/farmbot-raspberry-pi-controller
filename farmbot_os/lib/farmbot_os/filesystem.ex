defmodule FarmbotOS.FileSystem do
  @moduledoc "Helper module for accessing the RW data partion"

  @data_path Application.get_env(:farmbot, __MODULE__)[:data_path]
  @data_path ||
    Mix.raise("""
      config :farmbot, FarmbotOS.Filesystem,
        data_path: "/path/to/folder"
    """)

  @doc "helper that always returns #{@data_path}"
  def data_path, do: @data_path
end
