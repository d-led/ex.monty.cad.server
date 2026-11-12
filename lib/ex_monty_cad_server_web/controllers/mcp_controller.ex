defmodule ExMontyCadServerWeb.McpController do
  @moduledoc """
  The Model Context Protocol over HTTP: one JSON-RPC message per request.

  A request carries one message; a batch is refused rather than half-answered,
  because a client that sends one expects one reply per message and the protocol
  has no batch in the revisions this server speaks.

  A notification — a message without an `id` — is answered with `202` and an
  empty body, which is what the protocol says a notification gets: the work is
  done, and there is nothing to say about it.
  """

  use ExMontyCadServerWeb, :controller

  alias ExMontyCadServer.Mcp.Session

  @doc "One JSON-RPC message in, its reply out."
  def handle(conn, _params) do
    case conn.body_params do
      %{} = message when map_size(message) > 0 ->
        answer(conn, message)

      _not_a_message ->
        conn
        |> put_status(:bad_request)
        |> json(%{
          "jsonrpc" => "2.0",
          "id" => nil,
          "error" => %{"code" => -32_600, "message" => "one JSON-RPC object a request"}
        })
    end
  end

  defp answer(conn, message) do
    case Session.handle(message) do
      nil ->
        send_resp(conn, :accepted, "")

      reply ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(:ok, reply)
    end
  end
end
