defmodule ExMontyCadServer.MixProject do
  use Mix.Project

  # The same number `VERSION` carries: the release workflow compares the two, and
  # a tag that disagrees with either is refused rather than published.
  @version "0.1.0"

  def project do
    [
      app: :ex_monty_cad_server,
      version: @version,
      elixir: "~> 1.17",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      # What `mix ecto.*` acts on, and the timestamp type the generators use. The
      # name is the Postgres repo because that is the one a checkout and CI have;
      # `config/runtime.exs` replaces it with whatever the release chose.
      ecto_repos: [ExMontyCadServer.Repo.Postgres],
      generators: [timestamp_type: :utc_datetime],
      # The Mix task calls `Mix.Task` and `Mix.raise`, and the test support calls
      # `ExUnit`'s macros; neither application is in a default PLT, and without
      # them every one of those calls is reported as an unknown function.
      dialyzer: [
        plt_add_apps: [:mix, :ex_unit],
        plt_local_path: "priv/plts",
        plt_core_path: "priv/plts"
      ],
      compilers: [:phoenix_live_view] ++ Mix.compilers(),
      listeners: [Phoenix.CodeReloader],
      name: "ex_monty_cad_server",
      description:
        "A Model Context Protocol server for CAD: cadmpeg reads the file, " <>
          "quiddity names what it found and answers the geometry underneath, " <>
          "and Monty's own percept turns it into a graph memory a run loads.",
      source_url: "https://github.com/d-led/ex.monty.cad.server"
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {ExMontyCadServer.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  def cli do
    [
      preferred_envs: [precommit: :test]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:phoenix, "~> 1.8.16"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 1.2.0"},
      {:lazy_html, ">= 0.1.0", only: :test},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:jason, "~> 1.2"},
      {:dns_cluster, "~> 0.2.0"},
      {:bandit, "~> 1.5"},
      # The database: the same Postgres and Ecto the Monty app keeps its runs in,
      # and the same SQLite fallback so a release still works without a server.
      {:ecto_sql, "~> 3.13"},
      {:postgrex, ">= 0.0.0"},
      {:ecto_sqlite3, "~> 0.26"},
      # The three engines the tools are made of. `ex_cadmpeg` reads the file,
      # `ex_quiddity` names what is in it and answers the geometry, and
      # `ex_monty_cad` turns a frame into the percept Monty's sensor modules
      # make and writes the library a run loads.
      {:ex_cadmpeg, "~> 0.1"},
      {:ex_quiddity, "~> 0.1"},
      # Until the package is on Hex this is the repository it will be published
      # from; `mix.lock` pins the commit, so a clone builds the same code.
      {:ex_monty_cad, github: "d-led/ex.monty.cad"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "ecto.setup"],
      "ecto.setup": ["ecto.create", "ecto.migrate"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      # A suite runs against a database that exists and is migrated: the same
      # two steps the Monty app's test alias takes before `test`.
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      precommit: ["compile --warnings-as-errors", "deps.unlock --unused", "format", "test"]
    ]
  end
end
