defmodule ExMontyCadServer.Experiment do
  @moduledoc """
  This node's offer of the CAD experiment: Monty's ten-similar-objects run with a
  part's own geometry as its motor system.

  `base_10simobj_surf_agent` is Monty's own experiment — ten similar objects, a
  surface agent, its learning module, its training and evaluation epochs — and this
  definition is that experiment with one thing replaced: the motor system is
  `monty_cad.feature_walk`, the policy that ray-casts each step against an exact
  B-rep instead of reading the patch it was just handed (`MontyCad.Policy.FeatureWalk`).
  Everything else stays the config's, so a run of this definition is still a
  recognition, and the record says which plugin defined it.

  ## One variation of a shared experiment

  The same base config is offered as a variation by each plugin host whose library
  can decide something — `flyverse_plugin.10simobj_surf_agent` steps it with a
  spiking connectome, `example_plugin.10simobj_surf_agent_one_episode` with a
  surface stepper — and this is the geometry's. The three are compared by being
  the same config, the same seed and the same budget, differing only in who
  decides; `docs/plugins.md` in the studio keeps the table.

  ## The world, which a definition cannot name

  `Monty.Studio.PluginExperiment` composes the base config on the studio's node and
  reads from a definition what it may substitute: the config, the modules, the
  seed. A world is not one of those — it is a core noun, chosen when the run is
  opened. So a run of this experiment must be **started with the `cad` world**,
  which is where the part is the world: the walk converts the sensor's pose into
  the part's millimetres and walks the faces it finds there.

  Started on `mujoco` it would do something else and say nothing about it: the
  sensor would move through a scene of YCB meshes while the policy answered about
  a plate that is not in it. The actions would be real, the decisions would be
  about another object, and the record would look like any other run. That is why
  it is written here rather than left to be discovered.

  ## What it does not claim

  That the geometry recognises better. `docs/cad.md` in the studio is the
  measurement: under the walk the patch stops being a new observation at all (1 of
  497 steps against the curvature policy's 37), and a planar part still gets no
  definite pose from it, so the episodes do not conclude for a reason upstream of
  the policy. This definition exists so that the two policies can be run side by
  side and compared, not because one is expected to win.

  ## Why `needs` names the geometry

  An experiment's answer is data, and this one's data names a policy that cannot be
  served without `Quiddity`. `Monty.Studio.RemotePolicy.among/3` treats a host that
  cannot prove it carries what a plugin declares as no candidate, so declaring
  `[:quiddity, :monty]` is what keeps a cluster from listing an experiment that no
  node in it can start — the refusal names the missing package instead of the run
  failing at its first step.
  """

  use GenServer

  require Logger

  alias ExMontyCadServer.Cluster

  # The name a cluster registers, and the name a run asks for. Prefixed with the
  # package rather than the host, as the policy's own name is: a name is
  # cluster-wide, and which node hosts it is the cluster's answer, not the name's.
  @name "monty_cad.10simobj_surf_agent"

  # The config this variation steps: the same one every variation of this
  # comparison steps.
  @base "base_10simobj_surf_agent"

  # The walk's own name, as `MontyCad.Policy.FeatureWalk.describe/0` gives it. One
  # test asks the policy process for the name it is offering and compares, so a
  # rename breaks the test rather than the run.
  @motor_system "monty_cad.feature_walk"

  # The base config's own seed, written down rather than inherited: a definition
  # that said one thing and ran under another would be a record that disagrees with
  # itself, and two variations of one experiment would differ for a reason nobody
  # wrote down. The other variations write the same number.
  @seed 42

  @doc """
  The process, under the module's own name unless it is told another.

  One name per node, because two processes offering one experiment would be one
  experiment offered twice; a case that needs a second one says `name: nil`.
  """
  def start_link(opts \\ []) do
    case Keyword.get(opts, :name, __MODULE__) do
      nil -> GenServer.start_link(__MODULE__, opts)
      name -> GenServer.start_link(__MODULE__, opts, name: name)
    end
  end

  @doc "The name a cluster registers it under, and the name a run asks for."
  @spec name() :: String.t()
  def name, do: @name

  @doc "What a cluster is told about it."
  @spec describe() :: MontyPlugin.description()
  def describe do
    %{
      "name" => @name,
      "kind" => :experiment,
      "version" => version(),
      "placement" => :anywhere,
      "needs" => [:quiddity, :monty]
    }
  end

  @doc """
  The run it would perform.

  There is no `episodes` key: a definition cannot ask for fewer episodes, and a
  number here that nothing read would be a promise the record could not keep.
  """
  @spec run() :: map()
  def run do
    %{
      "base" => @base,
      "learning_modules" => [],
      "motor_system" => @motor_system,
      "seed" => @seed
    }
  end

  @doc """
  This application's version, which is what a description reports.

  Read rather than written twice: `describe/0` is a function, so the version a
  cluster sees is the version in `mix.exs` at the moment it asked.
  """
  @spec version() :: String.t()
  def version do
    case Application.spec(:ex_monty_cad_server, :vsn) do
      nil -> "unknown"
      vsn -> to_string(vsn)
    end
  end

  @impl true
  def init(_opts) do
    description = describe()

    with :ok <- MontyPlugin.conforms?(description),
         :ok <- Cluster.register(description["kind"], description["name"], self()) do
      Logger.info(
        "cad experiment: offering #{description["kind"]} #{description["name"]} " <>
          "#{description["version"]} (#{description["placement"]})"
      )

      {:ok, %{}}
    else
      {:error, reason} -> {:stop, "#{@name} cannot be offered: #{reason}"}
    end
  end

  @impl true
  def handle_call(:describe, _from, state), do: {:reply, describe(), state}

  # A definition is asked once, and what comes back is data: the config's name and
  # the modules the run wants for it.
  def handle_call(:run, _from, state), do: {:reply, {:ok, run()}, state}
end
