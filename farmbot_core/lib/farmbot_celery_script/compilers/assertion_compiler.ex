defmodule FarmbotCeleryScript.Compiler.Assertion do
  alias FarmbotCeleryScript.{Compiler, AST}
  @doc "`Assert` is a internal node useful for self testing."
  def assertion(
        %{
          args: %{
            lua: expression,
            assertion_type: assertion_type,
            _then: then_ast
          },
          comment: comment
        }) do
    comment_header =
      if comment do
        "[#{comment}] "
      else
        "[Assertion] "
      end

    fn better_params ->
      comment_header = (comment_header)
      assertion_type = (assertion_type)
      # cmnt = (comment)
      lua_code = (Compiler.ast2elixir(expression))
      result = FarmbotCeleryScript.Compiler.Lua.do_lua(lua_code, better_params)
      # result = FarmbotCeleryScript.SysCalls.perform_lua(lua_code, [], cmnt)
      case result do
        {:error, reason} ->
          FarmbotCeleryScript.SysCalls.log_assertion(
            false,
            assertion_type,
            "#{comment_header}failed to evaluate, aborting"
          )

          {:error, reason}

        {:ok, [true]} ->
          FarmbotCeleryScript.SysCalls.log_assertion(
            true,
            assertion_type,
            "#{comment_header}passed, continuing execution"
          )

          :ok

        {:ok, _} when assertion_type == "continue" ->
          FarmbotCeleryScript.SysCalls.log_assertion(
            false,
            assertion_type,
            "#{comment_header}failed, continuing execution"
          )

          :ok

        {:ok, _} when assertion_type == "abort" ->
          FarmbotCeleryScript.SysCalls.log_assertion(
            false,
            assertion_type,
            "#{comment_header}failed, aborting"
          )

          {:error, "Assertion failed (aborting)"}

        {:ok, _} when assertion_type == "recover" ->
          FarmbotCeleryScript.SysCalls.log_assertion(
            false,
            assertion_type,
            "#{comment_header}failed, recovering and continuing"
          )

          (FarmbotCeleryScript.Compiler.Utils.compile_block(then_ast))

        {:ok, _} when assertion_type == "abort_recover" ->
          FarmbotCeleryScript.SysCalls.log_assertion(
            false,
            assertion_type,
            "#{comment_header}failed, recovering and aborting"
          )

          then_block = (FarmbotCeleryScript.Compiler.Utils.compile_block(then_ast))

          then_block ++
            [
              FarmbotCeleryScript.Compiler.ast2elixir(%AST{kind: :abort, args: %{}})
            ]
      end
    end
  end
end
