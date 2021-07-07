defmodule FarmbotCeleryScript.Compiler.Utils do
  alias FarmbotCeleryScript.{ AST, Compiler }

  @doc """
  Recursively compiles a list or single Celery AST into an Elixir `__block__`
  """
  def compile_block(asts, acc \\ [])

  def compile_block(%AST{} = ast, _) do
    case Compiler.compile_ast(ast) do
      {_, _, _} = compiled ->
        {:__block__, [], [compiled]}

      compiled when is_list(compiled) ->
        {:__block__, [], compiled}
    end
  end

  def compile_block([ast | rest], acc) do
    case Compiler.compile_ast(ast) do
      compiled when is_list(compiled) ->
        compile_block(rest, acc ++ compiled)

      {_, _, _} = compiled ->
        compile_block(rest, acc ++ [compiled])

    end
  end

  def compile_block([], acc), do: {:__block__, [], acc}

  def decompose_block_to_steps({:__block__, _, steps} = _orig) do
    Enum.map(steps, fn step ->
      quote location: :keep do
        fn -> unquote(step) end
      end
    end)
  end

  def add_sequence_init_and_complete_logs(steps, sequence_name)
      when is_binary(sequence_name) do
    # This looks really weird because of the logs before and
    # after the compiled steps
    List.flatten([
      quote do
        fn ->
          FarmbotCeleryScript.SysCalls.sequence_init_log(
            "Starting #{unquote(sequence_name)}"
          )
        end
      end,
      steps,
      quote do
        fn ->
          FarmbotCeleryScript.SysCalls.sequence_complete_log(
            "Completed #{unquote(sequence_name)}"
          )
        end
      end
    ])
  end

  def add_sequence_init_and_complete_logs(steps, _) do
    steps
  end

  def add_sequence_init_and_complete_logs_ittr(steps, sequence_name)
      when is_binary(sequence_name) do
    # This looks really weird because of the logs before and
    # after the compiled steps
    List.flatten([
      quote do
        fn ->
          [
            fn ->
              FarmbotCeleryScript.SysCalls.sequence_init_log(
                "Starting #{unquote(sequence_name)}"
              )
            end
          ]
        end
      end,
      steps,
      quote do
        fn ->
          [
            fn ->
              FarmbotCeleryScript.SysCalls.sequence_complete_log(
                "Completed #{unquote(sequence_name)}"
              )
            end
          ]
        end
      end
    ])
  end

  def add_sequence_init_and_complete_logs_ittr(steps, _) do
    steps
  end
end
