# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :ex_monty_cad_server,
  ecto_repos: [ExMontyCadServer.Repo.Postgres],
  generators: [timestamp_type: :utc_datetime]

# The migrations sit in `priv/repo`, which is what Ecto's default builds from a
# repo called `Repo`; the two repos are `Repo.Postgres` and `Repo.SQLite`, so the
# directory is named rather than inherited. Ecto logs every statement at `:debug`,
# which a console following a request does not want; `log: :debug` here is how a
# console asks for the statements.
config :ex_monty_cad_server, ExMontyCadServer.Repo.Postgres,
  priv: "priv/repo",
  log: false,
  # How long a caller may hold a connection before DBConnection gives up: the
  # library write on a large part is the long one, and fifteen seconds is a
  # number a part can outgrow.
  timeout: 30_000,
  queue_target: 1_000,
  queue_interval: 10_000

config :ex_monty_cad_server, ExMontyCadServer.Repo.SQLite, priv: "priv/repo", log: false

# Configure the endpoint
config :ex_monty_cad_server, ExMontyCadServerWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: ExMontyCadServerWeb.ErrorHTML, json: ExMontyCadServerWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: ExMontyCadServer.PubSub,
  live_view: [signing_salt: "monlr6jT"]

# Configure LiveView
config :phoenix_live_view,
  # the attribute set on all root tags. Used for Phoenix.LiveView.ColocatedCSS.
  root_tag_attribute: "phx-r"

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
