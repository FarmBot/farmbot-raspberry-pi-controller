defmodule FarmbotCore.Config.Repo.Migrations.AddEnigmasTable do
  use Ecto.Migration

  def change do
    create table("enigmas", primary_key: false) do
      add(:local_id, :binary_id, primary_key: true)
      add(:problem_tag, :string)
      add(:priority, :integer)
      timestamps(inserted_at: :created_at, type: :utc_datetime)
    end
  end
end
