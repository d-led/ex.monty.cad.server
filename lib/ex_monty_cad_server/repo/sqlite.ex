defmodule ExMontyCadServer.Repo.SQLite do
  @moduledoc "The catalogue in a file, when no database server was named."
  use Ecto.Repo, otp_app: :ex_monty_cad_server, adapter: Ecto.Adapters.SQLite3
end
