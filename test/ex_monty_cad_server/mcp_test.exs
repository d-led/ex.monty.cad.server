defmodule ExMontyCadServer.McpTest do
  use ExMontyCadServer.DataCase, async: true

  alias ExMontyCadServer.Mcp

  @fixture Path.expand("../fixtures/golden_simple_through_hole.step", __DIR__)

  # The point quiddity's own suite stands a sensor at to reach the boss on this
  # part, and the direction it looks from.
  @boss_top [15.0, 0.0, 23.0]
  @up [0.0, 0.0, 1.0]

  describe "the handshake" do
    test "answers with the revision the client asked for" do
      {reply, _state} = request("initialize", %{"protocolVersion" => "2025-03-26"})

      assert reply["result"]["protocolVersion"] == "2025-03-26"
      assert reply["result"]["serverInfo"]["name"] == "ex-monty-cad-server"
      assert reply["result"]["capabilities"]["tools"] == %{"listChanged" => false}
    end

    test "a revision it does not speak is answered with the newest one it does" do
      {reply, _state} = request("initialize", %{"protocolVersion" => "1999-01-01"})

      assert reply["result"]["protocolVersion"] == "2025-06-18"
    end

    test "a notification is answered with nothing" do
      {reply, _state} = request("notifications/initialized", %{}, nil)

      assert reply == nil
    end

    test "a line that is not JSON is refused, not crashed on" do
      state = Mcp.fresh()

      assert {reply, ^state} = Mcp.handle("{not json", state)
      assert Jason.decode!(reply)["error"]["code"] == -32_700
    end

    test "an unknown method is an error that names it" do
      {reply, _state} = request("tools/nope", %{})

      assert reply["error"]["message"] == "unknown method: tools/nope"
    end
  end

  describe "the tools" do
    test "are one catalogue over the three engines" do
      {reply, _state} = request("tools/list", %{})

      names = Enum.map(reply["result"]["tools"], & &1["name"])

      assert "cadmpeg_formats" in names
      assert "quiddity_part" in names
      assert "monty_cad_brief" in names
    end

    test "what cadmpeg reads is a fact about this build" do
      {reply, _state} = request("tools/call", %{"name" => "cadmpeg_formats"})

      assert reply["result"]["isError"] == false
      assert reply["result"]["structuredContent"]["outputs"] != []
    end

    test "a name no engine owns is refused with the names there are" do
      {reply, _state} = request("tools/call", %{"name" => "cad_nothing"})

      text = reply["result"]["content"] |> hd() |> Map.fetch!("text")
      assert text =~ "`cad_nothing` is not one of the tools"
      assert text =~ "monty_cad_brief"
    end
  end

  describe "the part, named" do
    test "the brief counts the faces and says what the features are" do
      {reply, _state} =
        request("tools/call", %{
          "name" => "monty_cad_brief",
          "arguments" => %{"path" => @fixture}
        })

      result = reply["result"]
      assert result["isError"] == false

      assert result["structuredContent"]["faces"] > 0
      assert result["structuredContent"]["families"] |> Map.keys() |> length() > 0
      assert text_of(result) =~ "faces"
    end
  end

  describe "the sensor" do
    test "perceives node features where it stands" do
      {reply, _state} = sense()

      result = reply["result"]
      assert result["isError"] == false

      features = result["structuredContent"]["features"]
      assert Map.has_key?(features, "pose_vectors")
      assert text_of(result) =~ "the sensor perceives"
    end

    test "a point that is not three numbers is refused" do
      {reply, _state} =
        request("tools/call", %{
          "name" => "monty_cad_sense",
          "arguments" => %{"path" => @fixture, "point" => [1.0, 2.0], "normal" => @up}
        })

      assert reply["result"]["isError"] == true
      assert text_of(reply["result"]) =~ "`point` is required"
    end
  end

  describe "the memory" do
    @tag :tmp_dir
    test "is written as the library a run loads", %{tmp_dir: dir} do
      out = Path.join(dir, "part.jsonl.gz")

      {reply, _state} =
        request("tools/call", %{
          "name" => "monty_cad_library",
          "arguments" => %{
            "path" => @fixture,
            "object" => "plate",
            "out" => out,
            "spacing" => 5.0,
            "limit" => 6
          }
        })

      result = reply["result"]
      assert result["isError"] == false, text_of(result)
      assert result["structuredContent"]["object_id"] == "plate"
      assert result["structuredContent"]["nodes"] > 0
      assert File.exists?(out)
    end

    test "answers what has been learned already, newest first" do
      out =
        Path.join(
          System.tmp_dir!(),
          "mcp_libraries_#{System.unique_integer([:positive])}.jsonl.gz"
        )

      {_reply, state} =
        call_tool("monty_cad_library", %{
          "path" => @fixture,
          "object" => "plate",
          "out" => out,
          "spacing" => 5.0,
          "limit" => 6
        })

      {reply, _state} = call_tool("monty_cad_libraries", %{}, state)

      result = reply["result"]
      assert result["isError"] == false, text_of(result)

      assert [memory] = result["structuredContent"]["libraries"]
      assert memory["object_id"] == "plate"
      assert memory["part"] == Path.basename(@fixture)
      assert memory["nodes"] > 0
    end

    test "says plainly that nothing has been learned yet" do
      {reply, _state} = call_tool("monty_cad_libraries", %{})

      assert text_of(reply["result"]) =~ "0 memory(s) recorded — none has been written yet"
    end
  end

  describe "the cluster" do
    test "a node that takes no part in one says so rather than looking empty" do
      System.put_env("PLUGIN_DISCOVERY", "none")
      on_exit(fn -> System.delete_env("PLUGIN_DISCOVERY") end)

      {reply, _state} = call_tool("cad_plugin_list", %{})

      text = text_of(reply["result"])
      assert text =~ "plugin discovery is off on this node"
      assert text =~ "PLUGIN_DISCOVERY"
      assert reply["result"]["structuredContent"]["providers"] == []
    end

    # This VM may or may not be distributed — the test helper asks for one, and CI
    # says no — so the facts are stated rather than provoked. "0 plugins" read as
    # "nothing is offered anywhere" until a release over stdio said it on a node
    # that had never been in a cluster at all.
    test "a node outside a cluster still names what it has, and says it has no cluster" do
      {:ok, _pid} =
        ExMontyCadServer.TestPlugin.registered(:motor_policy, "follow_chamfers",
          describe: %{"name" => "follow_chamfers", "kind" => :motor_policy}
        )

      {reply, _state} = call_tool("cad_plugin_list", %{}, on_a_node(clustered: false))

      text = text_of(reply["result"])
      assert text =~ "motor_policy: follow_chamfers"
      assert text =~ "not part of a cluster"
      assert text =~ "NODE_NAME"
    end

    test "a plugin that is not here is not said to be nowhere, when this node cannot look" do
      arguments = %{"name" => "elsewhere", "kind" => "motor_policy"}

      {reply, _state} = call_tool("cad_plugin_describe", arguments, on_a_node(clustered: false))
      assert text_of(reply["result"]) =~ "not part of a cluster"

      {reply, _state} = call_tool("cad_plugin_describe", arguments, on_a_node(clustered: true))
      refute text_of(reply["result"]) =~ "not part of a cluster"
    end

    test "a plugin can be asked about on a named node, which is what an owner-only one needs" do
      {:ok, _pid} =
        ExMontyCadServer.TestPlugin.registered(:motor_policy, "follow_chamfers",
          describe: %{"name" => "follow_chamfers", "kind" => :motor_policy}
        )

      arguments = %{
        "name" => "follow_chamfers",
        "kind" => "motor_policy",
        "node" => to_string(node())
      }

      {reply, _state} = call_tool("cad_plugin_describe", arguments)

      assert text_of(reply["result"]) =~ "follow_chamfers"
      assert text_of(reply["result"]) =~ to_string(node())
    end

    test "a node that is not connected is refused, with the ones that are" do
      arguments = %{
        "name" => "follow_chamfers",
        "kind" => "motor_policy",
        "node" => "there@nohost"
      }

      {reply, _state} = call_tool("cad_plugin_describe", arguments)

      text = text_of(reply["result"])
      assert text =~ "no node called \"there@nohost\" is connected"
      assert text =~ to_string(node())
    end

    test "a node in a cluster counts what it offers" do
      {reply, _state} = call_tool("cad_plugin_list", %{}, on_a_node(clustered: true))

      assert text_of(reply["result"]) =~ "on this cluster"
    end

    test "names a plugin whose answer cannot be used as such" do
      description = %{"name" => "nameless", "kind" => :motor_policy, "placement" => :owner_only}

      {:ok, _pid} =
        ExMontyCadServer.TestPlugin.registered(:motor_policy, "nameless", describe: description)

      {reply, _state} = call_tool("cad_plugin_list", %{"kind" => "motor_policy"})

      assert text_of(reply["result"]) =~ "nameless (cannot be used)"

      {reply, _state} =
        call_tool("cad_plugin_describe", %{"name" => "nameless", "kind" => "motor_policy"})

      assert text_of(reply["result"]) =~ "it cannot be used"
      assert text_of(reply["result"]) =~ "`version` is missing"
    end

    test "lists what is offered, by kind" do
      {:ok, _pid} = ExMontyCadServer.TestPlugin.registered(:motor_policy, "follow_chamfers")

      {reply, _state} =
        request("tools/call", %{"name" => "cad_plugin_list", "arguments" => %{}})

      result = reply["result"]
      assert result["isError"] == false
      assert text_of(result) =~ "motor_policy: follow_chamfers"
    end

    test "describes one plugin, including where it may run" do
      {:ok, _pid} = ExMontyCadServer.TestPlugin.registered(:motor_policy, "follow_axes")

      {reply, _state} =
        request("tools/call", %{
          "name" => "cad_plugin_describe",
          "arguments" => %{"name" => "follow_axes", "kind" => "motor_policy"}
        })

      result = reply["result"]
      assert result["isError"] == false
      assert result["structuredContent"]["describe"]["placement"] == "owner_only"
    end

    test "asks for a kind when describing, because a name can be offered twice" do
      {reply, _state} =
        request("tools/call", %{
          "name" => "cad_plugin_describe",
          "arguments" => %{"name" => "follow_axes"}
        })

      assert reply["result"]["isError"] == true
      assert text_of(reply["result"]) =~ "`kind` is required"
    end
  end

  describe "the features near a point" do
    test "are named, nearest first, with how far each one is" do
      {reply, _state} = features_near(30.0)

      result = reply["result"]
      assert result["isError"] == false
      assert [first | _rest] = result["structuredContent"]["features"]
      assert first["id"] == "bosses/0"
      assert first["family"] == "bosses"
      # The boss's axis point is ten millimetres below the top the sensor is on.
      assert_in_delta first["distance"], 10.0, 0.01
      assert text_of(result) =~ "bosses/0 (bosses)"
    end

    test "a radius that reaches nothing says so instead of answering with something" do
      {reply, _state} = features_near(0.001)

      result = reply["result"]
      assert result["isError"] == false
      assert result["structuredContent"]["features"] == []
      assert text_of(result) =~ "none of them"
    end
  end

  describe "what is ahead" do
    test "names the feature in the direction of travel" do
      {reply, _state} = next_feature([0.0, 0.0, 1.0])

      result = reply["result"]
      assert result["isError"] == false
      assert [feature] = result["structuredContent"]["features"]
      assert feature["id"] == "bosses/0"
      assert_in_delta feature["distance"], 13.0, 0.01
      assert_in_delta feature["angle"], 0.0, 0.01
    end

    test "looking the other way finds nothing rather than the nearest thing behind" do
      {reply, _state} = next_feature([0.0, 0.0, -1.0])

      result = reply["result"]
      assert result["structuredContent"]["features"] == []
      assert text_of(result) =~ "none of them"
    end

    test "a direction of nought is refused, because a cone around it is everywhere" do
      {reply, _state} = next_feature([0.0, 0.0, 0.0])

      assert reply["result"]["isError"] == true
      assert text_of(reply["result"]) =~ "nought has none"
    end
  end

  describe "what a face is" do
    test "a face a feature claims is named, with its family" do
      {reply, _state} = on_face(7)

      result = reply["result"]
      assert result["isError"] == false
      assert result["structuredContent"]["feature"] == "bosses/0"
      assert result["structuredContent"]["family"] == "bosses"
    end

    test "a face no feature claims says which kind of unclaimed it is" do
      {reply, _state} = on_face(8)

      result = reply["result"]
      assert result["structuredContent"]["feature"] == nil
      assert result["structuredContent"]["owner"] == "unexplained"
    end

    test "a face the part does not have is refused, with the range that does" do
      {reply, _state} = on_face(99)

      assert reply["result"]["isError"] == true
      assert text_of(reply["result"]) =~ "`face` is one of 0..8"
    end
  end

  defp next_feature(direction) do
    request("tools/call", %{
      "name" => "monty_cad_next_feature",
      "arguments" => %{"path" => @fixture, "point" => [15.0, 0.0, 0.0], "direction" => direction}
    })
  end

  defp on_face(face) do
    request("tools/call", %{
      "name" => "monty_cad_on_face",
      "arguments" => %{"path" => @fixture, "face" => face}
    })
  end

  defp features_near(radius) do
    request("tools/call", %{
      "name" => "monty_cad_features_near",
      "arguments" => %{"path" => @fixture, "point" => @boss_top, "radius" => radius}
    })
  end

  defp sense do
    request("tools/call", %{
      "name" => "monty_cad_sense",
      "arguments" => %{"path" => @fixture, "point" => @boss_top, "normal" => @up}
    })
  end

  defp request(method, params, id \\ 1) do
    message = %{"jsonrpc" => "2.0", "method" => method, "params" => params}
    message = if is_nil(id), do: message, else: Map.put(message, "id", id)

    {reply, state} = Mcp.handle(Jason.encode!(message), Mcp.fresh())

    {if(reply, do: Jason.decode!(reply)), state}
  end

  # A tool call with the session it happens in, which a second call in the same
  # test needs: what the first one learned is state, not a database lookup.
  # The two facts about this node that a session reads once: a test states them
  # rather than provoking a VM that is not distributed.
  defp on_a_node(clustered: clustered) do
    %{Mcp.fresh() | cluster: %{discovery: true, discovery_var: nil, clustered: clustered}}
  end

  defp call_tool(name, arguments, state \\ Mcp.fresh()) do
    message = %{
      "jsonrpc" => "2.0",
      "method" => "tools/call",
      "id" => 1,
      "params" => %{"name" => name, "arguments" => arguments}
    }

    {reply, state} = Mcp.handle(Jason.encode!(message), state)

    {Jason.decode!(reply), state}
  end

  defp text_of(result) do
    result["content"] |> hd() |> Map.fetch!("text")
  end
end
