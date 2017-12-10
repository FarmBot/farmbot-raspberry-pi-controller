defmodule Farmbot.CeleryScript.AST.Node.WritePin do
  @moduledoc false
  use Farmbot.CeleryScript.AST.Node
  allow_args [:pin_number, :pin_value, :pin_mode]

  def execute(%{pin_mode: mode, pin_value: value, pin_number: num}, [], env) do
    env = mutate_env(env)
    case Farmbot.Firmware.set_pin_mode(num, :output) do
      :ok ->
        case Farmbot.Firmware.write_pin(num, mode, value) do
          :ok ->
            {:ok, env}
            {:error, reason} -> {:error, reason, env}
          end
      {:error, reason} -> {:error, reason, env}
    end
  end
end
