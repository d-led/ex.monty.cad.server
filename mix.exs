defmodule ExMontyCadServer.MixProject do
  use Mix.Project

  # The same number `VERSION` carries: the release workflow compares the two, and
  # a tag that disagrees with either is refused rather than published.
  @version "0.2.0"

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
      #
      # The PLTs live under `_build`, because `priv/` travels: `mix release` copies
      # an application's whole `priv` into the archive, and a run of `mix release`
      # on a machine that had also run dialyzer once put nine megabytes of PLT in
      # the tarball a deployment downloads.
      dialyzer: [
        plt_add_apps: [:mix, :ex_unit],
        plt_local_path: "_build/plts",
        plt_core_path: "_build/plts"
      ],
      compilers: [:phoenix_live_view] ++ Mix.compilers(),
      listeners: [Phoenix.CodeReloader],
      docs: docs(),
      releases: releases(),
      name: "ex_monty_cad_server",
      description:
        "A Model Context Protocol server for CAD: cadmpeg reads the file, " <>
          "quiddity names what it found and answers the geometry underneath, " <>
          "and the framework's own percept turns it into a graph memory a run loads.",
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
  # What `mix docs` builds, and what a published page is made of. The tool
  # reference is generated from the catalogue (`mix ex_monty_cad_server.tools_doc`),
  # so the page a model reads from `tools/list` and the page a person reads here
  # cannot say different things.
  defp docs do
    [
      main: "readme",
      source_ref: "main",
      extras: [
        "README.md",
        "docs/tools.md",
        "docs/architecture.md"
      ],
      groups_for_modules: [
        "The protocol": [ExMontyCadServer.Mcp, ExMontyCadServer.Mcp.Tools],
        "The tools this server adds": [
          ExMontyCadServer.Mcp.MemoryTools,
          ExMontyCadServer.Mcp.ClusterTools
        ],
        "The cluster": [ExMontyCadServer.Cluster],
        "The catalogue": [
          ExMontyCadServer.Catalogue,
          ExMontyCadServer.Catalogue.Part,
          ExMontyCadServer.Catalogue.Library
        ],
        "The database": [
          ExMontyCadServer.Repo,
          ExMontyCadServer.Database,
          ExMontyCadServer.Repo.Postgres,
          ExMontyCadServer.Repo.SQLite
        ],
        Transports: [
          ExMontyCadServer.Mcp.Session,
          ExMontyCadServerWeb.McpController,
          Mix.Tasks.ExMontyCadServer.Mcp
        ]
      ]
    ]
  end

  # One release, and the two scripts it carries (`rel/overlays/bin/`): serve HTTP,
  # or serve the protocol on stdio. `include_executables_for` is the build's own
  # platform, because a release is not a portable artifact — the two NIFs in it
  # are compiled for the machine that built them.
  defp releases do
    [
      ex_monty_cad_server: [
        include_executables_for: [:unix]
      ]
    ]
  end

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
      # 0.3 answers SRV queries as well as address lists, which is what a cluster
      # inside a Kubernetes service needs; the child spec this application starts
      # (`{DNSCluster, query: …}`) is unchanged.
      {:dns_cluster, "~> 0.3"},
      {:bandit, "~> 1.5"},
      # The database: the same Postgres and Ecto the studio app keeps its runs in,
      # and the same SQLite fallback so a release still works without a server.
      {:ecto_sql, "~> 3.13"},
      {:postgrex, ">= 0.0.0"},
      {:ecto_sqlite3, "~> 0.26"},
      # The reference for people: `mix docs`, and the page CI publishes.
      {:ex_doc, "~> 0.38", only: :dev, runtime: false},
      # The three engines the tools are made of. `ex_cadmpeg` reads the file,
      # `ex_quiddity` names what is in it and answers the geometry, and
      # `ex_monty_cad` turns a frame into the percept the framework's sensor modules
      # make and writes the library a run loads.
      {:ex_cadmpeg, "~> 0.1"},
      {:ex_quiddity, "~> 0.1"},
      # The contract a plugin and a cluster share, and the `:pg` registry that
      # carries the answer between nodes. The contract is the one thing two
      # packages have to agree about, so agreement is a version.
      #
      # `0.1.2` is the version that publishes what a host *carries*
      # (`MontyPlugin.Capabilities`), which is the half a plugin's `needs` is
      # checked against — and the walk this node offers needs `quiddity` and
      # `monty`, so a host that could not say it carries them would have its own
      # policy refused as unservable.
      {:ex_monty_plugin, "~> 0.1.2"},
      # `0.5` is the version with the feature walk (`MontyCad.Policy.FeatureWalk`)
      # and with `MontyCad.Inputs`, which is where a part is a name in
      # `$MONTY_DATA/parts`.
      {:ex_monty_cad, "~> 0.5"},
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
      # two steps the studio app's test alias takes before `test`.
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      precommit: ["compile --warnings-as-errors", "deps.unlock --unused", "format", "test"]
    ]
  end
end
