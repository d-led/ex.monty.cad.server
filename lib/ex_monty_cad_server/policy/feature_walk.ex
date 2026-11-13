defmodule ExMontyCadServer.Policy.FeatureWalk do
  @moduledoc """
  This node's offer of `monty_cad.feature_walk`: one process, and the part it walks over.

  A motor policy is called once per step from whichever node runs the experiment,
  and `Monty.Studio.RemotePolicy` says the policy itself travels with each call —
  a provider that kept it would give every episode in the cluster the same one.
  This policy cannot do that, and the reader deserves the reason rather than a
  silent exception:

  ## The walk reads a face, and a face is here

  `MontyCad.Policy.FeatureWalk` ray-casts against an open part, and an open part is
  a resource in the memory of the node that opened it. It cannot cross. So this
  process opens the part once and keeps it, and what travels is the walk's
  **progress**: the feature it chose, the features it has been to, how many steps
  it has taken — everything that makes one episode's walk different from another's.

      {:new, []}                    => {:ok, progress}   the fresh walk
      {:call, progress, …}          => {:ok, result, progress}
      {:reset, progress}            => {:ok, progress}
      {:state_dict, progress}       => {:ok, recorded}

  Two episodes stay apart because `progress` is theirs, and the part stays here
  because it cannot leave. That is what `:owner_only` means, and it is why the
  description says so: a caller that reaches for this policy from another node is
  turned away by the registry rather than by a failed send halfway through a step.

  ## No part is not a failed boot

  The policy is a policy whether or not a part has been named, so the node starts
  and offers it, and the first episode is refused with the sentence that names
  `MONTY_CAD_PART` (`MontyCad.Inputs`). A cluster that lost a name because a file
  was missing would be a cluster that looks empty, and the sentence is the repair.

  ## One caveat about the release it is pinned to

  `needs` is `[:quiddity, :monty]`, and a host can only be held to that once it
  publishes what it carries (`MontyPlugin.Capabilities`, `ex_monty_plugin` 0.1.2).
  A deployment still locking 0.1.1 will see this policy refused with "does not
  offer :quiddity, :monty" — which is the truth about what the node can prove, and
  `mix.exs` says how to move it.
  """

  use GenServer

  require Logger

  alias ExMontyCadServer.Cluster
  alias MontyCad.Inputs
  alias MontyCad.Policy.FeatureWalk, as: Walk
  alias Quiddity.Part

  @typedoc """
  What a caller holds: the walk's progress, and nothing that cannot cross a node.

  `MontyCad.Policy.FeatureWalk.state_dict/1`'s answer, because that is the walk's
  own account of what it has done — a second map with the same fields would be a
  second thing to keep true.
  """
  @type progress :: %{
          target: String.t() | nil,
          visited: [String.t()],
          walked: non_neg_integer(),
          standoff: float(),
          step: float()
        }

  @doc """
  The process, under the module's own name unless it is told another.

  One name per node, because two processes offering one policy would be one policy
  offered twice; a case that needs a second one says `name: nil`.
  """
  def start_link(opts \\ []) do
    case Keyword.get(opts, :name, __MODULE__) do
      nil -> GenServer.start_link(__MODULE__, opts)
      name -> GenServer.start_link(__MODULE__, opts, name: name)
    end
  end

  @doc "What the cluster is told about this policy — the package's own answer."
  @spec describe() :: MontyPlugin.description()
  def describe, do: Walk.describe()

  @impl true
  def init(opts) do
    description = describe()

    with :ok <- MontyPlugin.conforms?(description),
         :ok <- Cluster.register(description["kind"], description["name"], self()) do
      Logger.info(
        "cad policy: offering #{description["kind"]} #{description["name"]} " <>
          "#{description["version"]} (#{description["placement"]})"
      )

      {:ok, %{open: nil, opener: Keyword.get(opts, :opener, &open_part/0)}}
    else
      {:error, reason} -> {:stop, "#{description["name"]} cannot be offered: #{reason}"}
    end
  end

  @impl true
  def handle_call(:describe, _from, state), do: {:reply, describe(), state}

  def handle_call({:new, _options}, _from, state) do
    decide(state, fn opened ->
      walk = new_walk(opened)
      {:ok, progress(walk)}
    end)
  end

  # The framework's six arguments, the policy among them. This policy decides for
  # one goal and looks at none of them: the walk reads the depth it is handed and
  # the feature it is aiming at, both of which are in the progress it was given.
  def handle_call({:call, progress, ctx, observations, motor_state, percept, goal}, _from, state) do
    decide(state, fn opened ->
      with {:ok, walk} <- resume(progress, opened) do
        {result, walk} = Walk.call(walk, ctx, observations, motor_state, percept, goal)
        {:ok, result, progress(walk)}
      end
    end)
  end

  def handle_call({:reset, progress}, _from, state) do
    decide(state, fn opened ->
      with {:ok, walk} <- resume(progress, opened), do: {:ok, progress(Walk.reset(walk))}
    end)
  end

  def handle_call({:state_dict, progress}, _from, state) do
    if is_map(progress) and Map.has_key?(progress, :walked),
      do: {:reply, {:ok, progress}, state},
      else: {:reply, {:error, not_a_progress(progress)}, state}
  end

  # Every message but `:describe` is an episode asking about the part, so every one
  # of them opens it first — once, and never twice in a node's life.
  defp decide(state, answer) do
    case opened(state) do
      {:ok, opened, state} -> {:reply, answer.(opened), state}
      {:error, why} -> {:reply, {:error, why}, state}
    end
  end

  # -- the part, opened once --------------------------------------------------

  # A step is tens of times a second, and opening a STEP file is not: the part is
  # opened on the first message that needs it and kept until this process stops.
  defp opened(%{open: %{part: %Part{}} = opened} = state), do: {:ok, opened, state}

  defp opened(%{opener: opener, open: nil} = state) do
    case opener.() do
      {:ok, opened} -> {:ok, opened, %{state | open: opened}}
      {:error, why} -> {:error, why}
    end
  end

  # -- what the package calls a walk, and what a caller calls progress ---------

  defp new_walk(opened), do: Walk.new(part: opened.part, recognition: opened.recognition)

  # What a caller holds, from the walk's own account of what it did. One owner:
  # the package answers this map, and a copy here would be a second answer.
  defp progress(walk), do: Walk.state_dict(walk)

  defp resume(progress, opened) when is_map(progress) do
    walk = new_walk(opened)

    with {:ok, target} <- target(Map.get(progress, :target), walk.targets) do
      {:ok,
       %{
         walk
         | target: target,
           visited: Map.get(progress, :visited, []),
           walked: Map.get(progress, :walked, 0)
       }}
    end
  end

  defp resume(other, _opened), do: {:error, not_a_progress(other)}

  defp target(nil, _targets), do: {:ok, nil}

  defp target(id, targets) do
    case Enum.find(targets, &(&1.id == id)) do
      nil -> {:error, "this part has no feature #{inspect(id)} to walk to"}
      target -> {:ok, target}
    end
  end

  defp not_a_progress(policy) do
    "this policy's progress is what `{:new, []}` answered — a map with a part, a " <>
      "target and the steps taken — and #{inspect(policy)} is not one"
  end

  # -- the part --------------------------------------------------------------

  defp open_part do
    with {:ok, path} <- Inputs.part_path(),
         {:ok, scene} <- open_scene(path),
         {:ok, recognition} <- features(scene.part) do
      {:ok, %{part: scene.part, recognition: recognition}}
    end
  end

  defp features(part) do
    case Quiddity.features(part) do
      {:ok, recognition} ->
        {:ok, recognition}

      {:error, error} ->
        {:error, "the part's features could not be read: #{Exception.message(error)}"}
    end
  end

  defp open_scene(path) do
    case MontyCad.Scene.open(path) do
      {:ok, scene} -> {:ok, scene}
      {:error, error} -> {:error, "#{path} could not be opened: #{Exception.message(error)}"}
    end
  end
end
