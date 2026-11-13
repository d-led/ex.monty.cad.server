# ex_monty_cad_server

A Model Context Protocol server for CAD, over three engines that answer different
questions about the same part:

| Engine | The question it answers |
| --- | --- |
| [cadmpeg](https://github.com/cadmpeg/cadmpeg) | What is in this file, and how faithfully was it read? |
| [quiddity](https://github.com/pzfreo/quiddity) | What are the features, and what does the geometry look like where a sensor would stand? |
| Monty, via [ex_monty_cad](https://github.com/d-led/ex.monty.cad) | What would Monty's own observation processor perceive there, and what library would a run load? |

The protocol is the interface. A tool call is the unit of work, so the same server
is usable by an assistant over stdio, by a program over HTTP, and by anything that
can POST JSON — a container, a remote deployment, or a desktop shell carrying the
same release.

## Documentation

| Where | What |
| --- | --- |
| [d-led.github.io/ex.monty.cad.server](https://d-led.github.io/ex.monty.cad.server/) | this server: the architecture, the transports, the catalogue, and the API reference `mix docs` builds |
| [`docs/tools.md`](docs/tools.md) | the tool reference, generated from the catalogue the server answers `tools/list` with |
| [hexdocs.pm/ex_cadmpeg](https://hexdocs.pm/ex_cadmpeg) | the file reader: modules, options, the document model |
| [hexdocs.pm/ex_quiddity](https://hexdocs.pm/ex_quiddity) | the geometry: recognition, frames, rays, surfaces |
| [hexdocs.pm/ex_monty_cad](https://hexdocs.pm/ex_monty_cad) | the percept and the library a run loads |

The tool reference is not written by hand: `mix ex_monty_cad_server.tools_doc`
renders it from the same module attributes the server answers with, and CI fails
when the committed page and the catalogue disagree. A description improved for a
model is therefore improved for a reader, or it is not improved at all.

## The tools

From **cadmpeg**:

| Tool | Answer |
| --- | --- |
| `cadmpeg_formats` | which formats this build reads and writes — compiled-in features, so it is a fact rather than a promise |
| `cadmpeg_inspect` | the decode report: what was transferred, and every loss with its reason |
| `cadmpeg_convert` | the same document written as `step` or as cadmpeg's own JSON, with the export report |

From **quiddity**:

| Tool | Answer |
| --- | --- |
| `quiddity_part` | what the part is: faces, recognized features, the frame |
| `quiddity_features`, `quiddity_face`, `quiddity_correspond` | the recognition, one face, and two revisions compared |
| `quiddity_probe`, `quiddity_sense`, `quiddity_frame`, `quiddity_mesh` | a ray, a sensor at a point, the camera frame, the mesh |
| `quiddity_export_mjcf` | a MuJoCo scene in metres |

From this server, over all three:

| Tool | Answer |
| --- | --- |
| `monty_cad_brief` | what quiddity recognised: the feature families and how many of each, and the faces no feature claims |
| `monty_cad_features_near` | which features sit within a radius of a point, nearest first — the query a policy choosing where to sense next needs |
| `monty_cad_next_feature` | which features lie ahead along a direction, within a cone, with the distance and the angle off it |
| `monty_cad_on_face` | which feature claims a face — or that it is body, refused or unexplained |
| `monty_cad_sense` | the node features Monty's sensor module would store if it stood at a point and looked along a direction |
| `monty_cad_library` | samples the surface, takes that percept at every visit, and writes the gzipped library a run loads |
| `monty_cad_libraries` | what this server has already learned, newest first: the object, the part, the node count and the file |
| `cad_plugin_list`, `cad_plugin_describe` | which experiments, learning modules and motor policies a cluster offers |

## Two transports, one server

`ExMontyCadServer.Mcp.handle/2` is the whole protocol: a JSON-RPC message in, a
reply (or `nil` for a notification) and the state after it. Both transports call
it, so they cannot drift.

**stdio** — a client launches it. For a checkout:

```json
{
  "mcpServers": {
    "cad": {
      "command": "mix",
      "args": ["ex_monty_cad_server.mcp"],
      "cwd": "/path/to/ex.monty.cad.server"
    }
  }
}
```

For a release, point at the binary instead — no Elixir, no `mix`, nothing to
build on the machine that runs it:

```json
{"mcpServers": {"cad": {"command": "/opt/ex_monty_cad_server/bin/ex_monty_cad_server", "args": ["mcp"]}}}
```

**HTTP** — one message a request:

```sh
curl -s localhost:4000/mcp -H 'content-type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'
```

A client that speaks streamable HTTP names the same endpoint:

```json
{"mcpServers": {"cad": {"type": "http", "url": "http://localhost:4000/mcp"}}}
```

MCP Inspector, to try the tools without writing a client:

```sh
npx @modelcontextprotocol/inspector mix ex_monty_cad_server.mcp
```

A request carries one JSON-RPC message; a batch is refused rather than
half-answered. A notification is answered `202` with an empty body.

## A part is opened once

Calls name a path; the server keeps what it opened. Over stdio that cache is the
loop's state, and over HTTP it is `ExMontyCadServer.Mcp.Session` — one process, so
two requests cannot interleave their writes to it. Restarting the server costs a
re-read, and nothing on disk depends on the cache.

A B-rep handle is a Rust resource in the memory of the node that opened it: it
serves every process on that node and cannot be sent to another one. That is why
paths are the interface and why the placement rule below exists.

## What a cluster offers

A run is made of modules another node has: an experiment, the learning modules it
steps, the motor policies that decide where to sense next.
`ExMontyCadServer.Cluster` registers those under names with `:pg` — OTP's
cluster-wide process group, which is what `Registry` is not: a `Registry` names
processes on the node that started it.

A plugin is a process that answers `:describe`:

```elixir
%{
  "name" => "feature_following",
  "kind" => :motor_policy,
  "version" => "0.1.0",
  # It reads a part's B-rep, and a B-rep handle cannot leave its node.
  "placement" => :owner_only,
  "needs" => [:quiddity]
}
```

The three kinds are `:experiment`, `:learning_module` and `:motor_policy`, and
placement is not decoration:

- an experiment or a motor policy is called once per step, so a remote call costs
  microseconds against the step and the registry can route it;
- a learning module runs thousands of operations a step over hypotheses and a
  k-d tree, so what the cluster offers for it is a version and a capability, and
  the module is compiled in;
- a policy that consults quiddity must run where the part was opened, which
  `:owner_only` says and `Cluster.lookup/2` answers with the node.

`cad_plugin_list` and `cad_plugin_describe` expose the same thing over the
protocol, so a model can ask what the cluster has before calling anything.

## Running it

```sh
mix deps.get
mix ecto.setup                   # the catalogue's tables, in the database below
mix test
PORT=4000 mix phx.server          # HTTP on /mcp, a landing page on /
mix ex_monty_cad_server.mcp       # stdio, for a client that launches it
```

It needs the two Rust engines built, which `mix deps.get && mix compile` does.
`mix ex_monty_cad_server.mcp` refuses to start when one is missing rather than
failing on the third question.

### The database

Postgres when `DATABASE_URL` names one, SQLite in a file otherwise — so a machine
with no database server still keeps what it made:

```sh
DATABASE_URL=ecto://postgres:postgres@localhost/ex_monty_cad_server mix ecto.setup
PORT=4000 mix phx.server
```

The migrations are in `priv/repo/migrations`. `SQLITE_PATH` moves the file when
SQLite is the store. A development database server, if you want one in a
container:

```sh
docker run --rm -d --name ex-monty-cad-db -p 5432:5432 \
  -e POSTGRES_PASSWORD=postgres postgres:17
```

### The tests, and the two that need a second node

```sh
mix test                                                    # 45 tests
elixir --name cad@127.0.0.1 -S mix test --only distributed   # the other 2
```

The cluster tests start a second node with `:peer` and offer a plugin on it,
because "visible on every node" is a claim worth failing on. A peer needs a
distributed VM, and `mix test` does not start one, so they are tagged
`:distributed` and a plain run excludes them — the second command is how to run
them, and what CI does. No `--cookie` on that line: the peer inherits the default
one, and a cookie on one side only is a handshake refused.

### As a release

`mix release` builds the whole server — the application, both Rust engines compiled
for the machine that built it, and the migrations — into one directory that needs
no Elixir on the machine that runs it:

```sh
MIX_ENV=prod mix release
_build/prod/rel/ex_monty_cad_server/bin/server     # migrate, then serve HTTP
_build/prod/rel/ex_monty_cad_server/bin/mcp        # serve the protocol on stdio
_build/prod/rel/ex_monty_cad_server/bin/migrate    # just the schema, as a deploy step
```

`bin/server` migrates before it serves (`MIGRATE_ON_BOOT=false` turns that off and
makes `bin/migrate` the deploy step). `bin/mcp` migrates too, so a client that
launches a release on a fresh machine finds a catalogue rather than a missing
table.

A tag (`v*.*.*`) builds the release on Linux in CI and attaches the archive to a
GitHub release; the tag, `VERSION` and `mix.exs` have to agree or the job refuses.

The version is moved by a script rather than by hand, and so is the tag:

```sh
elixir scripts/release.exs bump patch     # 0.1.0 -> 0.1.1, in VERSION and mix.exs
git add -A && git commit -m "release: 0.1.1" && git push
./scripts/tag_and_push_version.sh          # refuses a dirty tree or red CI
```

`scripts/release.exs check` runs in CI too, so a version edited in one file by hand
is refused on the push that made it rather than at the tag.

Environment, and what each one is for:

| variable | what it does |
| --- | --- |
| `DATABASE_URL` | the Postgres to keep the catalogue in; without it, SQLite in `SQLITE_PATH` |
| `SQLITE_PATH` | where the catalogue file goes (default `<DATA_DIR>/catalogue.db`) |
| `DATA_DIR` | the directory a container mounts a volume at (default `/app/data`) |
| `PHX_SERVER` | set by `bin/server`: start the endpoint. `bin/mcp` leaves it unset and serves nothing but the pipe |
| `SECRET_KEY_BASE` | signs cookies; required only when the endpoint serves |
| `NODE_NAME` | the node's name, for a deployment that is one node of several — this is what makes plugins cluster-wide (`NODE_COOKIE` is its companion; a release spells them `RELEASE_NODE`/`RELEASE_COOKIE`) |
| `PLUGIN_SCOPE` | the `:pg` scope plugins register in (default `monty_plugins`) — shared with every other node of the estate, so a policy offered by a Monty studio node and one offered here are the same thing to a caller |
| `PLUGIN_DISCOVERY` | `pg` (default) or `none`: `none` takes this node out of the cluster, and `cad_plugin_list` says so rather than looking empty |
| `PORT` | the endpoint's port (default 4000) |

### In a container

The `Dockerfile` builds the release for the platform it is built on, with the two
NIFs compiled in. It is offered, not exercised: CI does not build an image, so
treat the file as a starting point rather than as a tested artifact.

```sh
docker build -t ex-monty-cad-server .
docker run --rm -p 4000:4000 -v "$PWD/parts:/parts" ex-monty-cad-server
```

Mount the directory that holds the parts: a path in a tool call is a path in the
container. `DATABASE_URL` switches it to Postgres, and without one the catalogue
is a file inside the container — mount a volume at the directory
`SQLITE_PATH` names, or point it elsewhere than the default.

## Dependencies, and one that is not on Hex yet

`ex_quiddity` and `ex_cadmpeg` are on Hex. `ex_monty_cad` is a `git` dependency
here, pinned by `mix.lock`, because the package has not been published; the day it
is, the line in `mix.exs` becomes `{:ex_monty_cad, "~> 0.1"}` and nothing else
changes.

## What this is not

- Not a CAD editor: it reads, reports, converts and samples. There is no toolbar
  and no save button.
- Not a Monty framework: the framework is Monty's, reached through
  `ex_tbp_monty_core`. This server is the join between a drawing and a memory.
- Not a training run either: `monty_cad_library` writes the library a run loads;
  running the experiment is the studio's job, not this server's.
