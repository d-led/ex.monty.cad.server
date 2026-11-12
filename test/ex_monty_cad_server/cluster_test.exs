defmodule ExMontyCadServer.ClusterTest do
  # `:pg` is one table for the node: two tests registering the same name at once
  # would be one test reading another's plugin.
  use ExUnit.Case, async: false

  alias ExMontyCadServer.{Cluster, TestPlugin}

  describe "a plugin offered by a node" do
    test "is found by name, with the node that offers it" do
      {:ok, _pid} = TestPlugin.registered(:motor_policy, "feature_following")

      assert {:ok, provider} = Cluster.lookup(:motor_policy, "feature_following")
      assert provider.name == "feature_following"
      assert provider.kind == :motor_policy
      assert provider.node == node()
      assert {:ok, %{"placement" => :owner_only}} = provider.describe
    end

    test "is listed among the providers of its kind" do
      {:ok, _pid} = TestPlugin.registered(:experiment, "evaluate_plate")

      names = Cluster.providers(:experiment) |> Enum.map(& &1.name)

      assert "evaluate_plate" in names
    end

    test "is not listed among another kind" do
      {:ok, _pid} = TestPlugin.registered(:learning_module, "evidence_graph")

      names = Cluster.providers(:motor_policy) |> Enum.map(& &1.name)

      refute "evidence_graph" in names
    end
  end

  describe "a name nobody offers" do
    test "is an error that names the kind and what there is" do
      assert {:error, message} = Cluster.lookup(:motor_policy, "no_such_policy")

      assert message =~ "no motor_policy called \"no_such_policy\""
      assert message =~ "the cluster offers:"
    end
  end

  describe "a provider that answers nonsense" do
    test "is still listed, with the reason a caller cannot use it" do
      {:ok, _pid} = TestPlugin.registered(:experiment, "confused", describe: :confused)

      [provider] = Enum.filter(Cluster.providers(:experiment), &(&1.name == "confused"))

      assert {:error, reason} = provider.describe
      assert reason =~ ":describe answered :confused rather than a map"
    end
  end
end
