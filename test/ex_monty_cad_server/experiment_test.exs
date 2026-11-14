defmodule ExMontyCadServer.ExperimentTest do
  @moduledoc """
  The experiment this node offers, asked the way a studio asks it.

  An `:experiment` plugin is a definition rather than a step of one, so there is
  one question (`:run`) and one answer (data). What is specified here is that the
  definition names a config the studio can compose, a policy this node actually
  offers, and the seed the other variations of the same experiment write — because
  a comparison whose rows differ in two things is not a comparison.

  The walk's own decisions are specified where the walk is
  (`MontyCad.Policy.FeatureWalk`), and this node's offer of it beside this file;
  nothing about a step belongs here.
  """

  use ExUnit.Case, async: false

  alias ExMontyCadServer.Experiment
  alias ExMontyCadServer.Policy.FeatureWalk

  # The application already runs one, because that is what a node does at boot: a
  # case asks the process a cluster would reach.
  setup do
    %{experiment: Process.whereis(Experiment) || start_supervised!(Experiment)}
  end

  test "it offers itself under the name a run asks for", %{experiment: pid} do
    assert %{
             "name" => "monty_cad.10simobj_surf_agent",
             "kind" => :experiment,
             "placement" => :anywhere,
             "version" => version,
             "needs" => needs
           } = GenServer.call(pid, :describe)

    assert version != "unknown"
    assert :quiddity in needs
    assert :monty in needs
  end

  test "it answers a cluster with the definition, and starts nothing", %{experiment: pid} do
    assert {:ok, %{"base" => "base_10simobj_surf_agent"}} = GenServer.call(pid, :run)
  end

  # Registered where a studio asks: on the node that offers it. A name is
  # cluster-wide, so this is asked of this node rather than of the cluster —
  # which is what `Cluster.lookup/3` is for and what the policy's own case says.
  test "a studio finds it on the node that offers it" do
    assert {:ok, %{describe: {:ok, %{"name" => "monty_cad.10simobj_surf_agent"}}}} =
             ExMontyCadServer.Cluster.lookup(
               :experiment,
               "monty_cad.10simobj_surf_agent",
               node()
             )
  end

  test "the definition names the motor system this node offers" do
    offered = FeatureWalk.describe()

    assert Experiment.run()["motor_system"] == offered["name"]
    assert offered["kind"] == :motor_policy
  end

  # A definition that named a learning module would be refused by the studio
  # (`Monty.Studio.PluginExperiment`), so the empty list is the definition saying
  # "the config's own", not an omission.
  test "it leaves the learning module to the config" do
    assert Experiment.run()["learning_modules"] == []
  end

  # The same config, the same seed, the same budget: two variations of one
  # experiment differ in who decides, and in nothing else.
  test "it steps the comparison's config at the seed the variations share" do
    assert %{
             "base" => "base_10simobj_surf_agent",
             "seed" => 42
           } = Experiment.run()

    refute Map.has_key?(Experiment.run(), "episodes")
  end
end
