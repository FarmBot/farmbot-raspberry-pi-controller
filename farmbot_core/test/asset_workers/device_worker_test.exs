defmodule FarmbotCore.DeviceWorkerTest do
  use ExUnit.Case, async: false
  alias Farmbot.TestSupport.AssetFixtures
  alias FarmbotCore.Asset.Device
  alias FarmbotCore.AssetWorker
  alias Farmbot.TestSupport.CeleryScript.TestSysCalls

  def fresh_device(needs_reset \\ true) do
    params = %{needs_reset: needs_reset}
    assert %Device{} = dev = AssetFixtures.device_init(params)
    dev
  end

  describe "devices" do
    test "triggering of factory reset during init" do
      {:ok, _} = TestSysCalls.checkout()
      test_pid = self()
      dev = fresh_device()

      :ok =
        TestSysCalls.handle(TestSysCalls, fn
          kind, args ->
            send(test_pid, {kind, args})
            :ok
        end)

      {:ok, _pid} = AssetWorker.start_link(dev, [])
      assert_receive {:factory_reset, ["farmbot_os"]}
    end
  end

  test "triggering of factory reset during update" do
    {:ok, _} = TestSysCalls.checkout()
    test_pid = self()
    dev = fresh_device(false)

    :ok =
      TestSysCalls.handle(TestSysCalls, fn
        kind, args ->
          send(test_pid, {kind, args})
          :ok
      end)

    {:ok, pid} = AssetWorker.start_link(dev, [])
    refute_receive {:factory_reset, ["farmbot_os"]}

    GenServer.cast(pid, {:new_data, %{dev | needs_reset: true}})
    assert_receive {:factory_reset, ["farmbot_os"]}
  end
end
