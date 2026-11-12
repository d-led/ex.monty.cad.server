# Two stages: one that has a Rust toolchain and the network, and one that has
# neither. What the second stage carries is a release — the BEAM, this
# application, and the two NIFs compiled in the first stage for this image's
# platform.
ARG ELIXIR_VERSION=1.20.5
ARG OTP_VERSION=29.1.2
ARG DEBIAN_VERSION=bookworm-20261104-slim

FROM hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION} AS build

# The engines are Rust: `ex_quiddity` and `ex_cadmpeg` compile a cdylib each, so
# the build stage needs cargo, and `ex_monty_cad` is a git dependency, so it
# needs git.
RUN apt-get update \
  && apt-get install -y --no-install-recommends build-essential ca-certificates curl git \
  && rm -rf /var/lib/apt/lists/*

ENV RUSTUP_HOME=/usr/local/rustup \
    CARGO_HOME=/usr/local/cargo \
    PATH=/usr/local/cargo/bin:$PATH

RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
  | sh -s -- -y --profile minimal --default-toolchain stable

ENV MIX_ENV=prod

WORKDIR /app

RUN mix local.hex --force && mix local.rebar --force

# Dependencies first, so a change to the code does not re-fetch or re-compile
# them: this is the slow layer, and it only moves when `mix.lock` does.
COPY mix.exs mix.lock ./
RUN mix deps.get --only prod && mix deps.compile

COPY config config
COPY lib lib

# No `priv`: this application ships no static files and no data of its own. The
# engines' own `priv` trees belong to the dependencies, which the build stage
# compiled into their applications.
RUN mix compile && mix release

FROM debian:${DEBIAN_VERSION} AS app

RUN apt-get update \
  && apt-get install -y --no-install-recommends ca-certificates libstdc++6 openssl \
  && rm -rf /var/lib/apt/lists/* \
  && useradd --create-home --shell /bin/bash app

WORKDIR /app
COPY --from=build --chown=app:app /app/_build/prod/rel/ex_monty_cad_server ./

# A path in a tool call is a path in this container: mount the directory that
# holds the parts, and name them under /parts.
VOLUME ["/parts"]

USER app

ENV PHX_SERVER=true \
    PORT=4000

EXPOSE 4000

CMD ["/app/bin/ex_monty_cad_server", "start"]
