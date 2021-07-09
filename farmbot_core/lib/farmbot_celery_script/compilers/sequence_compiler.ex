defmodule FarmbotCeleryScript.Compiler.Sequence do

  def sequence(%{ body: block }) do
    FarmbotCeleryScript.Compiler.Utils.compile_block(block)
  end
end
