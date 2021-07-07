defmodule FarmbotCeleryScript.Compiler.Farmware do
  alias FarmbotCeleryScript.Compiler

  def take_photo(%{body: params}) do
    execute_script(%{args: %{label: "take-photo"}, body: params})
  end

  def execute_script(%{args: %{label: package}, body: _params}) do
    quote location: :keep do
      package = unquote(Compiler.compile_ast(package))
      FarmbotCeleryScript.SysCalls.log(unquote(format_log(package)), true)
      FarmbotCeleryScript.SysCalls.execute_script(package, [])
    end
  end

  def install_first_party_farmware(_) do
    quote location: :keep do
      FarmbotCeleryScript.SysCalls.log("Installing dependencies...")
      FarmbotCeleryScript.SysCalls.install_first_party_farmware()
    end
  end

  def set_user_env(%{body: pairs}) do
    kvs =
      Enum.map(pairs, fn %{kind: :pair, args: %{label: key, value: value}} ->
        quote location: :keep do
          FarmbotCeleryScript.SysCalls.set_user_env(
            unquote(key),
            unquote(value)
          )
        end
      end)

    quote location: :keep do
      (unquote_splicing(kvs))
    end
  end

  def update_farmware(%{args: %{package: package}}) do
    quote location: :keep do
      package = unquote(Compiler.compile_ast(package))
      FarmbotCeleryScript.SysCalls.log("Updating Farmware: #{package}", true)
      FarmbotCeleryScript.SysCalls.update_farmware(package)
    end
  end

  def format_log("camera-calibration"), do: "Calibrating camera"
  def format_log("historical-camera-calibration"), do: "Calibrating camera"
  def format_log("historical-plant-detection"), do: "Running weed detector"
  def format_log("plant-detection"), do: "Running weed detector"
  def format_log("take-photo"), do: "Taking photo"
  def format_log(package), do: "Executing #{package}"
end
