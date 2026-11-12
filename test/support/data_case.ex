defmodule ExMontyCadServer.DataCase do
  @moduledoc """
  A case for a test that touches the catalogue.

  Each test gets a connection of its own with a transaction around it, so a test
  sees the rows it wrote and no test sees another's. The repo is the one the
  application would have started — `ExMontyCadServer.Database.repo_module/0` —
  because the sandbox is a property of the connection, not of the name the
  application calls it by.
  """
  use ExUnit.CaseTemplate

  alias Ecto.Adapters.SQL.Sandbox
  alias ExMontyCadServer.Database

  using do
    quote do
      alias ExMontyCadServer.Catalogue

      import Ecto.Query
      import ExMontyCadServer.DataCase
    end
  end

  setup tags do
    pid = Sandbox.start_owner!(repo(), shared: not tags[:async])
    on_exit(fn -> Sandbox.stop_owner(pid) end)

    :ok
  end

  @doc "The repo module under test."
  @spec repo() :: module()
  def repo, do: Database.repo_module()
end
