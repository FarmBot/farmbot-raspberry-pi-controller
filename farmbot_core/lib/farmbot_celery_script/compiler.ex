defmodule FarmbotCeleryScript.Compiler do
  @moduledoc """
  Responsible for compiling canonical CeleryScript AST into
  Elixir AST.
  """
  require Logger

  alias FarmbotCeleryScript.{ AST, Compiler }

  @doc "Returns current debug mode value"
  def debug_mode?() do
    # Set this to `true` when debuging.
    true
  end

  def compile_entry_point([], acc) do
    acc
  end

  defdelegate assertion(ast), to: Compiler.Assertion
  defdelegate calibrate(ast), to: Compiler.AxisControl
  defdelegate coordinate(ast), to: Compiler.DataControl
  defdelegate execute_script(ast), to: Compiler.Farmware
  defdelegate execute(ast), to: Compiler.Execute
  defdelegate find_home(ast), to: Compiler.AxisControl
  defdelegate home(ast), to: Compiler.AxisControl
  defdelegate install_first_party_farmware(ast), to: Compiler.Farmware
  defdelegate lua(ast), to: Compiler.Lua
  defdelegate move_absolute(ast), to: Compiler.AxisControl
  defdelegate move_relative(ast), to: Compiler.AxisControl
  defdelegate move(ast), to: Compiler.Move
  defdelegate named_pin(ast), to: Compiler.DataControl
  defdelegate point(ast), to: Compiler.DataControl
  defdelegate read_pin(ast), to: Compiler.PinControl
  defdelegate rpc_request(ast), to: Compiler.RPCRequest
  defdelegate sequence(ast), to: Compiler.Sequence
  defdelegate set_pin_io_mode(ast), to: Compiler.PinControl
  defdelegate set_servo_angle(ast), to: Compiler.PinControl
  defdelegate set_user_env(ast), to: Compiler.Farmware
  defdelegate take_photo(ast), to: Compiler.Farmware
  defdelegate toggle_pin(ast), to: Compiler.PinControl
  defdelegate tool(ast), to: Compiler.DataControl
  defdelegate unquote(:_if)(ast), to: Compiler.If
  defdelegate update_farmware(ast), to: Compiler.Farmware
  defdelegate update_resource(ast), to: Compiler.UpdateResource
  defdelegate variable_declaration(ast), to: Compiler.VariableDeclaration
  defdelegate write_pin(ast), to: Compiler.PinControl
  defdelegate zero(ast), to: Compiler.AxisControl

  def ast2elixir(ast_or_literal)

  def ast2elixir(%AST{kind: kind} = ast) do
    if function_exported?(__MODULE__, kind, 1),
      do: apply(__MODULE__, kind, [ast]),
      else: raise("no compiler for #{kind}")
  end

  def ast2elixir(lit) when is_number(lit), do: lit

  def ast2elixir(lit) when is_binary(lit), do: lit

  def nothing(_ast) do
    fn _better_params ->
      FarmbotCeleryScript.SysCalls.nothing()
    end
  end

  def abort(_ast) do
    fn _better_params ->
      {:error, "aborted"}
    end
  end

  def wait(%{args: %{milliseconds: millis}}) do
    fn _better_params ->
      with millis when is_integer(millis) <- millis do
        FarmbotCeleryScript.SysCalls.log("Waiting for #{millis} milliseconds")
        FarmbotCeleryScript.SysCalls.wait(millis)
      else
        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  def send_message(args) do
    %{args: %{message: msg, message_type: type}, body: channels} = args
    # body gets turned into a list of atoms.
    # Example:
    #   [{kind: "channel", args: {channel_name: "email"}}]
    # is turned into:
    #   [:email]
    channels =
      Enum.map(channels, fn %{
                              kind: :channel,
                              args: %{channel_name: channel_name}
                            } ->
        String.to_atom(channel_name)
      end)

    fn _better_params ->
      FarmbotCeleryScript.SysCalls.send_message(type, msg, channels)
    end
  end

  # compiles identifier into a variable.
  # We have to use Elixir ast syntax here because
  # var! doesn't work quite the way we want.
  def identifier(%{args: %{label: var_name}}) do
    IO.inspect(var_name, label: "====== identifier")
    {:error, "TODO: Re-write identifier"}
  end

  def emergency_lock(_) do
    fn _better_params ->
      FarmbotCeleryScript.SysCalls.emergency_lock()
    end
  end

  def emergency_unlock(_) do
    fn _better_params ->
      FarmbotCeleryScript.SysCalls.emergency_unlock()
    end
  end

  def read_status(_) do
    fn _better_params ->
      FarmbotCeleryScript.SysCalls.read_status()
    end
  end

  def sync(_) do
    fn _better_params ->
      FarmbotCeleryScript.SysCalls.sync()
    end
  end

  def check_updates(_) do
    fn _better_params ->
      FarmbotCeleryScript.SysCalls.check_update()
    end
  end

  def flash_firmware(%{args: %{package: package_name}}) do
    fn _better_params ->
      FarmbotCeleryScript.SysCalls.flash_firmware(package_name)
    end
  end

  def power_off(_) do
    fn _better_params ->
      FarmbotCeleryScript.SysCalls.power_off()
    end
  end

  def reboot(%{args: %{package: "farmbot_os"}}) do
    fn _better_params ->
      FarmbotCeleryScript.SysCalls.reboot()
    end
  end

  def reboot(%{args: %{package: "arduino_firmware"}}) do
    fn _better_params ->
      FarmbotCeleryScript.SysCalls.firmware_reboot()
    end
  end

  def factory_reset(%{args: %{package: package}}) do
    fn _ ->
      FarmbotCeleryScript.SysCalls.factory_reset(package)
    end
  end

  def change_ownership(%{body: body}) do
    pairs =
      Map.new(body, fn %{args: %{label: label, value: value}} ->
        {label, value}
      end)

    email = Map.fetch!(pairs, "email")

    secret =
      Map.fetch!(pairs, "secret")
      |> Base.decode64!(padding: false, ignore: :whitespace)

    server = Map.get(pairs, "server")

    fn _better_params ->
      FarmbotCeleryScript.SysCalls.change_ownership(email, secret, server)
    end
  end

  def print_compiled_code(compiled) do
    IO.puts("=== START ===")

    compiled
    |> Macro.to_string()
    |> Code.format_string!()
    |> IO.puts()

    IO.puts("=== END ===\n\n")
    compiled
  end
end
