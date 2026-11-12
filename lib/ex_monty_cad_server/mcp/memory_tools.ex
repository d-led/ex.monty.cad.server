defmodule ExMontyCadServer.Mcp.MemoryTools do
  @moduledoc """
  The tools that need all three engines, which is the reason this server exists.

  A part is read by quiddity, its percept is Monty's own sensor module's, and
  what comes out is the library a run loads. Each tool answers in the shape the
  protocol asks for — a sentence for the model, and the numbers as structured
  content — and a refusal is text saying what to try, never a crash.
  """

  alias MontyCad.{Percept, Training}

  # How far a proximity query looks when it is not told, and how many features it
  # answers with: enough to reach the neighbouring features of an ordinary part,
  # and few enough to read.
  @near_radius 25.0
  @near_limit 10

  # How far a "what is ahead" query looks, and how wide a cone counts as ahead.
  @search_radius 500.0
  @search_angle 45.0

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
      "name" => "monty_cad_features_near",
      "title" => "Which features are near this point?",
      "description" =>
        "Opens a STEP part, recognises its features, and answers which of them " <>
          "sit within a radius of a point, nearest first — a hole, a boss, a " <>
          "chamfer by name and by distance. The distance is to the anchor the " <>
          "recognition gives a feature (a boss's axis point, for instance), not " <>
          "to its surface, so it orders features rather than measuring gaps.",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "path" => %{"type" => "string", "description" => "the part to open"},
          "point" => %{
            "type" => "array",
            "items" => %{"type" => "number"},
            "description" => "the point to measure from, in the part's millimetres"
          },
          "radius" => %{
            "type" => "number",
            "description" => "how far to look, in millimetres (default 25)"
          },
          "limit" => %{
            "type" => "integer",
            "description" => "the most features to answer with (default 10)"
          }
        },
        "required" => ["path", "point"]
      },
      "annotations" => %{"readOnlyHint" => true}
    },
    %{
      "name" => "monty_cad_next_feature",
      "title" => "What is ahead?",
      "description" =>
        "Opens a STEP part, recognises its features, and answers which of them " <>
          "lie ahead of a point along a direction — within a cone, nearest first, " <>
          "with the distance and the angle off the direction for each. This is " <>
          "the move a policy makes when it jumps from one feature to the next.",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "path" => %{"type" => "string", "description" => "the part to open"},
          "point" => %{
            "type" => "array",
            "items" => %{"type" => "number"},
            "description" => "where the move starts, in the part's millimetres"
          },
          "direction" => %{
            "type" => "array",
            "items" => %{"type" => "number"},
            "description" => "which way the move goes, as three numbers"
          },
          "angle" => %{
            "type" => "number",
            "description" => "how wide a cone counts as ahead, in degrees (default 45)"
          },
          "radius" => %{
            "type" => "number",
            "description" => "how far to look, in millimetres (default 500)"
          },
          "limit" => %{
            "type" => "integer",
            "description" => "the most features to answer with (default 10)"
          }
        },
        "required" => ["path", "point", "direction"]
      },
      "annotations" => %{"readOnlyHint" => true}
    },
    %{
      "name" => "monty_cad_on_face",
      "title" => "What am I on?",
      "description" =>
        "Opens a STEP part and answers which feature claims a face — the id, the " <>
          "family and the feature's own parameters — or says that no feature " <>
          "claims it, and whether that is the body, a refusal, or a face the " <>
          "recognition could not explain. This is the question a sensor standing " <>
          "on the surface asks.",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "path" => %{"type" => "string", "description" => "the part to open"},
          "face" => %{
            "type" => "integer",
            "description" => "the face's own number, from 0"
          }
        },
        "required" => ["path", "face"]
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

  def call("monty_cad_features_near", arguments, state), do: features_near(arguments, state)

  def call("monty_cad_next_feature", arguments, state), do: next_feature(arguments, state)

  def call("monty_cad_on_face", arguments, state), do: on_face(arguments, state)

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

  # The features near a point, nearest first. A feature is placed by the anchor
  # the recognition gives it, so this orders features — which is what a policy
  # choosing where to sense next needs — rather than measuring the gap to a
  # surface, which would need the geometry rather than the record.
  defp features_near(arguments, state) do
    with {:ok, path} <- required(arguments, "path"),
         {:ok, point} <- point(arguments, "point"),
         {:ok, part} <- open(path),
         {:ok, recognition} <- features(part) do
      radius = Map.get(arguments, "radius") || @near_radius
      limit = Map.get(arguments, "limit") || @near_limit

      {placed, unplaced} =
        Enum.split_with(recognition.records, fn record -> not is_nil(anchor(record)) end)

      near =
        placed
        |> Enum.map(fn record -> {distance(point, anchor(record)), record} end)
        |> Enum.filter(fn {how_far, _record} -> how_far <= radius end)
        |> Enum.sort_by(fn {how_far, _record} -> how_far end)
        |> Enum.take(limit)
        |> Enum.map(fn {how_far, record} ->
          %{
            "id" => record["id"],
            "family" => record["family"],
            "distance" => Float.round(how_far, 3),
            "anchor" => anchor(record),
            "parameters" => record["parameters"]
          }
        end)

      {:ok,
       %{
         text: """
         #{length(near)} feature(s) within #{radius} mm of #{inspect(point)}: \
         #{near_sentence(near)}#{unplaced_sentence(length(unplaced))}
         """,
         structured: %{
           "path" => path,
           "point" => point,
           "radius" => radius,
           "features" => near
         }
       }, state}
    else
      {:error, message} -> {:error, message, state}
    end
  end

  # What is ahead: the features whose anchor lies inside a cone around a
  # direction, nearest first. The move a policy makes when it jumps from one
  # feature to the next, and the reason the answer carries both the distance and
  # the angle — the nearest one straight ahead and the nearest one sideways are
  # different moves.
  defp next_feature(arguments, state) do
    with {:ok, path} <- required(arguments, "path"),
         {:ok, point} <- point(arguments, "point"),
         {:ok, direction} <- direction(arguments, "direction"),
         {:ok, part} <- open(path),
         {:ok, recognition} <- features(part) do
      radius = Map.get(arguments, "radius") || @search_radius
      cone = Map.get(arguments, "angle") || @search_angle
      limit = Map.get(arguments, "limit") || @near_limit

      ahead =
        recognition
        |> placed()
        |> Enum.map(fn {record, anchor} ->
          %{
            "id" => record["id"],
            "family" => record["family"],
            "distance" => distance(point, anchor),
            "angle" => angle_between(point, anchor, direction),
            "anchor" => anchor,
            "parameters" => record["parameters"]
          }
        end)
        |> Enum.filter(
          &(&1["distance"] > 0.0 and &1["distance"] <= radius and &1["angle"] <= cone)
        )
        |> Enum.sort_by(&{&1["distance"], &1["angle"]})
        |> Enum.take(limit)
        |> Enum.map(fn feature ->
          %{
            feature
            | "distance" => Float.round(feature["distance"], 3),
              "angle" => Float.round(feature["angle"], 3)
          }
        end)

      {:ok,
       %{
         text: """
         #{length(ahead)} feature(s) ahead of #{inspect(point)} along #{inspect(direction)}, \
         inside #{cone}°: #{near_sentence(ahead)}
         """,
         structured: %{
           "path" => path,
           "point" => point,
           "direction" => direction,
           "angle" => cone,
           "radius" => radius,
           "features" => ahead
         }
       }, state}
    else
      {:error, message} -> {:error, message, state}
    end
  end

  # What a sensor standing on a face is on: the feature that claims it, by the
  # recognition's own accounting — or that it is body, refused, unexplained.
  defp on_face(arguments, state) do
    with {:ok, path} <- required(arguments, "path"),
         {:ok, part} <- open(path),
         {:ok, recognition} <- features(part),
         {:ok, face} <- face(arguments, recognition) do
      case Quiddity.Recognition.owner(recognition, face) do
        id when is_binary(id) ->
          record = Quiddity.Recognition.record(recognition, id) || %{}

          {:ok,
           %{
             text: "Face #{face} belongs to #{id} (#{record["family"]}).",
             structured: %{
               "face" => face,
               "feature" => id,
               "family" => record["family"],
               "parameters" => record["parameters"]
             }
           }, state}

        owner ->
          {:ok,
           %{
             text: "No feature claims face #{face}: the recognition calls it #{owner}.",
             structured: %{
               "face" => face,
               "feature" => nil,
               "family" => nil,
               "owner" => Atom.to_string(owner)
             }
           }, state}
      end
    else
      {:error, message} -> {:error, message, state}
    end
  end

  # The records that can be placed, with the anchor each one carries.
  defp placed(recognition) do
    recognition.records
    |> Enum.map(fn record -> {record, anchor(record)} end)
    |> Enum.reject(fn {_record, anchor} -> is_nil(anchor) end)
  end

  defp angle_between(point, anchor, direction) do
    vector = Enum.zip(anchor, point) |> Enum.map(fn {a, p} -> a - p end)
    cosine = dot(vector, direction) / (norm(vector) * norm(direction))

    # A dot product of unit vectors lands just outside [-1, 1] on rounding, and
    # `acos` of that is an arithmetic error rather than a result.
    :math.acos(min(1.0, max(-1.0, cosine))) * 180.0 / :math.pi()
  end

  defp dot(a, b), do: a |> Enum.zip(b) |> Enum.map(fn {x, y} -> x * y end) |> Enum.sum()

  defp norm(vector), do: :math.sqrt(dot(vector, vector))

  # A feature's own anchor: the point its record already carries in its
  # parameters — a boss's axis point, a hole's mouth.
  defp anchor(%{"parameters" => %{"location" => [x, y, z]}})
       when is_number(x) and is_number(y) and is_number(z),
       do: [x, y, z]

  defp anchor(_record), do: nil

  defp distance([ax, ay, az], [bx, by, bz]),
    do: :math.sqrt((ax - bx) ** 2 + (ay - by) ** 2 + (az - bz) ** 2)

  defp near_sentence([]), do: "none of them"

  defp near_sentence(features) do
    Enum.map_join(features, "; ", fn feature ->
      "#{feature["id"]} (#{feature["family"]}) at #{feature["distance"]} mm"
    end)
  end

  defp unplaced_sentence(0), do: ""
  defp unplaced_sentence(count), do: ". #{count} feature(s) give no anchor to measure from"

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

  # A direction has a length in it; zero has none, and a cone around it is every
  # direction at once — which is not the question that was asked.
  defp direction(arguments, name) do
    with {:ok, [x, y, z] = vector} <- point(arguments, name),
         true <- norm(vector) > 0.0 do
      {:ok, [x, y, z]}
    else
      false -> {:error, "`#{name}` is a direction, and nought has none"}
      {:error, message} -> {:error, message}
    end
  end

  defp face(arguments, recognition) do
    with {:ok, face} <- required_integer(arguments, "face"),
         true <- face < recognition.face_count do
      {:ok, face}
    else
      false -> {:error, "`face` is one of 0..#{recognition.face_count - 1}"}
      {:error, message} -> {:error, message}
    end
  end

  defp required_integer(arguments, name) do
    case Map.get(arguments, name) do
      value when is_integer(value) and value >= 0 -> {:ok, value}
      _missing -> {:error, "`#{name}` is required, as a whole number from nought"}
    end
  end
end
