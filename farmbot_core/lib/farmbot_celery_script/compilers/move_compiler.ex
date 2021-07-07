defmodule FarmbotCeleryScript.Compiler.Move do
  alias FarmbotCeleryScript.SysCalls
  alias FarmbotCeleryScript.SpecialValue

  def move(%{body: body}) do
    quote location: :keep do
      node_body = unquote(body)
      mod = unquote(__MODULE__)
      mod.perform_movement(node_body, better_params)
    end
  end

  # === "private" API starts here:
  def perform_movement(body, better_params) do
    extract_variables(body, better_params)
    |> expand_lua(better_params)
    |> calculate_movement_needs()
    |> do_perform_movement()
  end

  # If the user provides Lua, we need to evaluate the Lua and
  # tranform it to a `numeric` node type.
  def expand_lua(body, better_params) do
    Enum.map(body, fn
      %{ args: %{ speed_setting: %{ args: %{lua: lua} } }} = p ->
        data = convert_lua_to_number(lua, better_params)
        new_setting = %{kind: :numeric, args: %{number: data}}
        %{ p | args: %{ speed_setting: new_setting } }

      %{args: %{lua: lua}} = p ->
        data = convert_lua_to_number(lua, better_params)
        %{ p | args: %{kind: :numeric, args: %{number: data}} }

      %{ args: %{ axis_operand: %{ args: %{lua: lua} } } } = p ->
        data = convert_lua_to_number(lua, better_params)
        new_operand = %{args: %{number: data}, kind: :numeric}
        %{ p | args: %{ p.args | axis_operand: new_operand } }
      # Non-Lua nodes just pass through.
      item ->
        item
    end)
  end

  def extract_variables(body, better_params) do
    Enum.map(body, fn
      %{args: %{axis_operand: %{args: %{label: label}, kind: :identifier}}} = x ->
        new_operand = Map.fetch!(better_params, label)
        old_args = Map.fetch!(x, :args)
        new_args = Map.put(old_args, :axis_operand, new_operand)
        Map.put(x, :args, new_args)

      x ->
        x
    end)
  end

  def do_perform_movement(%{safe_z: true} = needs) do
    needs |> retract_z() |> move_xy() |> extend_z()
  end

  def do_perform_movement(%{safe_z: false} = n) do
    move_abs(n)
  end

  def retract_z(needs) do
    a = %{x: cx(), y: cy(), z: SpecialValue.safe_height()}
    b = Map.merge(needs, a)
    move_abs(b)
    needs
  end

  def move_xy(needs) do
    move_abs(Map.merge(needs, %{z: cz()}))
    needs
  end

  def extend_z(needs) do
    move_abs(Map.merge(needs, %{x: cx(), y: cy()}))
    needs
  end

  def calculate_movement_needs(body) do
    mapper = &FarmbotCeleryScript.Compiler.Move.mapper/1
    reducer = &FarmbotCeleryScript.Compiler.Move.reducer/2
    list = initial_state() ++ Enum.map(body, mapper)
    Enum.reduce(list, %{}, reducer)
  end

  def reducer({key, :+, value}, state) do
    Map.put(state, key, state[key] + value)
  end

  def reducer({key, :=, value}, state) do
    Map.put(state, key, value)
  end

  def mapper(%{kind: k, args: a}) do
    # lua, numeric
    speed_setting = a[:speed_setting]

    # identifier lua numeric point random special_value tool
    axis_operand = a[:axis_operand]

    # STRING: "x"|"y"|"z"|"all"
    axis = String.to_atom(a[:axis] || "none")

    if axis == :all do
      raise "Not permitted"
    end

    case k do
      :axis_overwrite ->
        {axis, :=, to_number(axis, axis_operand)}

      :axis_addition ->
        {axis, :+, to_number(axis, axis_operand)}

      :speed_overwrite ->
        next_speed = String.to_atom("speed_#{axis}")
        {next_speed, :=, to_number(axis, speed_setting)}

      :safe_z ->
        {:safe_z, :=, true}
    end
  end

  def initial_state do
    [
      {:x, :=, cx()},
      {:y, :=, cy()},
      {:z, :=, cz()},
      {:speed_x, :=, 100},
      {:speed_y, :=, 100},
      {:speed_z, :=, 100},
      {:safe_z, :=, false}
    ]
  end

  def to_number(_axis, %{args: %{variance: v}, kind: :random}) do
    Enum.random((-1 * v)..v)
  end

  def to_number(axis, %{kind: :coordinate, args: coord}) do
    to_number(axis, coord)
  end

  def to_number(_axis, %{args: %{number: num}, kind: :numeric}) do
    num
  end

  # This usually happens when `identifier`s are converted to
  # real values
  def to_number(axis, %{resource_id: id, resource_type: t}) do
    Map.fetch!(SysCalls.point(t, id), axis)
  end

  def to_number(axis, %{args: %{pointer_id: id, pointer_type: t}}) do
    Map.fetch!(SysCalls.point(t, id), axis)
  end

  def to_number(_, %{args: %{label: "safe_height"}, kind: :special_value}) do
    SpecialValue.safe_height()
  end

  def to_number(_, %{args: %{label: "soil_height"}, kind: :special_value}) do
    SpecialValue.soil_height()
  end

  def to_number(axis, %{
        args: %{label: "current_location"},
        kind: :special_value
      }) do
    to_number(axis, %{x: cx(), y: cy(), z: cz()})
  end

  def to_number(axis, %{x: _, y: _, z: _} = coord) do
    Map.fetch!(coord, axis)
  end

  def to_number(axis, %{kind: :tool, args: %{tool_id: id}}) do
    tool = FarmbotCeleryScript.SysCalls.get_toolslot_for_tool(id)
    to_number(axis, tool)
  end

  def to_number(_axis, arg) do
    raise "Can't handle numeric conversion for " <> inspect(arg)
  end

  def move_abs(%{x: x, y: y, z: z, speed_x: sx, speed_y: sy, speed_z: sz} = k) do
    x_str = FarmbotCeleryScript.FormatUtil.format_float(x)
    y_str = FarmbotCeleryScript.FormatUtil.format_float(y)
    z_str = FarmbotCeleryScript.FormatUtil.format_float(z)
    msg = "Moving to (#{x_str}, #{y_str}, #{z_str})"

    FarmbotCeleryScript.SysCalls.log(msg, true)
    :ok = SysCalls.move_absolute(x, y, z, sx, sy, sz)
    k
  end

  def cx, do: SysCalls.get_current_x()
  def cy, do: SysCalls.get_current_y()
  def cz, do: SysCalls.get_current_z()

  def convert_lua_to_number(lua, better_params) do
    case FarmbotCeleryScript.Compiler.Lua.do_lua(lua, better_params) do
      {:ok, [data]} ->
        if is_number(data) do
          data
        else
          lua_fail(data, lua)
        end

      data ->
        lua_fail(data, lua)
    end
  end

  def lua_fail(result, lua) do
    raise "Expected Lua to return number, got #{inspect(result)}. #{inspect(lua)}"
  end
end
