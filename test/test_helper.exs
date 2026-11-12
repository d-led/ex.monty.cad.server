# A peer node needs a distributed VM, and `mix test` does not start one. The two
# cluster tests that start a second node are tagged `:distributed`, so a plain run
# excludes them rather than failing on a capability the VM does not have; CI runs
# them separately, in a VM that was started with a name.
distributed? =
  case :net_kernel.start([:"ex_monty_cad_test@127.0.0.1", :longnames]) do
    {:ok, _pid} -> true
    {:error, {:already_started, _pid}} -> true
    {:error, _reason} -> false
  end

unless distributed? do
  IO.puts("not distributed: the cluster tests that start a second node are excluded")
end

ExUnit.start(exclude: if(distributed?, do: [], else: [:distributed]))
