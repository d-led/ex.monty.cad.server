defmodule ExMontyCadServer.Mcp.ClusterTools do
  @moduledoc """
  What the cluster offers, as two tools.

  A run on one node is made of modules another node has: an experiment, the
  learning modules it steps, the motor policies that decide where to sense next.
  These tools answer what there is and what each one says about itself, which is
  the question to ask before asking a plugin to do anything.
  """

  alias ExMontyCadServer.Cluster

  @catalogue [
    %{
      "name" => "cad_plugin_list",
      "title" => "What does the cluster offer?",
      "description" =>
        "Lists the plugins registered across the cluster — experiments, " <>
          "learning modules and motor policies — with the node that offers " <>
          "each one. Optionally narrowed to one kind.",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "kind" => %{
            "type" => "string",
            "enum" => Enum.map(Cluster.kinds(), &Atom.to_string/1),
            "description" => "only this kind"
          }
        }
      },
      "annotations" => %{"readOnlyHint" => true}
    },
    %{
      "name" => "cad_plugin_describe",
      "title" => "What is this plugin?",
      "description" =>
        "Asks one registered plugin what it says about itself: its version, " <>
          "whether it can be called from another node, and which engines it " <>
          "needs. A policy that reads a part must run where the part was " <>
          "opened, and this is where it says so.",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "name" => %{"type" => "string", "description" => "the plugin's name"},
          "kind" => %{
            "type" => "string",
            "enum" => Enum.map(Cluster.kinds(), &Atom.to_string/1),
            "description" => "the kind it is registered as"
          }
        },
        "required" => ["name", "kind"]
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
  def call("cad_plugin_list", arguments, state), do: list(arguments, state)

  def call("cad_plugin_describe", arguments, state), do: describe(arguments, state)

  def call(name, _arguments, state), do: {:error, "no such tool: #{name}", state}

  defp list(arguments, state) do
    case kinds(arguments) do
      {:ok, kinds} ->
        providers = Enum.flat_map(kinds, &Cluster.providers/1)

        {:ok,
         %{
           text: """
           #{length(providers)} plugin(s) on this cluster: #{listing(providers)}
           """,
           structured: %{"providers" => Enum.map(providers, &encode/1)}
         }, state}

      {:error, message} ->
        {:error, message, state}
    end
  end

  defp describe(arguments, state) do
    with {:ok, name} <- required(arguments, "name"),
         {:ok, kind} <- one_kind(arguments),
         {:ok, provider} <- Cluster.lookup(kind, name) do
      {:ok,
       %{
         text: """
         #{provider.name} — #{kind}, offered by #{provider.node}: #{spoken(provider.describe)}
         """,
         structured: encode(provider)
       }, state}
    else
      {:error, message} -> {:error, message, state}
    end
  end

  defp kinds(%{"kind" => kind}) do
    case one_kind(%{"kind" => kind}) do
      {:ok, kind} -> {:ok, [kind]}
      {:error, message} -> {:error, message}
    end
  end

  defp kinds(_arguments), do: {:ok, Cluster.kinds()}

  defp one_kind(%{"kind" => kind}) do
    if kind in Enum.map(Cluster.kinds(), &Atom.to_string/1),
      do: {:ok, String.to_existing_atom(kind)},
      else: {:error, "`kind` is one of: #{Enum.join(Cluster.kinds(), ", ")}"}
  end

  defp one_kind(_arguments),
    do: {:error, "`kind` is required, and one of: #{Enum.join(Cluster.kinds(), ", ")}"}

  defp listing([]), do: "nothing is registered"

  defp listing(providers) do
    providers
    |> Enum.group_by(& &1.kind)
    |> Enum.sort()
    |> Enum.map_join("; ", fn {kind, of_kind} ->
      names = of_kind |> Enum.map(& &1.name) |> Enum.uniq() |> Enum.join(", ")
      "#{kind}: #{names}"
    end)
  end

  defp spoken({:ok, describe}) do
    describe
    |> Enum.sort_by(fn {key, _value} -> key end)
    |> Enum.map_join(", ", fn {key, value} -> "#{key} #{inspect(value)}" end)
  end

  defp spoken({:error, reason}), do: "it did not answer: #{reason}"

  defp encode(provider) do
    %{
      "name" => provider.name,
      "kind" => Atom.to_string(provider.kind),
      "node" => Atom.to_string(provider.node),
      "describe" => describe_of(provider.describe)
    }
  end

  defp describe_of({:ok, describe}), do: describe
  defp describe_of({:error, reason}), do: %{"error" => reason}

  defp required(arguments, name) do
    case Map.get(arguments, name) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _missing -> {:error, "`#{name}` is required, and a name as text"}
    end
  end
end
