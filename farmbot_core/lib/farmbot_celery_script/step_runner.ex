defmodule FarmbotCeleryScript.StepRunner do
  @moduledoc """
  Handles execution of compiled CeleryScript AST
  """
  alias FarmbotCeleryScript.{AST, Compiler}

  @doc """
  Steps through an entire AST.
  """
  def step(listener, tag, %AST{} = ast) do
    IO.puts("=STARTING STEPS=")
    ast2 = Compiler.ast2elixir(ast)
    |> IO.inspect(label: "=== AST2")
    |> List.wrap()
    what_to_do? = {listener, tag, ast2}
    |> IO.inspect(label: "=ENDING STEPS=")
  end

  # def step(listener, tag, [fun | rest]) when is_function(fun, 0) do
  #   case execute(listener, tag, fun) do
  #     [fun | _] = more when is_function(fun, 0) ->
  #       step(listener, tag, more ++ rest)

  #     {:error, reason} when is_binary(reason) ->
  #       send(listener, {:step_complete, tag, {:error, reason}})
  #       {:error, reason}

  #     # Catch non string errors
  #     {:error, reason} ->
  #       send(listener, {:step_complete, tag, {:error, inspect(reason)}})
  #       {:error, inspect(reason)}

  #     _ ->
  #       step(listener, tag, rest)
  #   end
  # end

  # def step(listener, tag, []) do
  #   send(listener, {:step_complete, tag, :ok})
  #   :ok
  # end

  # defp execute(listener, tag, fun) do
  #   try do
  #     fun.()
  #   rescue
  #     e ->
  #       IO.warn("CeleryScript Exception: ", __STACKTRACE__)
  #       result = {:error, Exception.message(e)}
  #       send(listener, {:step_complete, tag, result})
  #       result
  #   catch
  #     _kind, error when is_binary(error) ->
  #       IO.warn("CeleryScript Error: #{error}", __STACKTRACE__)
  #       send(listener, {:step_complete, tag, {:error, error}})
  #       {:error, error}

  #     _kind, error ->
  #       IO.warn("CeleryScript Error: #{inspect(error)}", __STACKTRACE__)
  #       send(listener, {:step_complete, tag, {:error, inspect(error)}})
  #       {:error, inspect(error)}
  #   end
  # end
end
