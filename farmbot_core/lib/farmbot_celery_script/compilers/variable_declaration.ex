defmodule FarmbotCeleryScript.Compiler.VariableDeclaration do

  @doc "Compiles a variable asignment"
  def variable_declaration(%{args: %{label: var_name, data_value: data_value_ast}}) do
    fn _better_params ->
      IO.inspect(var_name, label: "==== in VariableDeclaration: var_name")
      IO.inspect(data_value_ast, label: "==== in VariableDeclaration: data_value_ast")
      {:error, "TODO: Re-write this"}
    end
  end
end
