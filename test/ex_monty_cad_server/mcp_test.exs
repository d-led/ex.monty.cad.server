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
      assert "monty_cad_sense" in names
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
      assert text =~ "monty_cad_sense"
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
