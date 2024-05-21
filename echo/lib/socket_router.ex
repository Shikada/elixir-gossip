defmodule SocketRouter do
  use GenServer

  def start_link(_state) do
    GenServer.start_link(__MODULE__, %{}, name: SocketRouter)
  end

  def set_bound_echo_socket(socket) do
    GenServer.call(SocketRouter, {:set_socket, socket})
  end

  def send_feeder_socket(dest_node_id, message) do
    GenServer.cast(SocketRouter, {:send, dest_node_id, message})
  end

  def get_feeder_socket(dest_node_id) do
    GenServer.call(SocketRouter, {:get_feeder_socket, dest_node_id})
  end

  @impl true
  def init(state) do
    {:ok, state}
  end

  @impl true
  def handle_call({:set_socket, socket}, _from, state) do
    {:reply, :ok, Map.put(state, :echo_socket, socket)}
  end

  @impl true
  def handle_call(:get_socket, _from, state) do
    {:reply, state.echo_socket, state}
  end

  @impl true
  def handle_call({:put, node_id, feeder_socket}, _from, state) do
    {:reply, :ok, Map.put(state, node_id, feeder_socket)}
  end

  @impl true
  def handle_call({:get_feeder_socket, dest_node_id}, _from, state) do
    {:reply, Map.get(state, dest_node_id), state}
  end

  @impl true
  def handle_cast({:send, dest_node_id, message}, state) do
    feeder_socket_path = Map.get(state, dest_node_id)

    :socket.sendto(
      state.echo_socket,
      message,
      %{family: :local, path: feeder_socket_path}
    )

    {:noreply, state}
  end
end
