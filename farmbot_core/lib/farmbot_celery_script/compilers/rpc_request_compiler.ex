defmodule FarmbotCeleryScript.Compiler.RPCRequest do
  def rpc_request(%{args: %{label: _label}, body: block}) do
    steps = FarmbotCeleryScript.Compiler.Utils.compile_block(block)
    fn better_params ->
      # Quiets the compiler (unused var warning)
      _ = inspect(better_params)
      steps
    end
  end
end
