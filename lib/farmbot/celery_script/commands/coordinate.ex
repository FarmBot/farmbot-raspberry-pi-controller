defmodule Farmbot.CeleryScript.Command.Coordinate do
  @moduledoc """
    Coordinate Object
  """

  alias Farmbot.CeleryScript.Ast
  alias Farmbot.CeleryScript.Command
  @behaviour Command

  @type x :: integer
  @type y :: integer
  @type z :: integer

  @doc ~s"""
    coodinate
      args: %{x: integer, y: integer, z: integer}
      body: []
  """
  @type coord_args :: %{x: x, y: y, z: z}
  @type t :: %Ast{kind: String.t, args: coord_args, body: []}
  @spec run(coord_args, [], Context.t) :: Context.t
  def run(%{x: _x, y: _y, z: _z} = args, [], context) do
    result = %Ast{kind: "coordinate", args: args, body: []}
    Farmbot.Context.push_data(context, result)
  end
end
