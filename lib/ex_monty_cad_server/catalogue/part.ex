defmodule ExMontyCadServer.Catalogue.Part do
  @moduledoc """
  A part this server has made a memory of.

  It is keyed by the digest of the file, not by its path: the same part copied
  to another folder is the same part, and a part that was edited is a different
  one — which is exactly what a memory made from it is true of.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias ExMontyCadServer.Catalogue.Library

  schema "cad_parts" do
    field(:path, :string)
    field(:name, :string)
    field(:digest, :string)
    field(:faces, :integer)
    # Which feature family the recognition found, and how many of each.
    field(:families, :map, default: %{})

    has_many(:libraries, Library)

    timestamps(type: :utc_datetime)
  end

  @doc "What opening a part tells us about it."
  @spec changeset(struct(), map()) :: Ecto.Changeset.t()
  def changeset(part, attributes) do
    part
    |> cast(attributes, [:path, :name, :digest, :faces, :families])
    |> validate_required([:path, :name, :digest, :faces])
    |> unique_constraint(:digest)
  end
end
