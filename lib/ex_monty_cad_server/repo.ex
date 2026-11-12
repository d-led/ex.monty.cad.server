defmodule ExMontyCadServer.Repo do
  @moduledoc """
  The database this server keeps its catalogue in, whichever that is.

  Ecto binds a repo to one adapter at compile time, so one release that serves
  Postgres when `DATABASE_URL` names a server and a SQLite file otherwise needs
  two compiled repos — `ExMontyCadServer.Repo.Postgres` and
  `ExMontyCadServer.Repo.SQLite` — and one name for the application to call them
  by: this module, which forwards to the one chosen at boot.

  The same shape as `ex_tbp_monty`'s `ExTbpMonty.Repo`: adding a call means
  adding a line here, and forgetting one is a warning at the call site rather
  than a silent no-op.
  """

  @doc "The repo module this instance uses."
  @spec current() :: module()
  def current, do: ExMontyCadServer.Database.repo_module()

  @spec config() :: keyword()
  def config, do: current().config()

  @spec config(atom()) :: term()
  def config(key), do: current().config(key)

  @spec transaction((-> term()) | Ecto.Multi.t(), keyword()) :: {:ok, term()} | {:error, term()}
  def transaction(fun_or_multi, opts \\ []), do: current().transaction(fun_or_multi, opts)

  @spec rollback(term()) :: no_return()
  def rollback(value), do: current().rollback(value)

  @spec all(Ecto.Queryable.t(), keyword()) :: [term()]
  def all(queryable, opts \\ []), do: current().all(queryable, opts)

  @spec one(Ecto.Queryable.t(), keyword()) :: term() | nil
  def one(queryable, opts \\ []), do: current().one(queryable, opts)

  @spec get(Ecto.Queryable.t(), term(), keyword()) :: struct() | nil
  def get(queryable, id, opts \\ []), do: current().get(queryable, id, opts)

  @spec get_by(Ecto.Queryable.t(), keyword() | map(), keyword()) :: struct() | nil
  def get_by(queryable, clauses, opts \\ []), do: current().get_by(queryable, clauses, opts)

  @spec get_by!(Ecto.Queryable.t(), keyword() | map(), keyword()) :: struct()
  def get_by!(queryable, clauses, opts \\ []), do: current().get_by!(queryable, clauses, opts)

  @spec insert(struct() | Ecto.Changeset.t(), keyword()) :: {:ok, term()} | {:error, term()}
  def insert(struct_or_changeset, opts \\ []), do: current().insert(struct_or_changeset, opts)

  # `insert/2` with the caller's own keys — `:on_conflict` and `:conflict_target`
  # — passed through untouched: a row that is already there is answered with the
  # row that is there.
  @spec insert!(struct() | Ecto.Changeset.t(), keyword()) :: term()
  def insert!(struct_or_changeset, opts \\ []), do: current().insert!(struct_or_changeset, opts)

  @spec update(struct() | Ecto.Changeset.t(), keyword()) :: {:ok, term()} | {:error, term()}
  def update(struct_or_changeset, opts \\ []), do: current().update(struct_or_changeset, opts)

  @spec delete(struct() | Ecto.Changeset.t(), keyword()) :: {:ok, term()} | {:error, term()}
  def delete(struct_or_changeset, opts \\ []), do: current().delete(struct_or_changeset, opts)

  @spec delete_all(Ecto.Queryable.t(), keyword()) :: {non_neg_integer(), nil | [term()]}
  def delete_all(queryable, opts \\ []), do: current().delete_all(queryable, opts)

  @spec aggregate(Ecto.Queryable.t(), :count | :avg | :sum | :max | :min, term(), keyword()) ::
          term()
  def aggregate(queryable, aggregate, field, opts \\ []),
    do: current().aggregate(queryable, aggregate, field, opts)

  @spec exists?(Ecto.Queryable.t(), keyword()) :: boolean()
  def exists?(queryable, opts \\ []), do: current().exists?(queryable, opts)

  @spec preload(struct() | [struct()], term(), keyword()) :: struct() | [struct()]
  def preload(struct_or_structs, preloads, opts \\ []),
    do: current().preload(struct_or_structs, preloads, opts)

  @spec query(String.t(), list(), keyword()) :: {:ok, term()} | {:error, term()}
  def query(sql, params \\ [], opts \\ []), do: current().query(sql, params, opts)
end
