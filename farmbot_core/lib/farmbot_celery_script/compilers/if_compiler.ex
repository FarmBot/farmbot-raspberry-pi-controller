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
    rhs = Compiler.ast2elixir(rhs)

    # Turns the left hand side arg into
    # a number. x, y, z, and pin{number} are special that need to be
    # evaluated before evaluating the if statement.
    # any AST is also aloud to be on the lefthand side as
    # well, so if that is the case, compile it first.
    lhs =
      case lhs_ast do
        "x" ->
          fn _better_params ->
            FarmbotCeleryScript.SysCalls.get_cached_x()
          end
        "y" ->
          fn _better_params ->
            FarmbotCeleryScript.SysCalls.get_cached_y()
          end
        "z" ->
          fn _better_params ->
            FarmbotCeleryScript.SysCalls.get_cached_z()
          end
        "pin" <> pin ->
          fn _better_params ->
              FarmbotCeleryScript.SysCalls.read_cached_pin(
                (String.to_integer(pin))
              )
          end
        # Named pin has two intents here
        # in this case we want to read the named pin.
        %AST{kind: :named_pin} = ast ->
          fn _better_params ->
              FarmbotCeleryScript.SysCalls.read_cached_pin(Compiler.ast2elixir(ast))
          end
        %AST{} = ast ->
          Compiler.ast2elixir(ast)
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
          # The ast will look like: {:==, [], lhs, Compiler.ast2elixir(rhs)}
          fn _better_params ->
            (lhs) == (rhs)
          end

        "not" ->
          # ast will look like: {:!=, [], [lhs, Compiler.ast2elixir(rhs)]}
          fn _better_params ->
            (lhs) != (rhs)
          end

        "is_undefined" ->
          # ast will look like: {:is_nil, [], [lhs]}
          fn _better_params ->
            is_nil(lhs)
          end

        "<" ->
          # ast will look like: {:<, [], [lhs, Compiler.ast2elixir(rhs)]}
          fn _better_params ->
            (lhs) < (rhs)
          end

        ">" ->
          # ast will look like: {:>, [], [lhs, Compiler.ast2elixir(rhs)]}
          fn _better_params -> lhs > rhs end

        _ ->
          fn _better_params -> lhs end
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
    fn _better_params ->
      prefix_string = FarmbotCeleryScript.SysCalls.format_lhs(lhs_ast)
      # examples:
      # "current x position is 100"
      # "pin 13 > 1"
      # "peripheral 10 is unknon"
      result_str =
        case (op) do
          "is" -> "#{prefix_string} is #{(rhs)}"
          "not" -> "#{prefix_string} is not #{(rhs)}"
          "is_undefined" -> "#{prefix_string} is unknown"
          "<" -> "#{prefix_string} is less than #{(rhs)}"
          ">" -> "#{prefix_string} is greater than #{(rhs)}"
        end

      if (if_eval) do
        FarmbotCeleryScript.SysCalls.log(
          "Evaluated IF statement: #{result_str}; #{(truthy_suffix)}"
        )

        (FarmbotCeleryScript.Compiler.Utils.compile_block(then_ast))
      else
        FarmbotCeleryScript.SysCalls.log(
          "Evaluated IF statement: #{result_str}; #{(falsey_suffix)}"
        )

        (FarmbotCeleryScript.Compiler.Utils.compile_block(else_ast))
      end
    end
  end
end
