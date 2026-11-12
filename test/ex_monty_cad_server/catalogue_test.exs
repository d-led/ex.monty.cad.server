defmodule ExMontyCadServer.CatalogueTest do
  @moduledoc """
  What the catalogue promises: a part is one row per file, and the memories are
  read back in the order they were made.
  """
  use ExMontyCadServer.DataCase, async: true

  @part %{
    path: "/parts/bracket.step",
    name: "bracket.step",
    digest: "3f2a",
    faces: 9,
    families: %{"bosses" => 1, "holes" => 1}
  }

  test "a part opened twice from two folders is one part" do
    {:ok, first} = Catalogue.record_part(@part)

    {:ok, second} =
      Catalogue.record_part(%{@part | path: "/elsewhere/bracket.step"})

    assert second.id == first.id
    assert second.path == "/parts/bracket.step"
  end

  test "a part that was edited is a different part" do
    {:ok, first} = Catalogue.record_part(@part)
    {:ok, second} = Catalogue.record_part(%{@part | digest: "9c81", path: "/parts/bracket2.step"})

    refute second.id == first.id
  end

  test "the memories are read newest first, with the part each was made from" do
    {:ok, part} = Catalogue.record_part(@part)

    for {object, nodes} <- [{"plate", 12}, {"plate again", 30}] do
      {:ok, _library} =
        Catalogue.record_library(part, %{
          object_id: object,
          path: "/libraries/#{object}.jsonl.gz",
          nodes: nodes,
          visited: 40
        })
    end

    assert [newest, oldest] = Catalogue.libraries()
    assert newest.object_id == "plate again"
    assert newest.part.name == "bracket.step"
    assert oldest.object_id == "plate"
  end

  test "a memory does not outlive the part it was made from" do
    {:ok, part} = Catalogue.record_part(@part)

    {:ok, _library} =
      Catalogue.record_library(part, %{
        object_id: "plate",
        path: "/libraries/plate.jsonl.gz",
        nodes: 12,
        visited: 40
      })

    {:ok, _deleted} = ExMontyCadServer.Repo.delete(part)

    assert Catalogue.libraries() == []
  end
end
