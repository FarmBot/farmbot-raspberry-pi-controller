defmodule FarmbotCeleryScript.Compiler.VariableDeclaration do

  @doc "Compiles a variable asignment"
  def variable_declaration(%{args: %{label: var_name, data_value: data_value_ast}}) do
    quote location: :keep do
      IO.inspect(unquote(var_name), label: "==== in VariableDeclaration: var_name")
      IO.inspect(unquote(data_value_ast), label: "==== in VariableDeclaration: data_value_ast")
      {:error, "TODO: Re-write this"}
    end
  end
end
