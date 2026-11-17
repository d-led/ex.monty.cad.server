defmodule ExMontyCadServer.Mcp.MemoryTools do
  @moduledoc """
  The tools that need all three engines, which is the reason this server exists.

  A part is read by quiddity, its percept is the framework's own sensor module's, and
  what comes out is the library a run loads. Each tool answers in the shape the
  protocol asks for — a sentence for the model, and the numbers as structured
  content — and a refusal is text saying what to try, never a crash.

  ## How finely a part is sampled

  One tool here writes a memory of **one** part, and it samples at
  `Training.write/4`'s own dial: two millimetres unless the caller names a
  `spacing`. That is right for one part and it is not the whole rule — a memory
  of *several* parts compares them, so each has to be sampled at the same
  resolution relative to itself, which is `Training.spacing/1` and
  `Training.write_library/3` (`ex_monty_cad` 0.6.1). With a fixed two millimetres
  a part five times the size gets the same number of nodes over twenty-five times
  the area, and the denser graph wins the candidate search.

  A tool that builds a multi-part memory should therefore call
  `Training.write_library/3` rather than this one repeatedly. It is not here yet,
  and this note exists so the next person does not have to rediscover the reason.
  """

  alias MontyCad.{Percept, Training}

  alias ExMontyCadServer.Catalogue

  @catalogue [
    %{
      "name" => "monty_cad_sense",
      "title" => "What would the sensor perceive here?",
      "description" =>
        "Stands a patch sensor on the part at a point and looks along a " <>
          "direction, and answers what the framework's own observation processor " <>
          "makes " <>
          "of that frame: the node features a graph memory stores, which is the " <>
          "percept a run would have made at the same place.",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "path" => %{"type" => "string", "description" => "the part to sense"},
          "point" => %{
            "type" => "array",
            "items" => %{"type" => "number"},
            "description" => "where the sensor stands, in the part's own millimetres"
          },
          "normal" => %{
            "type" => "array",
            "items" => %{"type" => "number"},
            "description" => "which way it looks, as three numbers"
          },
          "distance" => %{
            "type" => "number",
            "description" => "how far it stands off the surface, in millimetres"
          }
        },
        "required" => ["path", "point", "normal"]
      },
      "annotations" => %{"readOnlyHint" => true}
    },
    %{
      "name" => "monty_cad_library",
      "title" => "Write the graph memory a run loads",
      "description" =>
        "Samples the part's surface, takes the percept at every visit, and " <>
          "writes the labelled library a run loads: gzipped JSON lines, " <>
          "one record per node, in the shape a graph learning module reads. The " <>
          "labels are the recognition's own, so they are facts rather than " <>
          "guesses.",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "path" => %{"type" => "string", "description" => "the part to sample"},
          "object" => %{
            "type" => "string",
            "description" => "what the memory is called — the name a recognition would answer"
          },
          "out" => %{"type" => "string", "description" => "where to write the library"},
          "spacing" => %{
            "type" => "number",
            "description" => "millimetres between visits"
          },
          "limit" => %{
            "type" => "integer",
            "description" => "the most visits to make"
          }
        },
        "required" => ["path", "object", "out"]
      },
      "annotations" => %{"idempotentHint" => false}
    },
    %{
      "name" => "monty_cad_libraries",
      "title" => "What has this server already learned?",
      "description" =>
        "Answers the memories this server has written, newest first: the object " <>
          "each is labelled as, the part it was made from, how many nodes it holds, " <>
          "and where the file is. This is the question to ask before sampling a " <>
          "part again.",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "limit" => %{
            "type" => "integer",
            "description" => "the most memories to answer with (default 20)"
          }
        }
      },
      "annotations" => %{"readOnlyHint" => true}
    }
  ]

  @doc "The tools, as the protocol wants them listed."
  @spec catalogue() :: [map()]
  def catalogue, do: @catalogue

  @doc "Every tool name this module answers."
  @spec names() :: [String.t()]
  def names, do: Enum.map(@catalogue, & &1["name"])

  @doc "One tool call: its answer and the state after it."
  @spec call(String.t(), map(), map()) :: {atom(), term(), map()}
  def call("monty_cad_sense", arguments, state), do: sense(arguments, state)

  def call("monty_cad_library", arguments, state), do: library(arguments, state)

  def call("monty_cad_libraries", arguments, state), do: libraries(arguments, state)

  def call(name, _arguments, state), do: {:error, "no such tool: #{name}", state}

  defp sense(arguments, state) do
    with {:ok, path} <- required(arguments, "path"),
         {:ok, point} <- point(arguments, "point"),
         {:ok, normal} <- point(arguments, "normal"),
         {:ok, part} <- open(path),
         {:ok, frame} <- frame(part, point, normal),
         {:ok, message} <- Percept.message(frame) do
      features = Percept.node_features(message)

      {:ok,
       %{
         text: """
         At #{inspect(point)} the sensor perceives #{length(Map.keys(features))} features: \
         #{Map.keys(features) |> Enum.sort() |> Enum.join(", ")}.
         """,
         structured: %{"path" => path, "point" => point, "features" => features}
       }, state}
    else
      {:error, message} -> {:error, message, state}
    end
  end

  defp library(arguments, state) do
    with {:ok, path} <- required(arguments, "path"),
         {:ok, object} <- required(arguments, "object"),
         {:ok, out} <- required(arguments, "out"),
         {:ok, part} <- open(path),
         {:ok, written} <- write(part, object, out, arguments) do
      recorded = record(part, path, written)

      {:ok,
       %{
         text: """
         Wrote #{written.nodes} nodes to #{written.path} as "#{written.object_id}", from \
         #{written.visited} visits (#{written.skipped} skipped)#{families_sentence(Map.to_list(written.families))}#{recorded_sentence(recorded)}.
         """,
         structured: Map.put(written, :path, out)
       }, state}
    else
      {:error, message} -> {:error, message, state}
    end
  end

  # The library file is written whether or not the catalogue takes it, so a
  # database that refuses is a sentence in the answer rather than a lost file.
  defp record(part, path, written) do
    attributes = %{
      path: path,
      name: Path.basename(path),
      digest: written.source_sha256,
      faces: Quiddity.Part.face_count(part),
      families: written.families
    }

    with {:ok, recorded_part} <- Catalogue.record_part(attributes),
         {:ok, _library} <- Catalogue.record_library(recorded_part, written) do
      :ok
    else
      {:error, changeset} -> {:error, describe_errors(changeset)}
    end
  end

  defp describe_errors(%Ecto.Changeset{errors: errors}) do
    Enum.map_join(errors, ", ", fn {field, {message, _opts}} -> "#{field} #{message}" end)
  end

  defp libraries(arguments, state) do
    limit = Map.get(arguments, "limit") || 20
    memories = Catalogue.libraries(limit)

    {:ok,
     %{
       text: """
       #{length(memories)} memory(s) recorded#{if memories == [], do: " — none has been written yet", else: ": " <> memories_sentence(memories)}
       """,
       structured: %{"libraries" => Enum.map(memories, &describe_memory/1)}
     }, state}
  end

  defp describe_memory(library) do
    %{
      "object_id" => library.object_id,
      "path" => library.path,
      "nodes" => library.nodes,
      "visited" => library.visited,
      "part" => library.part && library.part.name,
      "part_faces" => library.part && library.part.faces,
      "recorded_at" => library.inserted_at
    }
  end

  defp memories_sentence(memories) do
    Enum.map_join(memories, "; ", fn library ->
      "#{library.object_id} (#{library.nodes} nodes) from #{library.part && library.part.name}"
    end)
  end

  defp recorded_sentence(:ok), do: ". It is in the catalogue"

  defp recorded_sentence({:error, reason}),
    do: ". It is not in the catalogue, because #{reason}"

  defp open(path) do
    case Quiddity.open(path) do
      {:ok, part} -> {:ok, part}
      {:error, error} -> {:error, Quiddity.Mcp.describe_error(error)}
    end
  end

  defp frame(part, point, normal) do
    with {:ok, camera} <- Quiddity.Camera.patch(point, normal),
         {:ok, frame} <- Quiddity.frame(part, camera) do
      {:ok, frame}
    else
      {:error, error} -> {:error, Quiddity.Mcp.describe_error(error)}
    end
  end

  defp write(part, object, out, arguments) do
    options =
      [spacing: Map.get(arguments, "spacing"), limit: Map.get(arguments, "limit")]
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)

    case Training.write(part, object, out, options) do
      {:ok, written} -> {:ok, written}
      {:error, error} -> {:error, Quiddity.Mcp.describe_error(error)}
    end
  end

  defp families_sentence([]), do: " and no feature claims one"

  defp families_sentence(families) do
    named = Enum.map_join(families, ", ", fn {family, count} -> "#{family} #{count}" end)
    ": " <> named
  end

  defp required(arguments, name) do
    case Map.get(arguments, name) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _missing -> {:error, "`#{name}` is required, and a path or a name as text"}
    end
  end

  defp point(arguments, name) do
    case Map.get(arguments, name) do
      [x, y, z] when is_number(x) and is_number(y) and is_number(z) -> {:ok, [x, y, z]}
      _missing -> {:error, "`#{name}` is required, as three numbers"}
    end
  end
end
