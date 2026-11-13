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
      {:ok, kinds} -> listed(Enum.flat_map(kinds, &Cluster.providers/1), state)
      {:error, message} -> {:error, message, state}
    end
  end

  defp listed(providers, state) do
    {:ok,
     %{text: summary(providers), structured: %{"providers" => Enum.map(providers, &encode/1)}},
     state}
  end

  # A node that takes no part in a cluster, and a node that was never in one, have
  # nothing for a different reason, and "0 plugins" reads as "nothing is offered
  # anywhere" for both. So the sentence says which it is, and names the fix — a
  # variable, not a colleague.
  #
  # The facts are passed in rather than read here because they are the VM's: a test
  # that wants the sentence for a node outside a cluster cannot make this VM stop
  # being in one, and an untested sentence is how the misleading one survived.
  @typedoc """
  What decides how the list is said: whether this node takes part at all, and
  whether it is in a cluster.
  """
  @type facts :: %{discovery: boolean(), discovery_var: String.t() | nil, clustered: boolean()}

  @doc """
  The answer to `cad_plugin_list`, as a sentence.

  `facts/1` is the default, which is what the tool uses; a test passes its own.
  """
  @spec summary([Cluster.provider()], facts()) :: String.t()
  def summary(providers, facts \\ facts())

  def summary(_providers, %{discovery: false, discovery_var: var}) do
    "plugin discovery is off on this node (PLUGIN_DISCOVERY=#{inspect(var)}), so it " <>
      "joined no cluster and offers nothing. `PLUGIN_DISCOVERY=pg` is how it takes part."
  end

  def summary(providers, %{clustered: false}) do
    "#{length(providers)} plugin(s) on this node: #{listing(providers)}. It is named " <>
      "#{Node.self()}, which is not part of a cluster — a node without a name reaches " <>
      "no other node, so a plugin elsewhere cannot be seen from here. `NODE_NAME` and " <>
      "`NODE_COOKIE` are what join one; `elixir --sname cad -S mix` does the same in " <>
      "development."
  end

  def summary(providers, _facts) do
    "#{length(providers)} plugin(s) on this cluster: #{listing(providers)}"
  end

  @doc "The facts `summary/2` reads, as this VM has them."
  @spec facts() :: facts()
  def facts do
    %{
      discovery: MontyPlugin.Registry.enabled?(),
      discovery_var: System.get_env("PLUGIN_DISCOVERY"),
      clustered: Node.alive?()
    }
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
      names = of_kind |> Enum.map(&named/1) |> Enum.uniq() |> Enum.join(", ")
      "#{kind}: #{names}"
    end)
  end

  # A plugin whose answer cannot be used is named as such in the sentence, not
  # left beside the others as though it were a choice: a model reads this line,
  # and calling it would fail for a reason that says nothing about the plugin.
  defp named(%{name: name, describe: {:ok, _describe}}), do: name
  defp named(%{name: name, describe: {:error, _reason}}), do: name <> " (cannot be used)"

  defp spoken({:ok, describe}) do
    describe
    |> Enum.sort_by(fn {key, _value} -> key end)
    |> Enum.map_join(", ", fn {key, value} -> "#{key} #{inspect(value)}" end)
  end

  defp spoken({:error, reason}), do: "it cannot be used: #{reason}"

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
