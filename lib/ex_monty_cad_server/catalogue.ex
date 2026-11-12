defmodule ExMontyCadServer.Catalogue do
  @moduledoc """
  What this server remembers: the parts it has made a memory of, and the
  memories it made.

  The tables are a record of facts the engines produced, not a second copy of
  them: a part row says which file (by digest), how many faces and which
  families; a library row says which file was written, for which object, and how
  many nodes it holds. Everything else — geometry, features, the nodes
  themselves — stays where it was made, and is asked for again rather than
  stored twice.
  """

  import Ecto.Query, only: [from: 2]

  alias ExMontyCadServer.Catalogue.{Library, Part}
  alias ExMontyCadServer.Repo

  @doc """
  Records a part, or answers the row that is already there for the same file.

  A part is the same part whatever folder it was opened from, so the digest is
  the key: recognising the same file twice adds nothing.
  """
  @spec record_part(map()) :: {:ok, struct()} | {:error, Ecto.Changeset.t()}
  def record_part(attributes) do
    changeset = Part.changeset(%Part{}, attributes)

    with {:ok, part} <- Repo.insert(changeset, on_conflict: :nothing, conflict_target: :digest) do
      case part.id do
        nil -> {:ok, Repo.get_by!(Part, digest: attributes.digest)}
        _id -> {:ok, part}
      end
    end
  end

  @doc "Records a memory written from a part."
  @spec record_library(struct(), map()) :: {:ok, struct()} | {:error, Ecto.Changeset.t()}
  def record_library(%Part{id: part_id}, written) do
    %Library{}
    |> Library.changeset(%{
      part_id: part_id,
      object_id: written.object_id,
      path: written.path,
      nodes: written.nodes,
      visited: written.visited
    })
    |> Repo.insert()
  end

  @doc "The memories written, newest first, with the part each was made from."
  @spec libraries(pos_integer()) :: [struct()]
  def libraries(limit \\ 20) do
    from(library in Library,
      order_by: [desc: library.inserted_at, desc: library.id],
      limit: ^limit,
      preload: [:part]
    )
    |> Repo.all()
  end
end
