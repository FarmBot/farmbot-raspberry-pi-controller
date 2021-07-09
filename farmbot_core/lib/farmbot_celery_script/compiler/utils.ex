defmodule FarmbotCeleryScript.Compiler.Utils do

  def compile_block(asts) do
    IO.inspect(asts, label: "=== DO STUFF WITH THIS")
      fn _better_params ->
        [
          fn ->
            IO.puts("LOL IDK")
            {:error, "whatever"}
          end
        ]
      end
  end
end
