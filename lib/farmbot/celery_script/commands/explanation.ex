defmodule Farmbot.CeleryScript.Command.Explanation do
  @moduledoc """
    Explanation
  """

  alias Farmbot.CeleryScript.Command
  alias Farmbot.CeleryScript.Ast
  @behaviour Command

  @doc ~s"""
    Explanation for an rpc error
      args: %{label: String.t},
      body: []
  """
  @type explanation_type ::
    %Ast{kind: String.t, args: %{message: String.t}, body: []}
  @spec run(%{message: String.t}, [], Context.t) :: Context.t
  def run(%{message: message}, [], context) do
    result = %Ast{kind: "explanation", args: %{message: message}, body: []}
    Farmbot.Context.push_data(context, result)
  end
end
