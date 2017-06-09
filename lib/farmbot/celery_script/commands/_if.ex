defmodule Farmbot.CeleryScript.Command.If do
  @moduledoc """
    If
  """

  alias Farmbot.CeleryScript.{Command, Ast}
  import Command, only: [do_command: 2, read_pin_or_raise: 3]
  alias Farmbot.Context
  use Farmbot.DebugLog

  @behaviour Command

  @doc ~s"""
    Conditionally does something
      args: %{_else: Ast.t
              _then: Ast.t,
              lhs: String.t,
              op: "<" | ">" | "is" | "not",
              rhs: integer},
      body: []
  """
  @spec run(%{}, [], Context.t) :: Context.t
  def run(%{_else: else_, _then: then_, lhs: lhs, op: op, rhs: rhs }, pairs, ctx) do
    left = lhs |> eval_lhs(ctx, pairs)
    unless is_integer(left) do
      raise "could not evaluate left hand side of if statment! #{inspect lhs}"
    end

    eval_if({left, op, rhs}, then_, else_, ctx)
  end

  # figure out what the user wanted
  @spec eval_lhs(binary, Context.t, [Ast.t]) :: integer

  defp eval_lhs(lhs, %Farmbot.Context{} = context, pairs) do
    [x, y, z] = Farmbot.BotState.get_current_pos(context)
    case lhs do
      "x"             -> x
      "y"             -> y
      "z"             -> z
      "pin" <> number -> lookup_pin(context, number, pairs)
      _               -> nil
    end
  end

  @spec lookup_pin(Context.t, binary, [Ast.t]) :: integer | no_return
  defp lookup_pin(context, number, pairs) do
    thing   = number |> String.trim |> String.to_integer
    pin_map = Farmbot.BotState.get_pin(context, thing)
    case pin_map do
      %{value: val} -> val
      nil           ->
        new_context = read_pin_or_raise(context, number, pairs)
        lookup_pin(new_context, number, [])
    end
  end

  @spec eval_if({integer, String.t, integer},
    Ast.t, Ast.t, Context.t) :: Context.t

  defp eval_if({lhs, ">", rhs}, then_, else_, context) do
    if lhs > rhs,
      do: print_and_execute(then_, lhs > rhs, context),
    else: print_and_execute(else_, lhs > rhs, context)
  end

  defp eval_if({lhs, "<", rhs}, then_, else_, context) do
    if lhs < rhs,
      do: print_and_execute(then_, lhs < rhs, context),
    else: print_and_execute(else_, lhs < rhs, context)
  end

  defp eval_if({lhs, "is", rhs}, then_, else_, context) do
    if lhs == rhs,
      do: print_and_execute(then_, lhs == rhs, context),
    else: print_and_execute(else_, lhs == rhs, context)
  end

  defp eval_if({lhs, "not", rhs}, then_, else_, context) do
    if lhs != rhs,
      do: print_and_execute(then_, lhs != rhs, context),
    else: print_and_execute(else_, lhs != rhs, context)
  end

  defp eval_if({_, op, _}, _, _, _context),
    do: raise "Bad operator in if #{inspect op}"

  defp print_and_execute(%Ast{} = ast, bool, %Context{} = ctx) do
    debug_log "if evaluated: #{bool}, doing: #{inspect ast}"
    do_command(ast, ctx)
  end
end
