defmodule FarmbotCeleryScript.Compiler.If do
  alias FarmbotCeleryScript.{AST, Compiler}

  # Compiles an if statement.
  def unquote(:_if)(
        %{
          args: %{
            _then: then_ast,
            _else: else_ast,
            lhs: lhs_ast,
            op: op,
            rhs: rhs
          }
        }) do
    rhs = Compiler.compile_ast(rhs)

    # Turns the left hand side arg into
    # a number. x, y, z, and pin{number} are special that need to be
    # evaluated before evaluating the if statement.
    # any AST is also aloud to be on the lefthand side as
    # well, so if that is the case, compile it first.
    lhs =
      case lhs_ast do
        "x" ->
          quote [location: :keep],
            do: FarmbotCeleryScript.SysCalls.get_cached_x()

        "y" ->
          quote [location: :keep],
            do: FarmbotCeleryScript.SysCalls.get_cached_y()

        "z" ->
          quote [location: :keep],
            do: FarmbotCeleryScript.SysCalls.get_cached_z()

        "pin" <> pin ->
          quote [location: :keep],
            do:
              FarmbotCeleryScript.SysCalls.read_cached_pin(
                unquote(String.to_integer(pin))
              )

        # Named pin has two intents here
        # in this case we want to read the named pin.
        %AST{kind: :named_pin} = ast ->
          quote [location: :keep],
            do:
              FarmbotCeleryScript.SysCalls.read_cached_pin(
                unquote(Compiler.compile_ast(ast))
              )

        %AST{} = ast ->
          Compiler.compile_ast(ast)
      end

    # Turn the `op` arg into Elixir code
    if_eval =
      case op do
        "is" ->
          # equality check.
          # Examples:
          # get_current_x() == 0
          # get_current_y() == 10
          # get_current_z() == 200
          # read_pin(22, nil) == 5
          # The ast will look like: {:==, [], lhs, Compiler.compile_ast(rhs)}
          quote location: :keep do
            unquote(lhs) == unquote(rhs)
          end

        "not" ->
          # ast will look like: {:!=, [], [lhs, Compiler.compile_ast(rhs)]}
          quote location: :keep do
            unquote(lhs) != unquote(rhs)
          end

        "is_undefined" ->
          # ast will look like: {:is_nil, [], [lhs]}
          quote location: :keep do
            is_nil(unquote(lhs))
          end

        "<" ->
          # ast will look like: {:<, [], [lhs, Compiler.compile_ast(rhs)]}
          quote location: :keep do
            unquote(lhs) < unquote(rhs)
          end

        ">" ->
          # ast will look like: {:>, [], [lhs, Compiler.compile_ast(rhs)]}
          quote location: :keep do
            unquote(lhs) > unquote(rhs)
          end

        _ ->
          quote location: :keep do
            unquote(lhs)
          end
      end

    truthy_suffix =
      case then_ast do
        %{kind: :execute} -> "branching"
        %{kind: :nothing} -> "continuing execution"
      end

    falsey_suffix =
      case else_ast do
        %{kind: :execute} -> "branching"
        %{kind: :nothing} -> "continuing execution"
      end

    # Finally, compile the entire if statement.
    # outputted code will look something like:
    # if get_current_x() == 123 do
    #    execute(123)
    # else
    #    nothing()
    # end
    quote location: :keep do
      prefix_string = FarmbotCeleryScript.SysCalls.format_lhs(unquote(lhs_ast))
      # examples:
      # "current x position is 100"
      # "pin 13 > 1"
      # "peripheral 10 is unknon"
      result_str =
        case unquote(op) do
          "is" -> "#{prefix_string} is #{unquote(rhs)}"
          "not" -> "#{prefix_string} is not #{unquote(rhs)}"
          "is_undefined" -> "#{prefix_string} is unknown"
          "<" -> "#{prefix_string} is less than #{unquote(rhs)}"
          ">" -> "#{prefix_string} is greater than #{unquote(rhs)}"
        end

      if unquote(if_eval) do
        FarmbotCeleryScript.SysCalls.log(
          "Evaluated IF statement: #{result_str}; #{unquote(truthy_suffix)}"
        )

        unquote(FarmbotCeleryScript.Compiler.Utils.compile_block(then_ast))
      else
        FarmbotCeleryScript.SysCalls.log(
          "Evaluated IF statement: #{result_str}; #{unquote(falsey_suffix)}"
        )

        unquote(FarmbotCeleryScript.Compiler.Utils.compile_block(else_ast))
      end
    end
  end
end
