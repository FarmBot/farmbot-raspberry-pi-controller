defmodule FarmbotCeleryScript.Compiler.Sequence do
  import FarmbotCeleryScript.Compiler.Utils

  def sequence(%{ body: block } = ast) do
    sequence_name = ast.meta[:sequence_name] || ast.args[:sequence_name]
    steps1 = compile_block(block) |> decompose_block_to_steps()
    steps2 = add_sequence_init_and_complete_logs(steps1, sequence_name)
    [
      quote location: :keep do
        fn ->
          unquote(steps2)
        end
      end
    ]
  end
end
