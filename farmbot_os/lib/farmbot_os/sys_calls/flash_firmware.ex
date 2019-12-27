defmodule FarmbotOS.SysCalls.FlashFirmware do
  @moduledoc false

  alias FarmbotCore.{Asset, Asset.Private}
  alias FarmbotFirmware
  alias FarmbotCore.FirmwareTTYDetector
  import FarmbotFirmware.PackageUtils, only: [find_hex_file: 1, package_to_string: 1]
  require FarmbotCore.Logger
  require Logger

  def flash_firmware(package) do
    FarmbotCore.Logger.busy(2, "Flashing #{package_to_string(package)} firmware")

    with {:ok, hex_file} <- find_hex_file(package),
         {:ok, tty} <- find_tty(),
         _ <- FarmbotCore.Logger.debug(3, "found tty: #{tty} for firmware flash"),
         {:ok, fun} <- find_reset_fun(package),
         _ <- FarmbotCore.Logger.debug(3, "closing firmware transport before flash"),
         :ok <- FarmbotFirmware.close_transport(),
         _ <- FarmbotCore.Logger.debug(3, "starting firmware flash"),
         {_, 0} <- Avrdude.flash(hex_file, tty, fun) do
      FarmbotCore.Logger.success(2, "Firmware flashed successfully!")

      %{
        # firmware_hardware: package, 
        firmware_path: tty
      }
      |> Asset.update_fbos_config!()
      |> Private.mark_dirty!(%{})

      :ok
    else
      {:error, reason} when is_binary(reason) ->
        {:error, reason}

      {_, exit_code} when is_number(exit_code) ->
        {:error, "avrdude error: #{exit_code}"}
    end
  end

  defp find_tty() do
    case FirmwareTTYDetector.tty() do
      nil ->
        {:error,
         """
         No suitable TTY detected. Check cables and try again.
         """}

      tty ->
        {:ok, tty}
    end
  end

  defp find_reset_fun(_) do
    config = Application.get_env(:farmbot_firmware, FarmbotFirmware)

    if module = config[:reset] do
      Logger.error("using reset function: #{inspect(config)}")
      {:ok, &module.reset/0}
    else
      Logger.error("no reset function is going to be used #{inspect(config)}")
      {:ok, fn -> :ok end}
    end
  end
end
