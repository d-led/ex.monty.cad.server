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
| `monty_cad_sense` | the node features Monty's sensor module would store if it stood at a point and looked along a direction |
| `monty_cad_library` | samples the surface, takes that percept at every visit, and writes the gzipped library a run loads |
| `cad_plugin_list`, `cad_plugin_describe` | which experiments, learning modules and motor policies a cluster offers |

## Two transports, one server

`ExMontyCadServer.Mcp.handle/2` is the whole protocol: a JSON-RPC message in, a
reply (or `nil` for a notification) and the state after it. Both transports call
it, so they cannot drift.

**stdio** — a client launches it:

```json
{"mcpServers": {"cad": {"command": "mix", "args": ["ex_monty_cad_server.mcp"]}}}
```

**HTTP** — one message a request:

```sh
curl -s localhost:4000/mcp -H 'content-type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'
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
mix test
PORT=4000 mix phx.server          # HTTP on /mcp, a landing page on /
mix ex_monty_cad_server.mcp       # stdio, for a client that launches it
```

It needs the two Rust engines built, which `mix deps.get && mix compile` does.
`mix ex_monty_cad_server.mcp` refuses to start when one is missing rather than
failing on the third question.

### In a container

```sh
docker build -t ex-monty-cad-server .
docker run --rm -p 4000:4000 -v "$PWD/parts:/parts" ex-monty-cad-server
```

The image runs the release, not `mix`, and carries the two NIFs built for the
image's platform. Mount the directory that holds the parts: a path in a tool call
is a path in the container.

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
