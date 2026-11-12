import Config

# The suite runs on the Postgres of the CI service, partitioned by
# `MIX_TEST_PARTITION`. `ExMontyCadServer.Database.repo_module/0` follows
# `DATABASE_URL` when nothing names a repo, which in a test would be a file.
config :ex_monty_cad_server, :repo, ExMontyCadServer.Repo.Postgres

config :ex_monty_cad_server, ExMontyCadServer.Repo.Postgres,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "ex_monty_cad_server_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  # A suite wants the opposite of a release: a statement that hangs should fail
  # the test that issued it rather than wait the half-minute a write may take.
  timeout: 15_000,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :ex_monty_cad_server, ExMontyCadServerWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "oILH3nb7UC3cNPlAwaKKnB6x2m0gUy0Mx0goT2tF2tcKDu5qE12/90y1QWRkiUYO",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
