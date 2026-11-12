defmodule ExMontyCadServer.Repo.Migrations.CreateCatalogue do
  use Ecto.Migration

  def change do
    create table(:cad_parts) do
      add :path, :string, null: false
      add :name, :string, null: false
      # The digest of the file's bytes: the part's identity, so the same part
      # opened from another folder is one row rather than two.
      add :digest, :string, null: false
      add :faces, :integer, null: false
      add :families, :map, null: false, default: %{}

      timestamps(type: :utc_datetime)
    end

    create unique_index(:cad_parts, [:digest])

    create table(:cad_libraries) do
      add :part_id, references(:cad_parts, on_delete: :delete_all), null: false
      add :object_id, :string, null: false
      add :path, :string, null: false
      add :nodes, :integer, null: false
      add :visited, :integer

      timestamps(type: :utc_datetime)
    end

    create index(:cad_libraries, [:part_id])
  end
end
