defmodule ExMontyCadServer.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      ExMontyCadServerWeb.Telemetry,
      {DNSCluster,
       query: Application.get_env(:ex_monty_cad_server, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: ExMontyCadServer.PubSub},
      # The cluster-wide process groups a plugin is registered in: `:pg` is what
      # knows a name on one node on every other node, and what forgets it when a
      # node goes down. The registry is `MontyPlugin.Registry`, shared with every
      # other node of the estate, and its child is the `:pg` process under the
      # scope `PLUGIN_SCOPE` names.
      MontyPlugin.Registry,
      # The catalogue: the parts this server has made a memory of and the
      # memories it wrote. Whichever repo `DATABASE_URL` chose at boot; it starts
      # before anything that would read or write it.
      ExMontyCadServer.Database.repo_module(),
      # What the server remembers between HTTP requests: the documents cadmpeg
      # has opened and the parts quiddity has read. A transport that is a pipe
      # keeps its own state in its own loop; a request cannot.
      ExMontyCadServer.Mcp.Session,
      # Start to serve requests, typically the last entry
      ExMontyCadServerWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: ExMontyCadServer.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    ExMontyCadServerWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
