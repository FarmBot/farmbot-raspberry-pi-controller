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

  @valid_entry_points [:sequence, :rpc_request]

  @typedoc """
  Compiled CeleryScript node should compile to an anon function.
  Entrypoint nodes such as
  * `rpc_request`
  * `sequence`
  will compile to a function that takes a Keyword list of variables. This function
  needs to be executed before scheduling/executing.

  Non entrypoint nodes compile to a function that symbolizes one individual step.

  ## Examples

  `rpc_request` will be compiled to something like:
  ```
  fn ->
    [
      # Body of the `rpc_request` compiled in here.
    ]
  end
  ```

  as compared to a "simple" node like `wait` will compile to something like:
  ```
  fn() -> wait(200) end
  ```
  """
  @type compiled :: (Keyword.t() -> [(() -> any())]) | (() -> any())

  @doc """
  Recursive function that will emit Elixir AST from CeleryScript AST.
  """
  @spec compile(AST.t()) :: [compiled()]
  def compile(ast)

  def compile(%AST{kind: :abort}) do
    fn -> {:error, "aborted"} end
  end

  def compile(%AST{kind: kind} = ast) when kind in @valid_entry_points do
    compile_entry_point(compile_ast(ast), [])
  end

  def compile_entry_point([compiled | rest], acc) do
    debug_mode?() && print_compiled_code(compiled)
    # entry points must be evaluated once more with the calling `env`
    # to return a list of compiled `steps`
    case Macro.to_string(compiled) |> Code.eval_string() do
      {fun, _env} when is_function(fun, 0) ->
        compile_entry_point(rest, acc ++ apply(fun, []))

      {{:error, error}, _} ->
        {:error, error}
    end
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

  def compile_ast(ast_or_literal)

  def compile_ast(%AST{kind: kind} = ast) do
    if function_exported?(__MODULE__, kind, 1),
      do: apply(__MODULE__, kind, [ast]),
      else: raise("no compiler for #{kind}")
  end

  def compile_ast(lit) when is_number(lit), do: lit

  def compile_ast(lit) when is_binary(lit), do: lit

  def nothing(_ast) do
    quote location: :keep do
      FarmbotCeleryScript.SysCalls.nothing()
    end
  end

  def abort(_ast) do
    quote location: :keep do
      Macro.escape({:error, "aborted"})
    end
  end

  def wait(%{args: %{milliseconds: millis}}) do
    quote location: :keep do
      with millis when is_integer(millis) <- unquote(compile_ast(millis)) do
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

    quote location: :keep do
      FarmbotCeleryScript.SysCalls.send_message(
        unquote(compile_ast(type)),
        unquote(compile_ast(msg)),
        unquote(channels)
      )
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
    quote location: :keep do
      FarmbotCeleryScript.SysCalls.emergency_lock()
    end
  end

  def emergency_unlock(_) do
    quote location: :keep do
      FarmbotCeleryScript.SysCalls.emergency_unlock()
    end
  end

  def read_status(_) do
    quote location: :keep do
      FarmbotCeleryScript.SysCalls.read_status()
    end
  end

  def sync(_) do
    quote location: :keep do
      FarmbotCeleryScript.SysCalls.sync()
    end
  end

  def check_updates(_) do
    quote location: :keep do
      FarmbotCeleryScript.SysCalls.check_update()
    end
  end

  def flash_firmware(%{args: %{package: package_name}}) do
    quote location: :keep do
      FarmbotCeleryScript.SysCalls.flash_firmware(
        unquote(compile_ast(package_name))
      )
    end
  end

  def power_off(_) do
    quote location: :keep do
      FarmbotCeleryScript.SysCalls.power_off()
    end
  end

  def reboot(%{args: %{package: "farmbot_os"}}) do
    quote location: :keep do
      FarmbotCeleryScript.SysCalls.reboot()
    end
  end

  def reboot(%{args: %{package: "arduino_firmware"}}) do
    quote location: :keep do
      FarmbotCeleryScript.SysCalls.firmware_reboot()
    end
  end

  def factory_reset(%{args: %{package: package}}) do
    quote location: :keep do
      FarmbotCeleryScript.SysCalls.factory_reset(
        unquote(compile_ast(package))
      )
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

    quote location: :keep do
      FarmbotCeleryScript.SysCalls.change_ownership(
        unquote(compile_ast(email)),
        unquote(compile_ast(secret)),
        unquote(compile_ast(server))
      )
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
