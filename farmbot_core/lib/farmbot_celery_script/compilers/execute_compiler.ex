defmodule FarmbotCeleryScript.Compiler.Execute do
  # Compiles an `execute` block.
  # This one is actually pretty complex and is split into two parts.
  def execute( %{args: %{sequence_id: id}, body: _}) do
    quote location: :keep do
      # We have to lookup the sequence by it's id.
      case FarmbotCeleryScript.SysCalls.get_sequence(unquote(id)) do
        %FarmbotCeleryScript.AST{} = ast ->
          FarmbotCeleryScript.Compiler.compile(ast)
        error ->
          error
      end
    end
  end
end
