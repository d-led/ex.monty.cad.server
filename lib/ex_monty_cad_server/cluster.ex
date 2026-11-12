defmodule ExMontyCadServer.Cluster do
  @moduledoc """
  What a cluster of these nodes offers, by name, on every node.

  `:pg` rather than `Registry`: a `Registry` names processes on the node that
  started it and knows nothing of the others, while `:pg` is OTP's cluster-wide
  process group — a name joined on one node is visible on all of them, and a node
  that goes down takes its names with it.

  ## What a provider is

  A plugin is a process, and it answers one question about itself:

      def handle_call(:describe, _from, state) do
        {:reply, %{
           "name" => "feature_following",
           "kind" => :motor_policy,
           "version" => "0.1.0",
           # `:owner_only` — it reads a part's B-rep, and a B-rep handle is a
           # resource in the memory of the node that opened it.
           "placement" => :owner_only,
           "needs" => [:quiddity]
         }, state}
      end

  The three kinds are the three things a run is made of: an experiment, the
  learning modules it steps, and the motor policies that decide where to sense
  next. A provider is registered under one of them.

  ## Placement is not decoration

  A learning module runs thousands of operations a step over hypotheses and
  a k-d tree; calling it across nodes would be transported sound and locally
  useless, so the honest advertisement is a version and a capability, and the
  caller compiles the module in. An experiment or a motor policy is called once
  per step, which is what makes a remote call free — and a policy that consults
  quiddity *must* be remote-called, because the part it reads cannot leave the
  node that opened it. `:owner_only` says so, and `lookup/2` keeps the node, so a
  caller never has to discover it by crashing.
  """

  @scope :ex_monty_cad_server
  @kinds [:experiment, :learning_module, :motor_policy]
  @timeout 5_000

  @typedoc "The three things a run is made of."
  @type kind :: :experiment | :learning_module | :motor_policy

  @typedoc """
  One provider: where to call it, and what it says it is.

  `describe` is `{:ok, map}` when the plugin answered and `{:error, reason}` when
  it did not — a provider that has gone quiet is still listed, because a cluster
  that hides one is a cluster where "nothing there" and "there but silent" look
  the same.
  """
  @type provider :: %{
          kind: kind(),
          name: String.t(),
          node: node(),
          pid: pid(),
          describe: {:ok, map()} | {:error, String.t()}
        }

  @doc "The kinds a provider can be registered as."
  @spec kinds() :: [kind()]
  def kinds, do: @kinds

  @doc """
  Offers a process under a name, on this node and therefore on every node.
  """
  @spec register(kind(), String.t(), pid()) :: :ok
  def register(kind, name, pid) when kind in @kinds and is_binary(name) and is_pid(pid) do
    :pg.join(@scope, group(kind, name), pid)
  end

  @doc "Withdraws an offer."
  @spec unregister(kind(), String.t(), pid()) :: :ok
  def unregister(kind, name, pid) when kind in @kinds and is_binary(name) and is_pid(pid) do
    :pg.leave(@scope, group(kind, name), pid)
  end

  @doc """
  Every provider of a kind, across the cluster, in no particular order.

  One plugin registered on two nodes appears twice, which is the truth: the
  caller picks, and the node it picks is the node the work happens on.
  """
  @spec providers(kind()) :: [provider()]
  def providers(kind) when kind in @kinds do
    @scope
    |> :pg.which_groups()
    |> Enum.filter(&match?({^kind, _name}, &1))
    |> Enum.flat_map(fn {^kind, name} = group ->
      group |> members() |> Enum.map(&provider(kind, name, &1))
    end)
  end

  @doc """
  The one provider under a name.

  A name nobody offers is an error that names the ones there are, because the
  caller is usually a model that can pick another.
  """
  @spec lookup(kind(), String.t()) :: {:ok, provider()} | {:error, String.t()}
  def lookup(kind, name) when kind in @kinds do
    case members(group(kind, name)) do
      [] ->
        {:error, "no #{kind} called #{inspect(name)}; the cluster offers: #{offered(kind)}"}

      [pid | _rest] ->
        {:ok, provider(kind, name, pid)}
    end
  end

  defp group(kind, name), do: {kind, name}

  defp members(group), do: :pg.get_members(@scope, group)

  defp provider(kind, name, pid) do
    %{kind: kind, name: name, node: node(pid), pid: pid, describe: describe(pid)}
  end

  defp describe(pid) do
    case GenServer.call(pid, :describe, @timeout) do
      %{} = describe -> {:ok, describe}
      other -> {:error, ":describe answered #{inspect(other)} rather than a map"}
    end
  catch
    :exit, reason -> {:error, "the plugin did not answer: #{inspect(reason)}"}
  end

  defp offered(kind) do
    case providers(kind) |> Enum.map(& &1.name) |> Enum.uniq() |> Enum.sort() do
      [] -> "nothing of that kind"
      names -> Enum.join(names, ", ")
    end
  end
end
