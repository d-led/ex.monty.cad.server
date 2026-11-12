defmodule ExMontyCadServer.Mcp do
  @moduledoc """
  One Model Context Protocol server over three engines, because a question about
  a CAD part runs through all of them.

  `cadmpeg` reads the file and says what was lost reading it. `quiddity` takes
  the geometry and names what is in it, so a face is a hole rather than a
  surface. `MontyCad` takes a frame of that geometry and answers what Monty's own
  sensor module would perceive there, and writes the labelled library a run
  loads.

  ## Transport

  `handle/2` is the whole server: a JSON-RPC message in, a reply (or `nil` for a
  notification) and the state after it. The stdio task `mix
  ex_monty_cad_server.mcp` loops over it, and `POST /mcp` hands it the decoded
  body. One implementation, so the two transports cannot drift.

  ## State

  Each engine keeps what it remembers — the documents cadmpeg has opened, the
  parts quiddity has read — and this server keeps one state per engine, keyed by
  engine. A tool call is answered by the engine that owns the tool, so a second
  question about the same file does not read it again.
  """

  alias ExMontyCadServer.Mcp.Tools

  @protocol_versions ~w(2025-06-18 2025-03-26 2024-11-05)

  @typedoc "What the server remembers between messages: one state per engine."
  @type state :: %{
          cadmpeg: map(),
          quiddity: map(),
          monty_cad: map(),
          cluster: map()
        }

  @doc "The protocol revisions this server speaks, newest first."
  @spec protocol_versions() :: [String.t()]
  def protocol_versions, do: @protocol_versions

  @doc "The state a new server starts with."
  @spec fresh() :: state()
  def fresh do
    %{
      cadmpeg: Cadmpeg.Mcp.fresh(),
      # `%{parts: %{}}` is the state `Quiddity.Mcp.serve/0` starts with; the
      # package has no `fresh/0` yet, which is the one thing this server knows
      # about another module's internals.
      quiddity: %{parts: %{}},
      monty_cad: %{},
      # The cluster tools answer from `:pg`, which the cluster keeps; nothing to
      # remember between messages.
      cluster: %{}
    }
  end

  @doc """
  Reads JSON-RPC messages from stdin and writes answers to stdout until stdin
  closes.

  Notifications are answered with nothing, which is what the transport says.
  """
  @spec serve() :: :ok
  def serve do
    _ =
      IO.stream(:stdio, :line)
      |> Enum.reduce(fresh(), fn line, state ->
        {reply, state} = handle(String.trim_trailing(line), state)
        if reply, do: IO.puts(reply)
        state
      end)

    :ok
  end

  @doc """
  One message, as the text a client wrote: the reply (or `nil` for a
  notification) and the state after it.

  `nil` for a blank line, and for a line that is not JSON — a transport that
  crashes on garbage is a transport nobody can debug.
  """
  @spec handle(String.t() | nil, state()) :: {String.t() | nil, state()}
  def handle(line, state) when line in ["", " ", nil], do: {nil, state}

  def handle(line, state) when is_binary(line) do
    case Jason.decode(line) do
      {:ok, message} when is_map(message) -> message(message, state)
      {:ok, _not_an_object} -> {error_reply(nil, -32_600, "not a JSON-RPC object"), state}
      {:error, _reason} -> {error_reply(nil, -32_700, "the line is not JSON"), state}
    end
  end

  @doc """
  One message, already decoded — what a transport that parses the body itself
  hands over, so the JSON is read once.
  """
  @spec message(map(), state()) :: {String.t() | nil, state()}
  def message(%{"method" => method, "id" => id} = request, state) when is_binary(method) do
    case result(method, Map.get(request, "params", %{}), state) do
      {:ok, result, state} -> {reply(id, result), state}
      {:error, message} -> {error_reply(id, -32_601, message), state}
    end
  end

  def message(%{"method" => method} = request, state) when is_binary(method) do
    # A notification: do the work, answer nothing.
    _ = result(method, Map.get(request, "params", %{}), state)
    {nil, state}
  end

  def message(_message, state), do: {error_reply(nil, -32_600, "no method"), state}

  defp result("initialize", params, state) do
    {:ok,
     %{
       "protocolVersion" => negotiate(Map.get(params, "protocolVersion")),
       "capabilities" => %{"tools" => %{"listChanged" => false}},
       "serverInfo" => %{
         "name" => "ex-monty-cad-server",
         "title" => "CAD, named, and as a Monty graph memory",
         "version" => version()
       },
       "instructions" => instructions()
     }, state}
  end

  defp result("tools/list", _params, state), do: {:ok, %{"tools" => Tools.catalogue()}, state}

  defp result("tools/call", params, state) do
    name = Map.get(params, "name")
    arguments = Map.get(params, "arguments") || %{}

    case Tools.call(name, arguments, state) do
      {:ok, %{text: text, structured: structured}, state} ->
        {:ok,
         %{
           "content" => [%{"type" => "text", "text" => text}],
           "structuredContent" => structured,
           "isError" => false
         }, state}

      {:error, message, state} ->
        {:ok, %{"content" => [%{"type" => "text", "text" => message}], "isError" => true}, state}
    end
  end

  defp result("ping", _params, state), do: {:ok, %{}, state}

  defp result(method, _params, _state), do: {:error, "unknown method: #{method}"}

  defp negotiate(requested) do
    if requested in @protocol_versions, do: requested, else: hd(@protocol_versions)
  end

  defp instructions do
    """
    This server answers questions about a CAD part, and turns one into a graph
    memory that Monty can match against.

    A FILE: cadmpeg_formats says which formats this build reads and writes, and
    cadmpeg_inspect opens a path and answers the decode report — what was
    transferred and every loss with its reason. "It opened" and "it opened
    faithfully" are different answers.

    WHAT IS IN IT: monty_cad_brief opens the part and answers what quiddity
    recognised — the feature families and how many of each, and the faces no
    feature claims — which is the sentence a model needs before asking anything
    else.

    WHERE THE SENSOR WOULD STAND: monty_cad_sense takes a point and a direction
    and answers what Monty's own sensor module would perceive there: the node
    features a graph memory stores.

    A MEMORY: monty_cad_library samples the part's surface, takes that percept at
    every visit, and writes the library a run loads — an object id, a node count,
    and how many nodes each feature family contributed.

    THE GEOMETRY UNDERNEATH: the quiddity tools answer a face, a ray, a frame, a
    mesh and the surface samples directly, for a model that wants the numbers
    rather than a summary.

    WHAT A RUN IS MADE OF: cad_plugin_list says which experiments, learning
    modules and motor policies the cluster offers, and cad_plugin_describe asks
    one of them about itself — including whether it can be called from another
    node, which a policy that reads a part cannot.

    Paths are the interface. A native format that keeps parts of itself in files
    beside it is read against its own directory, which is why a file is named
    rather than bytes.
    """
  end

  defp version do
    case Application.spec(:ex_monty_cad_server, :vsn) do
      nil -> "dev"
      version -> to_string(version)
    end
  end

  defp reply(id, result) do
    Jason.encode!(%{"jsonrpc" => "2.0", "id" => id, "result" => result})
  end

  defp error_reply(id, code, message) do
    Jason.encode!(%{
      "jsonrpc" => "2.0",
      "id" => id,
      "error" => %{"code" => code, "message" => message}
    })
  end
end
