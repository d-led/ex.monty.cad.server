defmodule ExMontyCadServer.Mcp.Session do
  @moduledoc """
  The one place a server's state lives, for a transport that is not a pipe.

  The stdio transport owns its state in its own loop, because one client is one
  process. HTTP has no such loop: every request is a separate visit, and a
  document opened by one of them should still be open for the next. This process
  is that memory — it holds one state and answers one message at a time, which is
  also what keeps two calls from interleaving their cache writes.

  A call that changes what is remembered therefore goes through here; `ping` and
  `tools/list` do too, because going around it would need a second copy of the
  state and a second answer to disagree with.
  """

  use GenServer

  alias ExMontyCadServer.Mcp

  # Reading a part, sampling its surface and writing a library is seconds of
  # work on a real file, and the client is waiting for the answer.
  @timeout 300_000

  @doc false
  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc """
  One decoded message: the reply, or `nil` for a notification.

  The state this returns is the state the next message sees.
  """
  @spec handle(map()) :: String.t() | nil
  def handle(message), do: GenServer.call(__MODULE__, {:handle, message}, @timeout)

  @impl true
  def init(_opts), do: {:ok, Mcp.fresh()}

  @impl true
  def handle_call({:handle, message}, _from, state) do
    {reply, state} = Mcp.message(message, state)
    {:reply, reply, state}
  end
end
