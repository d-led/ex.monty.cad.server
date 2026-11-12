defmodule ExMontyCadServer.Repo.Postgres do
  @moduledoc "The catalogue in a Postgres server, when `DATABASE_URL` names one."
  use Ecto.Repo, otp_app: :ex_monty_cad_server, adapter: Ecto.Adapters.Postgres
end
