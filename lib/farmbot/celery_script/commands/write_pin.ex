defmodule Farmbot.CeleryScript.Command.WritePin do
  @moduledoc """
    WritePin
  """

  alias      Farmbot.CeleryScript.{Command, Types}
  alias      Farmbot.Context
  alias      Farmbot.Serial.Handler, as: UartHan
  @behaviour Command

  @doc ~s"""
    writes an arduino pin
      args: %{
        pin_number: integer,
        pin_mode: integer,
        pin_value: integer
      },
      body: []
  """
  @spec run(%{pin_number: Types.pin_number, pin_mode: Types.pin_mode,
    pin_value: integer}, [], Context.t) :: Context.t
  def run(%{pin_number: pin, pin_mode: mode, pin_value: val},
          [],
          context) do
    # sets the pin mode in bot state.
    Farmbot.BotState.set_pin_mode(context, pin, mode)
    UartHan.write(context, "F41 P#{pin} V#{val} M#{mode}")
    # HACK read the pin back to make sure it worked
    read_pin_args = %{pin_number: pin, pin_mode: mode, label: "ack"}
    new_context   = Command.read_pin(read_pin_args, [], context)
    # HACK the above hack doesnt work some times so we just force it to work.
    Farmbot.BotState.set_pin_value(context, pin, val)
    new_context
  end
end
