defmodule ExMontyCadServerWeb.McpControllerTest do
  # The session holds one state for the running application, so two of these
  # tests at once would be two clients sharing a cache by accident.
  use ExMontyCadServerWeb.ConnCase, async: false

  describe "POST /mcp" do
    test "a request is answered with its reply", %{conn: conn} do
      body =
        message("initialize", %{"protocolVersion" => "2025-06-18"}, 1)

      reply =
        conn
        |> post(~p"/mcp", body)
        |> json_response(200)

      assert reply["jsonrpc"] == "2.0"
      assert reply["id"] == 1
      assert reply["result"]["protocolVersion"] == "2025-06-18"
    end

    test "a notification is accepted and says nothing", %{conn: conn} do
      conn
      |> post(~p"/mcp", message("notifications/initialized", %{}, nil))
      |> response(202)
    end

    test "a body that is not a message is refused", %{conn: conn} do
      reply =
        conn
        |> post(~p"/mcp", %{})
        |> json_response(400)

      assert reply["error"]["code"] == -32_600
    end

    test "an engine's state outlives the request that filled it", %{conn: conn} do
      fixture = Path.expand("../../fixtures/golden_simple_through_hole.step", __DIR__)

      first =
        conn
        |> post(~p"/mcp", tool("monty_cad_brief", %{"path" => fixture}))
        |> json_response(200)

      assert first["result"]["isError"] == false

      # The second call asks the same engine about the same file through a new
      # request; the part is already open in the session the first call used.
      second =
        conn
        |> post(
          ~p"/mcp",
          tool("monty_cad_sense", %{
            "path" => fixture,
            "point" => [15.0, 0.0, 23.0],
            "normal" => [0.0, 0.0, 1.0]
          })
        )
        |> json_response(200)

      assert second["result"]["isError"] == false
      assert second["result"]["structuredContent"]["features"]["pose_vectors"]
    end
  end

  defp message(method, params, id) do
    message = %{"jsonrpc" => "2.0", "method" => method, "params" => params}
    if is_nil(id), do: message, else: Map.put(message, "id", id)
  end

  defp tool(name, arguments) do
    message("tools/call", %{"name" => name, "arguments" => arguments}, 2)
  end
end
