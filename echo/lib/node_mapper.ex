defmodule NodeMapper do
  use GenServer

  def start_link(_state) do
    GenServer.start_link(__MODULE__, %{}, name: NodeMapper)
  end

  @impl true
  def init(state) do
    {:ok, state}
  end

  @impl true
  def handle_call({:put, node_id, pid}, _from, state) do
    {:reply, :ok, Map.put(state, node_id, pid)}
  end

  @impl true
  def handle_call({:get, node_id}, _from, state) do
    {:reply, Map.get(state, node_id), state}
  end
end
