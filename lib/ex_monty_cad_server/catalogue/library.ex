defmodule ExMontyCadServer.Catalogue.Library do
  @moduledoc """
  A graph memory this server wrote, and the part it was written from.

  The row is what makes the file findable a week later: the path it was written
  to, the object it is labelled as, and how much of the part it saw.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias ExMontyCadServer.Catalogue.Part

  schema "cad_libraries" do
    field(:object_id, :string)
    field(:path, :string)
    field(:nodes, :integer)
    field(:visited, :integer)

    belongs_to(:part, Part)

    timestamps(type: :utc_datetime)
  end

  @doc "What writing a library told us about it."
  @spec changeset(struct(), map()) :: Ecto.Changeset.t()
  def changeset(library, attributes) do
    library
    |> cast(attributes, [:part_id, :object_id, :path, :nodes, :visited])
    |> validate_required([:part_id, :object_id, :path, :nodes])
    |> foreign_key_constraint(:part_id)
  end
end
