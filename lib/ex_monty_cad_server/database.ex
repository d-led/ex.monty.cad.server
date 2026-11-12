defmodule ExMontyCadServer.Database do
  @moduledoc """
  Which database this instance keeps its catalogue in, decided when it starts.

  Postgres when `DATABASE_URL` names one — a deployment with a database server
  says where it is, and that is the whole configuration. Otherwise SQLite in a
  file, so a release on a machine that has no database server still keeps what
  it made. Both drivers are compiled in, so one release serves either.

  `SQLITE_PATH` moves the file. Without it the file sits in the operating
  system's per-user application-data directory, which a container points at a
  volume.
  """

  @app :ex_monty_cad_server

  @doc """
  The repo module this instance starts and calls.

  A configured answer wins (test names the Postgres it has); otherwise
  `DATABASE_URL` decides, and a name that was never configured is a question for
  the environment rather than a default written when Postgres was the only
  answer.
  """
  @spec repo_module() :: module()
  def repo_module do
    Application.get_env(@app, :repo) || from_environment()
  end

  defp from_environment do
    case postgres_url() do
      nil -> ExMontyCadServer.Repo.SQLite
      _url -> ExMontyCadServer.Repo.Postgres
    end
  end

  # `nil` for a database server that was not named: one predicate, so the module
  # that is started and the configuration it is started with cannot disagree.
  defp postgres_url do
    case System.get_env("DATABASE_URL") do
      url when url in [nil, ""] -> nil
      url -> url
    end
  end

  @doc "The `ExMontyCadServer.Repo` configuration for this instance."
  @spec repo() :: keyword()
  def repo do
    case postgres_url() do
      nil -> sqlite()
      url -> postgres(url)
    end
  end

  @doc "The SQLite file, when SQLite is the database in use."
  @spec sqlite_path() :: String.t()
  def sqlite_path do
    System.get_env("SQLITE_PATH") ||
      Path.join(:filename.basedir(:user_data, "ex_monty_cad_server"), "catalogue.db")
  end

  defp postgres(url) do
    [
      url: url,
      pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10")
    ]
  end

  defp sqlite do
    [
      database: sqlite_path(),
      pool_size: String.to_integer(System.get_env("POOL_SIZE") || "5")
    ]
  end
end
