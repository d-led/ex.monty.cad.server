defmodule ExMontyCadServer.Policy.FeatureWalkTest do
  @moduledoc """
  The node's offer of `monty_cad.feature_walk`, asked the way a run asks it.

  The cases speak the wire `Monty.Studio.RemotePolicy` speaks — `{:new, []}`,
  `{:call, …}` carrying the policy, `{:reset, …}` — because that is the whole
  agreement between a run and a host. `MontyCad.Policy.FeatureWalk`'s own cases
  are where the walk's steps are specified; what is specified here is that this
  process offers it under a name, keeps the part, and hands back something that
  can cross a node.
  """

  use ExUnit.Case, async: false

  alias ExMontyCadServer.Policy.FeatureWalk
  alias Monty.Frameworks.Models.MotorPolicies.MotorPolicyResult
  alias Monty.Frameworks.Models.MotorSystemState.{AgentState, SensorState}
  alias MontyCad.Scene

  @fixture Path.expand("../../fixtures/golden_simple_through_hole.step", __DIR__)
  @agent "agent_id_0"
  @sensor "patch"

  # The application already runs one, because that is what a node does at boot:
  # a case asks the process a cluster would reach.
  setup do
    named(@fixture)
    %{policy: Process.whereis(FeatureWalk) || start_supervised!(FeatureWalk)}
  end

  test "it offers itself under the name a config names", %{policy: pid} do
    assert %{
             "name" => "monty_cad.feature_walk",
             "kind" => :motor_policy,
             "placement" => :owner_only,
             "needs" => needs
           } = GenServer.call(pid, :describe)

    assert :quiddity in needs
    assert :monty in needs
  end

  test "the cluster finds it by that name", %{policy: pid} do
    assert {:ok, %{pid: ^pid, describe: {:ok, %{"name" => "monty_cad.feature_walk"}}}} =
             ExMontyCadServer.Cluster.lookup(:motor_policy, "monty_cad.feature_walk")
  end

  # The part cannot leave this node, so what a caller holds is the walk's
  # progress: everything that makes one episode's walk its own, and nothing that
  # is a resource here.
  test "the first policy is a walk over the named part, and it is data a node can send", %{
    policy: pid
  } do
    assert {:ok, progress} = GenServer.call(pid, {:new, []})

    assert %{target: nil, visited: [], walked: 0, standoff: standoff, step: step} = progress
    assert is_float(standoff)
    assert is_float(step)
    assert is_binary(:erlang.term_to_binary(progress))
  end

  test "a step answers with a result and the progress it moved to", %{policy: pid} do
    {:ok, progress} = GenServer.call(pid, {:new, []})
    {:ok, observations, state} = sensing()

    assert {:ok, %MotorPolicyResult{} = result, moved} =
             GenServer.call(pid, {:call, progress, nil, observations, state, nil, nil})

    assert is_list(result.actions)
    assert result.status == :ready
    assert moved.walked >= progress.walked

    # The progress it answered with is one it can be asked again: an episode is
    # hundreds of these, each carrying the policy the last one gave back.
    assert {:ok, %MotorPolicyResult{}, _again} =
             GenServer.call(pid, {:call, moved, nil, observations, state, nil, nil})
  end

  test "a reset is the walk starting over", %{policy: pid} do
    {:ok, progress} = GenServer.call(pid, {:new, []})
    {:ok, moved} = GenServer.call(pid, {:reset, progress})

    assert %{target: nil, visited: [], walked: 0} = moved
  end

  test "what a run is read from afterwards is what the caller already holds", %{policy: pid} do
    {:ok, progress} = GenServer.call(pid, {:new, []})

    assert GenServer.call(pid, {:state_dict, progress}) == {:ok, progress}
  end

  test "something that is not a progress says so rather than deciding", %{policy: pid} do
    assert {:error, sentence} = GenServer.call(pid, {:state_dict, :not_a_walk})
    assert sentence =~ "progress"
  end

  # A node with no part named still offers the policy — it is the episode that
  # cannot start, and the sentence is the repair.
  test "no part named refuses the first policy with the sentence that names the variable" do
    # Its own process: the node's has already opened a part, and this is about a
    # node that has none to open.
    System.delete_env("MONTY_CAD_PART")
    pid = start_supervised!({FeatureWalk, name: nil})

    assert %{"name" => "monty_cad.feature_walk"} = GenServer.call(pid, :describe)
    assert {:error, sentence} = GenServer.call(pid, {:new, []})
    assert sentence =~ "MONTY_CAD_PART"
  end

  defp named(part) do
    previous = System.get_env("MONTY_CAD_PART")
    System.put_env("MONTY_CAD_PART", part)
    on_exit(fn -> restore("MONTY_CAD_PART", previous) end)
  end

  defp restore(variable, nil), do: System.delete_env(variable)
  defp restore(variable, value), do: System.put_env(variable, value)

  # A patch sensor where a world would start one: above the part, looking down,
  # which is the only pose a walk can begin from. The observations are the
  # framework's shape; this policy reads the ray rather than the image.
  defp sensing do
    {:ok, scene} = Scene.open(@fixture)
    pose = Scene.start_pose(scene)

    state = %{
      @agent => %AgentState{
        position: pose.position,
        rotation: pose.rotation,
        sensors: %{@sensor => %SensorState{position: pose.position, rotation: pose.rotation}}
      }
    }

    {:ok, %{@agent => %{@sensor => %{depth: 0.05}}}, state}
  end
end
