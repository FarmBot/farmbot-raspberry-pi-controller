defmodule FarmbotCeleryScript.Compiler.Assertion do
  alias FarmbotCeleryScript.Compiler
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

    quote location: :keep do
      comment_header = unquote(comment_header)
      assertion_type = unquote(assertion_type)
      # cmnt = unquote(comment)
      lua_code = unquote(Compiler.compile_ast(expression))
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

          unquote(FarmbotCeleryScript.Compiler.Utils.compile_block(then_ast))

        {:ok, _} when assertion_type == "abort_recover" ->
          FarmbotCeleryScript.SysCalls.log_assertion(
            false,
            assertion_type,
            "#{comment_header}failed, recovering and aborting"
          )

          then_block = unquote(FarmbotCeleryScript.Compiler.Utils.compile_block(then_ast))

          then_block ++
            [
              FarmbotCeleryScript.Compiler.compile(%AST{kind: :abort, args: %{}})
            ]
      end
    end
  end
end
