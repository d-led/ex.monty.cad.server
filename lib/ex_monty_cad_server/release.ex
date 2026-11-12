defmodule ExMontyCadServer.Release do
  @moduledoc """
  What a release is driven from: its migrations, and its two ways of serving.

  A release is the same server without Mix: the application, the two Rust engines
  compiled for the platform, and a script per way of running it.

      bin/ex_monty_cad_server          # the overlay: migrate, then serve HTTP
      bin/ex_monty_cad_server mcp      # the overlay: serve the protocol on stdio

  Both are in `rel/overlays/bin/`, so `mix release` carries them and nothing else
  has to be right about paths.
  """

  @app :ex_monty_cad_server

  alias ExMontyCadServer.Mcp.Serve

  @doc """
  Applies the migrations, in a VM of its own.

  Called before the server starts rather than from it, so a deploy that fails at
  the schema fails before anything serves against tables that are not there. The
  migration lock means several nodes booting at once migrate once.
  """
  @spec migrate() :: :ok
  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _repo, _applied} =
        Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end

    :ok
  end

  @doc """
  Serves the protocol on stdin and stdout, for a client that launches the server.

  The same two checks `mix ex_monty_cad_server.mcp` makes: a release whose native
  libraries did not make it into the image refuses here, with the reason, rather
  than failing every tool call with "module ... is not available".
  """
  @spec mcp() :: no_return()
  def mcp do
    {:ok, _apps} = Application.ensure_all_started(@app)
    Serve.serve!()
  end

  defp repos do
    # The module this instance was started with, not the compile-time list: in a
    # release that can be the SQLite repo, and the migrations are the same files.
    [ExMontyCadServer.Database.repo_module()]
  end

  defp load_app do
    Application.load(@app)
  end
end
