defmodule ExMontyCadServer.MixProject do
  use Mix.Project

  def project do
    [
      app: :ex_monty_cad_server,
      version: "0.1.0",
      elixir: "~> 1.17",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
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
      setup: ["deps.get"],
      precommit: ["compile --warnings-as-errors", "deps.unlock --unused", "format", "test"]
    ]
  end
end
