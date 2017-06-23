defmodule Farmbot.ImageWatcherTest do
  use ExUnit.Case, async: false
  alias Farmbot.Auth
  alias Farmbot.Context

  setup_all do
    context = Context.new()
    Auth.purge_token(context.auth)

    # Makes sure the dirs are empty
    File.rm_rf "/tmp/images"
    File.mkdir "/tmp/images"
    Farmbot.ImageWatcher.force_upload(context)
    :ok = Auth.interim(context.auth, "admin@admin.com", "password123", "http://localhost:3000")
    {:ok, token} = Auth.try_log_in(context.auth)
    %{cs_context: context}
  end

  # test "uploads an image automagically" do
  #   img_path = "#{:code.priv_dir(:farmbot)}/static/farmbot_logo.png"
  #   use_cassette "good_image_upload" do
  #     File.cp! img_path, "/tmp/images/farmbot_logo.png"
  #   end
  # end
end
