defmodule ExMontyCadServer.Mcp.MemoryTools do
  @moduledoc """
  The tools that need all three engines, which is the reason this server exists.

  A part is read by quiddity, its percept is Monty's own sensor module's, and
  what comes out is the library a run loads. Each tool answers in the shape the
  protocol asks for — a sentence for the model, and the numbers as structured
  content — and a refusal is text saying what to try, never a crash.
  """

  alias MontyCad.{Percept, Training}

  @catalogue [
    %{
      "name" => "monty_cad_brief",
      "title" => "What is this part?",
      "description" =>
        "Opens a STEP part and answers what quiddity recognised in it: the " <>
          "feature families and how many of each, the faces no feature claims, " <>
          "and how many records it could not prove. This is the sentence to " <>
          "read before asking a part anything else.",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "path" => %{"type" => "string", "description" => "the part to open"}
        },
        "required" => ["path"]
      },
      "annotations" => %{"readOnlyHint" => true}
    },
    %{
      "name" => "monty_cad_sense",
      "title" => "What would the sensor perceive here?",
      "description" =>
        "Stands a patch sensor on the part at a point and looks along a " <>
          "direction, and answers what Monty's own observation processor makes " <>
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
          "writes the labelled library a Monty run loads: gzipped JSON lines, " <>
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
  def call("monty_cad_brief", arguments, state), do: brief(arguments, state)

  def call("monty_cad_sense", arguments, state), do: sense(arguments, state)

  def call("monty_cad_library", arguments, state), do: library(arguments, state)

  def call(name, _arguments, state), do: {:error, "no such tool: #{name}", state}

  defp brief(arguments, state) do
    with {:ok, path} <- required(arguments, "path"),
         {:ok, part} <- open(path),
         {:ok, recognition} <- features(part) do
      families = Quiddity.Recognition.families(recognition)
      unexplained = Quiddity.Recognition.unexplained_faces(recognition)
      unproved = Quiddity.Recognition.unproved(recognition)

      {:ok,
       %{
         text: """
         #{Path.basename(path)} — #{recognition.face_count} faces#{families_sentence(families)}
         #{unexplained_sentence(unexplained)} #{unproved_sentence(unproved)}
         """,
         structured: %{
           "path" => path,
           "faces" => recognition.face_count,
           "families" => Map.new(families),
           "unexplained_faces" => unexplained,
           "unproved_records" => length(unproved),
           "frame" => recognition.frame
         }
       }, state}
    else
      {:error, message} -> {:error, message, state}
    end
  end

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
      {:ok,
       %{
         text: """
         Wrote #{written.nodes} nodes to #{written.path} as "#{written.object_id}", from \
         #{written.visited} visits (#{written.skipped} skipped)#{families_sentence(Map.to_list(written.families))}.
         """,
         structured: Map.put(written, :path, out)
       }, state}
    else
      {:error, message} -> {:error, message, state}
    end
  end

  defp open(path) do
    case Quiddity.open(path) do
      {:ok, part} -> {:ok, part}
      {:error, error} -> {:error, Quiddity.Mcp.describe_error(error)}
    end
  end

  defp features(part) do
    case Quiddity.features(part) do
      {:ok, recognition} -> {:ok, recognition}
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

  defp unexplained_sentence([]), do: "No face is left unexplained."

  defp unexplained_sentence(faces) do
    "No feature claims #{length(faces)} face(s): #{Enum.join(faces, ", ")}."
  end

  defp unproved_sentence([]), do: "Every record it made is proved."

  defp unproved_sentence(records) do
    "#{length(records)} record(s) it could not prove."
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
