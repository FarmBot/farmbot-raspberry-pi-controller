defmodule FarmbotCeleryScript.Compiler.AxisControl do
  alias FarmbotCeleryScript.Compiler

  # Compiles move_absolute
  def move_absolute(%{
    args: %{
      location: location,
      offset: offset,
      speed: speed
    }
    }) do
    fn _better_params ->
      # Extract the location arg
      with %{x: locx, y: locy, z: locz} =
             (Compiler.ast2elixir(location)),
           # Extract the offset arg
           %{x: offx, y: offy, z: offz} =
             (Compiler.ast2elixir(offset)) do
        # Subtract the location from offset.
        # Note: list syntax here for readability.
        [x, y, z] = [
          locx + offx,
          locy + offy,
          locz + offz
        ]

        x_str = FarmbotCeleryScript.FormatUtil.format_float(x)
        y_str = FarmbotCeleryScript.FormatUtil.format_float(y)
        z_str = FarmbotCeleryScript.FormatUtil.format_float(z)

        FarmbotCeleryScript.SysCalls.log(
          "Moving to (#{x_str}, #{y_str}, #{z_str})",
          true
        )

        FarmbotCeleryScript.SysCalls.move_absolute(
          x,
          y,
          z,
          (Compiler.ast2elixir(speed))
        )
      end
    end
  end

  # compiles move_relative into move absolute
  def move_relative(%{args: %{x: x, y: y, z: z, speed: speed}}) do
    fn _better_params ->
      with locx when is_number(locx) <- (Compiler.ast2elixir(x)),
           locy when is_number(locy) <- (Compiler.ast2elixir(y)),
           locz when is_number(locz) <- (Compiler.ast2elixir(z)),
           curx when is_number(curx) <-
             FarmbotCeleryScript.SysCalls.get_current_x(),
           cury when is_number(cury) <-
             FarmbotCeleryScript.SysCalls.get_current_y(),
           curz when is_number(curz) <-
             FarmbotCeleryScript.SysCalls.get_current_z() do
        # Combine them
        x = locx + curx
        y = locy + cury
        z = locz + curz
        x_str = FarmbotCeleryScript.FormatUtil.format_float(x)
        y_str = FarmbotCeleryScript.FormatUtil.format_float(y)
        z_str = FarmbotCeleryScript.FormatUtil.format_float(z)

        FarmbotCeleryScript.SysCalls.log(
          "Moving relative to (#{x_str}, #{y_str}, #{z_str})",
          true
        )

        FarmbotCeleryScript.SysCalls.move_absolute(
          x,
          y,
          z,
          (Compiler.ast2elixir(speed))
        )
      end
    end
  end

  # Expands find_home(all) into three find_home/1 calls
  def find_home(%{args: %{axis: "all"}}, _env) do
    fn _better_params ->
      FarmbotCeleryScript.SysCalls.log("Finding home on all axes", true)

      with :ok <- FarmbotCeleryScript.SysCalls.find_home("z"),
           :ok <- FarmbotCeleryScript.SysCalls.find_home("y") do
        FarmbotCeleryScript.SysCalls.find_home("x")
      end
    end
  end

  # compiles find_home
  def find_home(%{args: %{axis: axis}}) do
    fn _better_params ->
      with axis when axis in ["x", "y", "z"] <-
             (Compiler.ast2elixir(axis)) do
        FarmbotCeleryScript.SysCalls.log(
          "Finding home on the #{String.upcase(axis)} axis",
          true
        )

        FarmbotCeleryScript.SysCalls.find_home(axis)
      else
        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  # Expands home(all) into three home/1 calls
  def home(%{args: %{axis: "all", speed: speed}}) do
    fn _better_params ->
      FarmbotCeleryScript.SysCalls.log("Going to home on all axes", true)

      with speed when is_number(speed) <-
             (Compiler.ast2elixir(speed)),
           :ok <- FarmbotCeleryScript.SysCalls.home("z", speed),
           :ok <- FarmbotCeleryScript.SysCalls.home("y", speed) do
        FarmbotCeleryScript.SysCalls.home("x", speed)
      end
    end
  end

  # compiles home
  def home(%{args: %{axis: axis, speed: speed}}) do
    fn _better_params ->
      with axis when axis in ["x", "y", "z"] <-
             (Compiler.ast2elixir(axis)),
           speed when is_number(speed) <-
             (Compiler.ast2elixir(speed)) do
        FarmbotCeleryScript.SysCalls.log(
          "Going to home on the #{String.upcase(axis)} axis",
          true
        )

        FarmbotCeleryScript.SysCalls.home(axis, speed)
      else
        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  # Expands zero(all) into three zero/1 calls
  def zero(%{args: %{axis: "all"}}, _env) do
    fn _better_params ->
      FarmbotCeleryScript.SysCalls.log("Setting home for all axes", true)

      with :ok <- FarmbotCeleryScript.SysCalls.zero("z"),
           :ok <- FarmbotCeleryScript.SysCalls.zero("y") do
        FarmbotCeleryScript.SysCalls.zero("x")
      end
    end
  end

  # compiles zero
  def zero(%{args: %{axis: axis}}) do
    fn _better_params ->
      with axis when axis in ["x", "y", "z"] <-
             (Compiler.ast2elixir(axis)) do
        FarmbotCeleryScript.SysCalls.log(
          "Setting home for the #{String.upcase(axis)} axis",
          true
        )

        FarmbotCeleryScript.SysCalls.zero(axis)
      else
        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  # Expands calibrate(all) into three calibrate/1 calls
  def calibrate(%{args: %{axis: "all"}}, _env) do
    fn _better_params ->
      FarmbotCeleryScript.SysCalls.log("Finding length of all axes", true)

      with :ok <- FarmbotCeleryScript.SysCalls.calibrate("z"),
           :ok <- FarmbotCeleryScript.SysCalls.calibrate("y") do
        FarmbotCeleryScript.SysCalls.calibrate("x")
      else
        {:error, reason} -> {:error, reason}
      end
    end
  end

  # compiles calibrate
  def calibrate(%{args: %{axis: axis}}) do
    fn _better_params ->
      with axis when axis in ["x", "y", "z"] <-
             (Compiler.ast2elixir(axis)) do
        msg = "Determining length of the #{String.upcase(axis)} axis"
        FarmbotCeleryScript.SysCalls.log(msg, true)
        FarmbotCeleryScript.SysCalls.calibrate(axis)
      else
        {:error, reason} -> {:error, reason}
      end
    end
  end
end
