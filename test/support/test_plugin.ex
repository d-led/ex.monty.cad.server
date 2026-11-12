defmodule ExMontyCadServer.TestPlugin do
  @moduledoc """
  A plugin for the cluster tests: it answers what it is, and nothing else.

  Registered through `ExMontyCadServer.Cluster` exactly as a real provider would
  be, so what the tests exercise is the contract rather than a stand-in for it.
  """

  use GenServer

  @describe %{
    "name" => "feature_following",
    "kind" => :motor_policy,
    "version" => "0.1.0",
    "placement" => :owner_only,
    "needs" => [:quiddity]
  }

  def start_link(opts \\ []) do
    {describe, opts} = Keyword.pop(opts, :describe, @describe)
    GenServer.start_link(__MODULE__, describe, Keyword.put_new(opts, :name, __MODULE__))
  end

  @impl true
  def init(describe), do: {:ok, describe}

  @impl true
  def handle_call(:describe, _from, describe), do: {:reply, describe, describe}

  # A provider registered and started in one step, which is what a test wants.
  @doc false
  def registered(kind, name, opts \\ []) do
    {:ok, pid} = start_link(opts)
    :ok = ExMontyCadServer.Cluster.register(kind, name, pid)
    {:ok, pid}
  end
end
