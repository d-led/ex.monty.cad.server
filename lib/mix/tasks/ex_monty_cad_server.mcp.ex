defmodule Mix.Tasks.ExMontyCadServer.Mcp do
  @shortdoc "Speaks the Model Context Protocol over stdio"

  @moduledoc """
  The server as a process a client launches:

      {"mcpServers": {"cad": {"command": "mix", "args": ["ex_monty_cad_server.mcp"]}}}

  One JSON-RPC message per line in, one out. Nothing else is written to stdout —
  a client that reads a banner as a message is a client that cannot start.

  It refuses to start when an engine is missing rather than answering every tool
  call with an error: a server that cannot read a CAD file is not this server,
  and saying so at launch is cheaper than saying it on the third question.

  The checks and the loop are `ExMontyCadServer.Mcp.Serve.serve!/0`, which is also
  what a release's `bin/ex_monty_cad_server mcp` runs: a checkout and a release
  cannot disagree about when there is no server to start.
  """

  use Mix.Task

  @impl true
  def run(_args) do
    Mix.Task.run("app.start")
    ExMontyCadServer.Mcp.Serve.serve!()
  end
end
