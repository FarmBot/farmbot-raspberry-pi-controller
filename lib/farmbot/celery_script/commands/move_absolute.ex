defmodule Farmbot.CeleryScript.Command.MoveAbsolute do
  @moduledoc """
    Update Farmware
  """

  alias Farmbot.CeleryScript.Ast
  alias Farmbot.CeleryScript.Command
  import Command, only: [ast_to_coord: 2, ensure_gcode: 2]
  alias Farmbot.Lib.Maths
  require Logger
  alias Farmbot.Serial.Handler, as: UartHan

  @behaviour Command

  @type coordinate_ast :: Command.Coordinate.t

  @doc ~s"""
    move_absolute to a prticular position.
      args: %{
        speed: integer,
        offset: coordinate_ast | Ast.t
        location: coordinate_ast | Ast.t
      },
      body: []
  """
  @type move_absolute_args :: %{
    speed: integer,
    offset: coordinate_ast | Ast.t,
    location: coordinate_ast | Ast.t
  }
  @spec run(move_absolute_args, [], Context.t) :: Context.t
  def run(%{speed: s, offset: offset, location: location}, [], context) do
    new_context              = ast_to_coord(context, location)
    {location, new_context1} = Farmbot.Context.pop_data(new_context)

    new_context2             = ast_to_coord(new_context1, offset)
    {offset, new_context3}   = Farmbot.Context.pop_data(new_context2)

    a = {location.args.x, location.args.y, location.args.z}
    b = {offset.args.x,   offset.args.y,    offset.args.z }
    do_move(a, b, s, new_context3)
  end

  defp do_move({xa, ya, za}, {xb, yb, zb}, speed, context) do
    { combined_x, combined_y, combined_z } = { xa + xb, ya + yb, za + zb }
    {x, y, z} = do_math(combined_x, combined_y, combined_z, context)
    context
    |> UartHan.write("G00 X#{x} Y#{y} Z#{z} S#{speed}")
    |> ensure_gcode(context)
  end

  defp do_math(combined_x, combined_y, combined_z, context) do
    { Maths.mm_to_steps(combined_x, spm(:x, context)),
      Maths.mm_to_steps(combined_y, spm(:y, context)),
      Maths.mm_to_steps(combined_z, spm(:z, context)) }
  end

  defp spm(xyz, %Farmbot.Context{} = ctx) do
    thing = "steps_per_mm_#{xyz}" |> String.to_atom
    Farmbot.BotState.get_config(ctx, thing)
  end
end
