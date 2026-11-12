defmodule ExMontyCadServer.Mcp.Tools do
  @moduledoc """
  The tools, as one catalogue over three engines.

  Each engine already answers the Model Context Protocol on its own: cadmpeg and
  quiddity each have a `Tools` module with a `catalogue/0`, a `call/3` and their
  own state. This server does not re-implement any of those answers — it decides
  which engine owns a tool name, and hands the call to it with that engine's own
  state. What it adds is `ExMontyCadServer.Mcp.MemoryTools`, the tools that need
  all three.

  Tool names carry their engine's prefix (`cadmpeg_`, `quiddity_`,
  `monty_cad_`), so a name says who answers it and two engines cannot claim the
  same one.
  """

  alias ExMontyCadServer.Mcp
  alias ExMontyCadServer.Mcp.{ClusterTools, MemoryTools}

  @doc "The tools of every engine, as the protocol wants them listed."
  @spec catalogue() :: [map()]
  def catalogue do
    Cadmpeg.Mcp.Tools.catalogue() ++
      Quiddity.Mcp.Tools.catalogue() ++
      MemoryTools.catalogue() ++
      ClusterTools.catalogue()
  end

  @doc "Every tool name this server answers."
  @spec names() :: [String.t()]
  def names, do: Enum.map(catalogue(), & &1["name"])

  @doc """
  One tool call: its answer and the state after it.

  An unknown name is an error a model can read and retry — the message names the
  tools there are, rather than only the one that was not.
  """
  @spec call(String.t(), map(), Mcp.state()) :: {atom(), term(), Mcp.state()}
  def call(name, arguments, state) when is_binary(name) and is_map(arguments) do
    case engine(name) do
      {key, module} -> dispatch(key, module, name, arguments, state)
      :none -> {:error, "`#{name}` is not one of the tools: #{Enum.join(names(), ", ")}", state}
    end
  end

  def call(name, _arguments, state) do
    {:error, "`#{inspect(name)}` is not one of the tools: #{Enum.join(names(), ", ")}", state}
  end

  defp dispatch(engine, module, name, arguments, state) do
    case module.call(name, arguments, Map.fetch!(state, engine)) do
      {:ok, answer, next} -> {:ok, answer, Map.put(state, engine, next)}
      {:error, message, next} -> {:error, message, Map.put(state, engine, next)}
    end
  end

  @doc """
  Which engine answers a tool name.

  The order is the order of the question: what this server adds first, then the
  geometry it was built from, then the reader underneath both. A name is looked
  up in each engine's own catalogue, because that is the only thing all three
  agree on — cadmpeg has no `names/0`, and inventing one here would be a second
  list to keep in step.
  """
  @spec engine(String.t()) :: {atom(), module()} | :none
  def engine(name) do
    Enum.find_value(engines(), :none, fn {engine, module} ->
      if name in names_of(module), do: {engine, module}
    end)
  end

  @doc "The engines, in the order a tool name is looked up in."
  @spec engines() :: [{atom(), module()}]
  def engines do
    [
      monty_cad: MemoryTools,
      cluster: ClusterTools,
      quiddity: Quiddity.Mcp.Tools,
      cadmpeg: Cadmpeg.Mcp.Tools
    ]
  end

  defp names_of(module), do: Enum.map(module.catalogue(), & &1["name"])
end
