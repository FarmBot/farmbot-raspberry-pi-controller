defmodule Farmbot.CeleryScript.AST.Node.CheckUpdates do
  @moduledoc false
  use Farmbot.CeleryScript.AST.Node
  allow_args [:package]

  def execute(%{package: :farmbot_os}, _, env) do
    env = mutate_env(env)
    {:error, "No implementation for updating fbos right now.", env}
  end

  def execute(%{package: :arduino_firmware}, _, env) do
    env = mutate_env(env)
    {:error, "Arduino firmware can not be updated manually.", env}
  end

  def execute(%{package: {:farmware, fw}}, _, env) do
    env = mutate_env(env)
    case Farmbot.Farmware.lookup(fw) do
      {:ok, %Farmbot.Farmware{} = fw} -> do_update_farmware(fw, env)
      {:error, reason} -> {:error, reason, env}
    end
  end

  defp do_update_farmware(%Farmbot.Farmware{url: url}, env) do
    case Farmbot.Farmware.Installer.install(url) do
      :ok -> {:ok, env}
      {:error, reason} -> {:error, reason, env}
    end
  end
end
