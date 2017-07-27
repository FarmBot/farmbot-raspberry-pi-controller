defmodule Farmbot.Serial.Gcode.Parser do
  @moduledoc """
    Parses farmbot_arduino_firmware G-Codes.
  """

  require Logger

  @spec parse_code(binary) :: {binary, tuple}

  def parse_code("R00 Q" <> tag), do: {tag, :idle}
  def parse_code("R01 Q" <> tag), do: {tag, :received}
  def parse_code("R02 Q" <> tag), do: {tag, :done}
  def parse_code("R03 Q" <> tag), do: {tag, :error}
  def parse_code("R04 Q" <> tag), do: {tag, :busy}

  def parse_code("R05" <> _r), do: {nil, :noop} # Dont care about this.
  def parse_code("R06 " <> r), do: parse_report_calibration(r)
  def parse_code("R07 " <> _), do: {nil, :noop}

  def parse_code("R20 Q" <> tag),   do: {tag, :report_params_complete}
  def parse_code("R21 " <> params), do: parse_pvq(params, :report_parameter_value)
  def parse_code("R23 " <> params), do: parse_report_axis_calibration(params)
  def parse_code("R31 " <> params), do: parse_pvq(params, :report_status_value)
  def parse_code("R41 " <> params), do: parse_pvq(params, :report_pin_value)
  def parse_code("R81 " <> params), do: parse_end_stops(params)

  def parse_code("R82 " <> p), do: report_xyz(p, :report_current_position)
  def parse_code("R83 " <> v), do: parse_version(v)

  def parse_code("R84 " <> p),  do: report_xyz(p, :report_encoder_position_scaled)
  def parse_code("R85 " <> p),  do: report_xyz(p, :report_encoder_position_raw)
  def parse_code("R87 Q" <> q), do: {q, :report_emergency_lock}

  def parse_code("R99 " <> message) do {nil, {:debug_message, message}} end
  def parse_code("Command" <> _), do: {nil, :noop} # I think this is a bug
  def parse_code(code)  do {:unhandled_gcode, code} end

  @spec parse_report_calibration(binary)
    :: {binary, {:report_calibration, binary, binary}}
  defp parse_report_calibration(r) do
    [axis_and_status | [q]] = String.split(r, " Q")
    <<a :: size(8), b :: size(8)>> = axis_and_status
    case b do
      48 -> {q, {:report_calibration, <<a>>, :idle}}
      49 -> {q, {:report_calibration, <<a>>, :home}}
      50 -> {q, {:report_calibration, <<a>>, :end}}
    end
  end

  defp parse_report_axis_calibration(params) do
    ["P" <> parm, "V" <> val, "Q" <> tag] = String.split(params, " ")
    if parm in ["141", "142", "143"] do
      uh  = :report_axis_calibration
      msg = {uh, parse_param(parm), String.to_integer(val)}
      {tag, msg}
    else
      {tag, :noop}
    end
  end

  @spec parse_version(binary) :: {binary, {:report_software_version, binary}}
  defp parse_version(version) do
    [derp | [code]] = String.split(version, " Q")
    {code, {:report_software_version, derp}}
  end

  @type reporter :: :report_current_position
    | :report_encoder_position_scaled
    | :report_encoder_position_raw

  @spec report_xyz(binary, reporter)
  :: {binary, {reporter, binary, binary, binary}}
  defp report_xyz(position, reporter) when is_bitstring(position),
    do: position |> String.split(" ") |> do_parse_pos(reporter)

  defp do_parse_pos(["X" <> x, "Y" <> y, "Z" <> z, "Q" <> tag], reporter) do
    {tag, {reporter,
      String.to_integer(x),
      String.to_integer(y),
      String.to_integer(z)}}
  end

  @doc ~S"""
    Parses End Stops. I don't think we actually use these yet.
    Example:
      iex> Gcode.parse_end_stops("XA1 XB1 YA0 YB1 ZA0 ZB1 Q123")
      {:report_end_stops, "1", "1", "0", "1", "0", "1", "123"}
  """
  @spec parse_end_stops(binary)
  :: {:report_end_stops,
      binary,
      binary,
      binary,
      binary,
      binary,
      binary,
      binary}
  def parse_end_stops(
    <<
      "XA", xa :: size(8), 32,
      "XB", xb :: size(8), 32,
      "YA", ya :: size(8), 32,
      "YB", yb :: size(8), 32,
      "ZA", za :: size(8), 32,
      "ZB", zb :: size(8), 32,
      "Q", tag :: binary
    >>), do: {tag, {:report_end_stops,
              xa |> pes,
              xb |> pes,
              ya |> pes,
              yb |> pes,
              za |> pes,
              zb |> pes}}

  @spec pes(48 | 49) :: 0 | 1 # lol
  defp pes(48), do: 0
  defp pes(49), do: 1

  @doc ~S"""
    common function for report_(something)_value from gcode.
    Example:
      iex> Gcode.parse_pvq("P20 V100", :report_parameter_value)
      {:report_parameter_value, "20" ,"100", "0"}

    Example:
      iex> Gcode.parse_pvq("P20 V100 Q12", :report_parameter_value)
      {:report_parameter_value, "20" ,"100", "12"}
  """
  @spec parse_pvq(binary, :report_parameter_value)
  :: {:report_parameter_value, atom, integer, String.t}
  def parse_pvq(params, :report_parameter_value)
  when is_bitstring(params),
    do: params |> String.split(" ") |> do_parse_params

  def parse_pvq(params, human_readable_param_name)
  when is_bitstring(params)
   and is_atom(human_readable_param_name),
   do: params |> String.split(" ") |> do_parse_pvq(human_readable_param_name)

  defp do_parse_pvq([p, v, q], human_readable_param_name) do
    [_, rp] = String.split(p, "P")
    [_, rv] = String.split(v, "V")
    [_, rq] = String.split(q, "Q")
    {rq, {human_readable_param_name,
     String.to_integer(rp),
     String.to_integer(rv)}}
  end

  defp do_parse_params([p, v, q]) do
    [_, rp] = String.split(p, "P")
    [_, rv] = String.split(v, "V")
    [_, rq] = String.split(q, "Q")
    {rq, {:report_parameter_value, parse_param(rp), String.to_integer(rv)}}
  end

  @doc ~S"""
    Parses farmbot_arduino_firmware params.
    If we want the name of param "0"\n
    Example:
      iex> Gcode.parse_param("0")
      :param_version

    Example:
      iex> Gcode.parse_param(0)
      :param_version

    If we want the integer of param :param_version\n
    Example:
      iex> Gcode.parse_param(:param_version)
      0

    Example:
      iex> Gcode.parse_param("param_version")
      0
  """
  @spec parse_param(binary | integer) :: atom | nil
  def parse_param("0"), do: :param_version

  def parse_param("2"), do: :param_config_ok
  def parse_param("3"), do: :param_use_eeprom
  def parse_param("4"), do: :param_e_stop_on_mov_err
  def parse_param("5"), do: :param_mov_nr_retry

  def parse_param("11"), do: :movement_timeout_x
  def parse_param("12"), do: :movement_timeout_y
  def parse_param("13"), do: :movement_timeout_z

  def parse_param("15"), do: :movement_keep_active_x
  def parse_param("16"), do: :movement_keep_active_y
  def parse_param("17"), do: :movement_keep_active_z

  def parse_param("18"), do: :movement_home_at_boot_x
  def parse_param("19"), do: :movement_home_at_boot_y
  def parse_param("20"), do: :movement_home_at_boot_z

  def parse_param("21"), do: :movement_invert_endpoints_x
  def parse_param("22"), do: :movement_invert_endpoints_y
  def parse_param("23"), do: :movement_invert_endpoints_z

  def parse_param("25"), do: :movement_enable_endpoints_x
  def parse_param("26"), do: :movement_enable_endpoints_y
  def parse_param("27"), do: :movement_enable_endpoints_z

  def parse_param("31"), do: :movement_invert_motor_x
  def parse_param("32"), do: :movement_invert_motor_y
  def parse_param("33"), do: :movement_invert_motor_z

  def parse_param("36"), do: :movement_secondary_motor_x
  def parse_param("37"), do: :movement_secondary_motor_invert_x

  def parse_param("41"), do: :movement_steps_acc_dec_x
  def parse_param("42"), do: :movement_steps_acc_dec_y
  def parse_param("43"), do: :movement_steps_acc_dec_z

  def parse_param("45"), do: :movement_stop_at_home_x
  def parse_param("46"), do: :movement_stop_at_home_y
  def parse_param("47"), do: :movement_stop_at_home_z

  def parse_param("51"), do: :movement_home_up_x
  def parse_param("52"), do: :movement_home_up_y
  def parse_param("53"), do: :movement_home_up_z

  def parse_param("61"), do: :movement_min_spd_x
  def parse_param("62"), do: :movement_min_spd_y
  def parse_param("63"), do: :movement_min_spd_z

  def parse_param("71"), do: :movement_max_spd_x
  def parse_param("72"), do: :movement_max_spd_y
  def parse_param("73"), do: :movement_max_spd_z

  def parse_param("101"), do: :encoder_enabled_x
  def parse_param("102"), do: :encoder_enabled_y
  def parse_param("103"), do: :encoder_enabled_z

  def parse_param("105"), do: :encoder_type_x
  def parse_param("106"), do: :encoder_type_y
  def parse_param("107"), do: :encoder_type_z

  def parse_param("111"), do: :encoder_missed_steps_max_x
  def parse_param("112"), do: :encoder_missed_steps_max_y
  def parse_param("113"), do: :encoder_missed_steps_max_z

  def parse_param("115"), do: :encoder_scaling_x
  def parse_param("116"), do: :encoder_scaling_y
  def parse_param("117"), do: :encoder_scaling_z

  def parse_param("121"), do: :encoder_missed_steps_decay_x
  def parse_param("122"), do: :encoder_missed_steps_decay_y
  def parse_param("123"), do: :encoder_missed_steps_decay_z

  def parse_param("125"), do: :encoder_use_for_pos_x
  def parse_param("126"), do: :encoder_use_for_pos_y
  def parse_param("127"), do: :encoder_use_for_pos_z

  def parse_param("131"), do: :encoder_invert_x
  def parse_param("132"), do: :encoder_invert_y
  def parse_param("133"), do: :encoder_invert_z

  def parse_param("141"), do: :movement_axis_nr_steps_x
  def parse_param("142"), do: :movement_axis_nr_steps_y
  def parse_param("143"), do: :movement_axis_nr_steps_z

  def parse_param("145"), do: :movement_stop_at_max_x
  def parse_param("146"), do: :movement_stop_at_max_y
  def parse_param("147"), do: :movement_stop_at_max_z

  def parse_param("201"), do: :pin_guard_1_pin_nr
  def parse_param("202"), do: :pin_guard_1_pin_time_out
  def parse_param("203"), do: :pin_guard_1_active_state

  def parse_param("205"), do: :pin_guard_2_pin_nr
  def parse_param("206"), do: :pin_guard_2_pin_time_out
  def parse_param("207"), do: :pin_guard_2_active_state

  def parse_param("211"), do: :pin_guard_3_pin_nr
  def parse_param("212"), do: :pin_guard_3_pin_time_out
  def parse_param("213"), do: :pin_guard_3_active_state

  def parse_param("215"), do: :pin_guard_4_pin_nr
  def parse_param("216"), do: :pin_guard_4_pin_time_out
  def parse_param("217"), do: :pin_guard_4_active_state

  def parse_param("221"), do: :pin_guard_5_pin_nr
  def parse_param("222"), do: :pin_guard_5_time_out
  def parse_param("223"), do: :pin_guard_5_active_state
  def parse_param(param) when is_integer(param), do: parse_param("#{param}")

  @spec parse_param(atom) :: integer | nil
  def parse_param(:param_version), do: 0

  def parse_param(:param_config_ok), do: 2
  def parse_param(:param_use_eeprom), do: 3
  def parse_param(:param_e_stop_on_mov_err), do: 4
  def parse_param(:param_mov_nr_retry), do: 5


  def parse_param(:movement_timeout_x), do: 11
  def parse_param(:movement_timeout_y), do: 12
  def parse_param(:movement_timeout_z), do: 13

  def parse_param(:movement_keep_active_x), do: 15
  def parse_param(:movement_keep_active_y), do: 16
  def parse_param(:movement_keep_active_z), do: 17

  def parse_param(:movement_home_at_boot_x), do: 18
  def parse_param(:movement_home_at_boot_y), do: 19
  def parse_param(:movement_home_at_boot_z), do: 20

  def parse_param(:movement_invert_endpoints_x), do: 21
  def parse_param(:movement_invert_endpoints_y), do: 22
  def parse_param(:movement_invert_endpoints_z), do: 23

  def parse_param(:movement_invert_motor_x), do: 31
  def parse_param(:movement_invert_motor_y), do: 32
  def parse_param(:movement_invert_motor_z), do: 33

  def parse_param(:movement_enable_endpoints_x), do: 25
  def parse_param(:movement_enable_endpoints_y), do: 26
  def parse_param(:movement_enable_endpoints_z), do: 27

  def parse_param(:movement_secondary_motor_x), do: 36
  def parse_param(:movement_secondary_motor_invert_x), do: 37

  def parse_param(:movement_steps_acc_dec_x), do: 41
  def parse_param(:movement_steps_acc_dec_y), do: 42
  def parse_param(:movement_steps_acc_dec_z), do: 43

  def parse_param(:movement_stop_at_home_x), do: 45
  def parse_param(:movement_stop_at_home_y), do: 46
  def parse_param(:movement_stop_at_home_z), do: 47

  def parse_param(:movement_home_up_x), do: 51
  def parse_param(:movement_home_up_y), do: 52
  def parse_param(:movement_home_up_z), do: 53

  def parse_param(:movement_min_spd_x), do: 61
  def parse_param(:movement_min_spd_y), do: 62
  def parse_param(:movement_min_spd_z), do: 63

  def parse_param(:movement_max_spd_x), do: 71
  def parse_param(:movement_max_spd_y), do: 72
  def parse_param(:movement_max_spd_z), do: 73

  def parse_param(:encoder_enabled_x), do: 101
  def parse_param(:encoder_enabled_y), do: 102
  def parse_param(:encoder_enabled_z), do: 103

  def parse_param(:encoder_type_x), do: 105
  def parse_param(:encoder_type_y), do: 106
  def parse_param(:encoder_type_z), do: 107

  def parse_param(:encoder_missed_steps_max_x), do: 111
  def parse_param(:encoder_missed_steps_max_y), do: 112
  def parse_param(:encoder_missed_steps_max_z), do: 113

  def parse_param(:encoder_scaling_x), do: 115
  def parse_param(:encoder_scaling_y), do: 116
  def parse_param(:encoder_scaling_z), do: 117

  def parse_param(:encoder_missed_steps_decay_x), do: 121
  def parse_param(:encoder_missed_steps_decay_y), do: 122
  def parse_param(:encoder_missed_steps_decay_z), do: 123

  def parse_param(:encoder_use_for_pos_x), do: 125
  def parse_param(:encoder_use_for_pos_y), do: 126
  def parse_param(:encoder_use_for_pos_z), do: 127

  def parse_param(:encoder_invert_x), do: 131
  def parse_param(:encoder_invert_y), do: 132
  def parse_param(:encoder_invert_z), do: 133

  def parse_param(:movement_axis_nr_steps_x), do: 141
  def parse_param(:movement_axis_nr_steps_y), do: 142
  def parse_param(:movement_axis_nr_steps_z), do: 143

  def parse_param(:movement_stop_at_max_x), do: 145
  def parse_param(:movement_stop_at_max_y), do: 146
  def parse_param(:movement_stop_at_max_z), do: 147

  def parse_param(:pin_guard_1_pin_nr), do: 201
  def parse_param(:pin_guard_1_pin_time_out), do: 202
  def parse_param(:pin_guard_1_active_state), do: 203

  def parse_param(:pin_guard_2_pin_nr), do: 205
  def parse_param(:pin_guard_2_pin_time_out), do: 206
  def parse_param(:pin_guard_2_active_state), do: 207

  def parse_param(:pin_guard_3_pin_nr), do: 211
  def parse_param(:pin_guard_3_pin_time_out), do: 212
  def parse_param(:pin_guard_3_active_state), do: 213

  def parse_param(:pin_guard_4_pin_nr), do: 215
  def parse_param(:pin_guard_4_pin_time_out), do: 216
  def parse_param(:pin_guard_4_active_state), do: 217

  def parse_param(:pin_guard_5_pin_nr), do: 221
  def parse_param(:pin_guard_5_time_out), do: 222
  def parse_param(:pin_guard_5_active_state), do: 223

  def parse_param(param_string) when is_bitstring(param_string),
    do: param_string |> String.to_atom |> parse_param

  # derp.
  if Mix.env == :dev do
    def parse_param(uhh) do
      Logger.error("Unrecognized param needs implementation " <>
        "#{inspect uhh}", rollbar: false)
      nil
    end
  else
    def parse_param(_), do: nil
  end
end
