defmodule ExMontyCadServer.ClusterAcrossNodesTest do
  @moduledoc """
  The claim this repository makes about `:pg` — that a name joined on one node is
  visible on every node — as a test rather than a sentence.

  Each test starts a second node with `:peer` and the same application on it with
  no listener (the endpoint only binds when `PHX_SERVER` is set), and offers a
  plugin there. What this node then sees has to come over the network: the node
  in the answer is the peer's, and the description was asked for across the
  connection.

  The peer is started linked and by the test itself, so it goes when the test
  does; a peer outliving its test would be one node's plugin in the next node's
  answers.
  """

  # One cluster scope per node and one peer per test, so these cannot run beside
  # each other.
  use ExUnit.Case, async: false

  # A second node needs a distributed VM. `mix test` does not start one, so a
  # plain run excludes these; `test_helper.exs` says why, and CI starts a VM with
  # a name and asks for them.
  @moduletag :distributed

  alias ExMontyCadServer.{Cluster, TestPlugin}

  test "a plugin offered by another node is found here, with its description" do
    peer_node = peer()

    {:ok, plugin} = :rpc.call(peer_node, TestPlugin, :start_unlinked, [])
    :ok = :rpc.call(peer_node, Cluster, :register, [:motor_policy, "far_policy", plugin])

    assert {:ok, provider} =
             eventually(
               fn -> Cluster.lookup(:motor_policy, "far_policy") end,
               &match?({:ok, _}, &1)
             )

    assert provider.node == peer_node
    assert provider.pid == plugin
    assert {:ok, %{"placement" => :owner_only, "needs" => [:quiddity]}} = provider.describe
  end

  test "a plugin withdrawn elsewhere leaves the list here" do
    peer_node = peer()

    {:ok, plugin} = :rpc.call(peer_node, TestPlugin, :start_unlinked, [])
    :ok = :rpc.call(peer_node, Cluster, :register, [:experiment, "gone_soon", plugin])

    assert {:ok, _provider} =
             eventually(fn -> Cluster.lookup(:experiment, "gone_soon") end, &match?({:ok, _}, &1))

    :ok = :rpc.call(peer_node, Cluster, :unregister, [:experiment, "gone_soon", plugin])

    assert {:error, message} =
             eventually(
               fn -> Cluster.lookup(:experiment, "gone_soon") end,
               &match?({:error, _}, &1)
             )

    assert message =~ "no experiment called \"gone_soon\""
  end

  # A second node with this application running on it, and no listener: it is the
  # answer to "on every node", not a second server.
  defp peer do
    start_distribution()

    name = :"cad_peer_#{System.unique_integer([:positive])}"

    {:ok, _peer, peer_node} =
      case domain() do
        :longnames -> :peer.start_link(%{name: name, longnames: true})
        :shortnames -> :peer.start_link(%{name: name, sname: true})
      end

    :ok = :rpc.call(peer_node, :code, :add_paths, [:code.get_path()])
    {:ok, _apps} = :rpc.call(peer_node, Application, :ensure_all_started, [:ex_monty_cad_server])

    peer_node
  end

  # Which kind of name this node has, because a peer has to be reachable by it:
  # `ex_monty_cad_test@127.0.0.1` reaches `peer@host.domain` and `cad_ci@host`
  # reaches `peer@host`, while a mismatch is a peer that starts and never answers.
  defp domain do
    case :erlang.node() do
      :nonode@nohost -> :longnames
      node -> if String.contains?(Atom.to_string(node), "."), do: :longnames, else: :shortnames
    end
  end

  # A peer is a node name, so the caller has to be one too. Started here rather
  # than demanded of whoever runs the suite: a test that only passes when the VM
  # was launched with a name is a test nobody can run.
  defp start_distribution do
    case :net_kernel.start([:"ex_monty_cad_test@127.0.0.1", :longnames]) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end
  end

  # `:pg` has no "everything before this is everywhere" call, so what the other
  # node did is waited for by asking until it is there — bounded, and a failure
  # is the last answer rather than a hang.
  defp eventually(fun, settled?, attempts \\ 40) do
    Enum.reduce_while(1..attempts, fun.(), fn _attempt, result ->
      if settled?.(result) do
        {:halt, result}
      else
        Process.sleep(50)
        {:cont, fun.()}
      end
    end)
  end
end
