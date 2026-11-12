defmodule ExMontyCadServer.Mcp.Serve do
  @moduledoc """
  The server as a process a client launches: one JSON-RPC message per line in,
  one out.

  Both ways of getting here — `mix ex_monty_cad_server.mcp` and a release's
  `bin/ex_monty_cad_server mcp` — go through `serve!/0`, so the checks a checkout
  makes are the checks a release makes.

  Nothing but protocol messages is written to stdout: a client that reads a banner
  as a message is a client that cannot start. The one diagnostic this prints goes
  to stderr.
  """

  @doc """
  Serves until stdin closes, or refuses to start.

  Refusing is deliberate: a server whose NIF did not build can answer `tools/list`
  and fail every call, which is a client that looks connected and is not. Raising
  at launch says which engine is missing.
  """
  @spec serve!() :: no_return()
  def serve! do
    case Enum.reject(engines(), fn {_name, loaded?} -> loaded? end) do
      [] ->
        ExMontyCadServer.Mcp.serve()

      missing ->
        names = Enum.map_join(missing, ", ", fn {name, _} -> name end)
        raise "the #{names} NIF is not built, so there is no engine to answer with"
    end
  end

  defp engines, do: [{"quiddity", Quiddity.Native.loaded?()}, {"cadmpeg", Cadmpeg.loaded?()}]
end
