# How this server is put together

Three engines, one protocol. cadmpeg reads a CAD file, quiddity names what is in
it and answers the geometry, and the framework's own sensor module turns a sensed frame
into the percept a graph memory stores. This server is the surface over all three
plus the things only a server can do: keep a part open between requests, remember
what it has learned, and find the plugins other nodes offer.

## The protocol

One implementation, `ExMontyCadServer.Mcp`, is both transports. `handle/2` takes
one JSON-RPC message as a string and answers with the string to send back, and
nothing in it knows whether that string arrived on a pipe or over HTTP.

| method | what it answers |
| --- | --- |
| `initialize` | the revision both sides will speak, the capabilities, and the instruction text |
| `tools/list` | the catalogue, which is the tool reference this documentation includes |
| `tools/call` | one tool's answer: a sentence for the model and the numbers as structured content |
| `ping` | nothing, which is the whole point |

A request carries an `id` and is answered; a notification has none and is not.
The revision is negotiated over `2025-06-18`, `2025-03-26` and `2024-11-05`, and
a client that asks for something else is answered with the newest, because a
server that refuses a revision it half-speaks is worse than one that says which
one it will speak.

## The two transports

**stdio** — `mix ex_monty_cad_server.mcp` starts the application and answers on
stdin and stdout, one message per line. It refuses to start when either native
library is missing, because a server that starts and then fails every call is
harder to diagnose than one that does not start.

**HTTP** — `POST /mcp` in the `:api` pipeline. A message that is not JSON-RPC is
`400` with the protocol's parse error; a notification is `202` with no body.

A pipe keeps its state in its own loop. A request cannot: each one arrives in a
process that dies when it answers. So between requests the state — the documents
cadmpeg has open, the parts quiddity has read — lives in
`ExMontyCadServer.Mcp.Session`, one GenServer per server, and a call is answered
with the state it produced.

## The engines

Each engine already answers the protocol on its own, with its own `Tools` module,
its own `catalogue/0` and its own slice of state. This server does not
re-implement any of those answers: `ExMontyCadServer.Mcp.Tools.engines/0` says
which engine owns a name and the call is handed over with that engine's state.
Names carry their engine's prefix, so two engines cannot claim the same one.

`ExMontyCadServer.Mcp.MemoryTools` is what the server adds: the tools that need
all three engines at once, and the only ones that write.

| question | tool | what it takes |
| --- | --- | --- |
| what is this part | `monty_cad_brief` | a path |
| what would a sensor perceive here | `monty_cad_sense` | a point, a direction |
| what am I standing on | `monty_cad_on_face` | a path, a face |
| what is near | `monty_cad_features_near` | a point, a radius |
| what is ahead | `monty_cad_next_feature` | a point, a direction, a cone |
| what has been learned already | `monty_cad_libraries` | nothing |
| learn this part | `monty_cad_library` | a path, an object id, an output path |

The reference for all nineteen tools — every engine's, with argument schemas — is
[the tools page](tools.html), which is generated from the catalogue.

## The cluster

A plugin is a process another node offers: an experiment, a learning module, a
motor policy. The registry is `MontyPlugin.Registry` from `ex_monty_plugin` —
`ExMontyCadServer.Cluster` is this server's name for it — and it keeps them in
`:pg`, whose point is that a name joined on one node is visible on every node and
forgotten when a node goes down. `Registry` would not do: it is one node's table.

The scope (`PLUGIN_SCOPE`, default `monty_plugins`) is shared with every other node
of the estate, which is the point: a policy offered by an Elixir Monty Studio node and a
policy offered here are the same thing to a caller. `PLUGIN_DISCOVERY=none` takes a
node out of the cluster, and `cad_plugin_list` says so rather than answering
"0 plugins" — silence about a variable is the failure mode that costs an afternoon.
The `:pg` process itself is started by that package's application, so this server's
tree does not start it a second time.

A provider answers `:describe` with its name, kind, version, what it needs, and
where it may run. `placement: :owner_only` exists because a B-rep handle cannot
leave the node that holds it — a motor policy that reads a part has to be called
where the part is, and saying so is part of the contract rather than a detail a
caller discovers.

What is not routed is the learning module's inner loop, which runs thousands of
operations per step: it is advertised and compiled where it will run, never called
across the network. Experiments and motor policies are called once per step, so a
remote call is free.

### What this node offers

`ExMontyCadServer.Policy.FeatureWalk` is a provider of its own: the node offers
`monty_cad.feature_walk`, the walk from feature to feature over a part's surface
(`MontyCad.Policy.FeatureWalk` in `ex_monty_cad`). It answers the four messages a
remote caller sends — `{:new, []}`, `{:call, policy, …}`, `{:reset, policy}`,
`{:state_dict, policy}` — which is `Monty.Studio.RemotePolicy`'s whole agreement
with a host.

The part cannot cross, so what crosses is the walk's **progress**: the feature it
chose, the ones it has been to, how many steps it took. The part is opened here on
the first episode and kept, which is the `:owner_only` placement that section
above is about, made concrete.

The part is named by `MONTY_CAD_PART`: a part's file name in `$MONTY_DATA/parts`
(`MontyCad.Inputs`, the same convention the studio resolves), or the path of a file
that exists. A node with no part named still starts and offers the policy — the
first episode is refused with the sentence that names the variable, which is the
same answer `cad_plugin_describe` gives a caller who asks first.

## The catalogue

`monty_cad_library` writes two things: the library file a run loads, and a row
that says what was written. The second is what makes the first findable next
week — the part by the digest of its bytes, the memory by the object it is
labelled as and how much of the part it saw.

The database is chosen when the server starts: Postgres when `DATABASE_URL`
names one, SQLite in a file otherwise, so a release on a machine with no database
server still keeps what it made. Both drivers are compiled in, which is why there
are two repo modules and one name (`ExMontyCadServer.Repo`) the application calls
them by.

## Supervision

```mermaid
graph TD
  S[ExMontyCadServer.Supervisor] --> T[Telemetry]
  S --> D[DNSCluster]
  S --> P[Phoenix.PubSub]
  S --> PG[":pg"]
  S --> R[Repo: Postgres or SQLite]
  S --> SS[Mcp.Session]
  S --> PW[Policy.FeatureWalk]
  S --> E[Endpoint]
```

The repo starts before the session, and the session before the endpoint: nothing
that answers a request may outlive the store it reads. The policy registers itself
from its `init/1`, so a node that restarts re-offers it, and one that stops takes
its name out of the cluster with it.
