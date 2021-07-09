defmodule FarmbotCeleryScript.Compiler.DataControl do
  alias FarmbotCeleryScript.Compiler

  # compiles coordinate
  # Coordinate should return a vec3
  def coordinate(%{args: %{x: x, y: y, z: z}}) do
    fn _better_params ->
      FarmbotCeleryScript.SysCalls.coordinate(
        (Compiler.ast2elixir(x)),
        (Compiler.ast2elixir(y)),
        (Compiler.ast2elixir(z))
      )
    end
  end

  # compiles point
  def point(%{args: %{pointer_type: type, pointer_id: id}}) do
    fn _better_params ->
      FarmbotCeleryScript.SysCalls.point(
        (Compiler.ast2elixir(type)),
        (Compiler.ast2elixir(id))
      )
    end
  end

  # compile a named pin
  def named_pin(%{args: %{pin_id: id, pin_type: type}}) do
    fn _better_params ->
      FarmbotCeleryScript.SysCalls.named_pin(
        (Compiler.ast2elixir(type)),
        (Compiler.ast2elixir(id))
      )
    end
  end

  def tool(%{args: %{tool_id: tool_id}}) do
    fn _better_params ->
      FarmbotCeleryScript.SysCalls.get_toolslot_for_tool(
        (Compiler.ast2elixir(tool_id))
      )
    end
  end
end
