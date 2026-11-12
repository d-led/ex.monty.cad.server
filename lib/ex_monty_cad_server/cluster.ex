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
  next. A provider is registered under one of them, and its answer is held to
  `MontyPlugin`'s contract: a description is a map, so nothing in the compiler
  checks it, and a plugin that names itself unusably is reported with the field
  rather than offered as if it were a choice.

  This module is the server's name for that: the registry itself is
  `MontyPlugin.Registry`, shared with every other node in the estate, so an
  experiment offered by a Monty studio node and a policy offered here are the same
  kind of thing to a caller.

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

  @typedoc "The three things a run is made of."
  @type kind :: MontyPlugin.kind()

  @typedoc """
  One provider: where to call it, and what it says it is.

  `describe` is `{:ok, map}` when the plugin answered with a description a cluster
  can use, and `{:error, reason}` when it did not answer or answered unusably.
  """
  @type provider :: MontyPlugin.Registry.provider()

  @doc "The kinds a provider can be registered as."
  @spec kinds() :: [kind()]
  def kinds, do: MontyPlugin.kinds()

  @doc """
  Offers a process under a name, on this node and therefore on every node.
  """
  @spec register(kind(), String.t(), pid()) :: :ok
  def register(kind, name, pid), do: MontyPlugin.Registry.register(kind, name, pid)

  @doc "Withdraws an offer."
  @spec unregister(kind(), String.t(), pid()) :: :ok
  def unregister(kind, name, pid), do: MontyPlugin.Registry.unregister(kind, name, pid)

  @doc """
  Every provider of a kind, across the cluster, in no particular order.

  One plugin registered on two nodes appears twice, which is the truth: the caller
  picks, and the node it picks is the node the work happens on.
  """
  @spec providers(kind()) :: [provider()]
  def providers(kind), do: MontyPlugin.Registry.providers(kind)

  @doc """
  The one provider under a name.

  A name nobody offers is an error that names the ones there are, because the
  caller is usually a model that can pick another.
  """
  @spec lookup(kind(), String.t()) :: {:ok, provider()} | {:error, String.t()}
  def lookup(kind, name), do: MontyPlugin.Registry.lookup(kind, name)
end
