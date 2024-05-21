defmodule NodeRouter do
  use GenServer

  def start_link(_state) do
    GenServer.start_link(__MODULE__, %{}, name: NodeRouter)
  end

  def set_bound_echo_socket(socket) do
    GenServer.call(NodeRouter, {:set_socket, socket})
  end

  def get_echo_socket() do
    GenServer.call(NodeRouter, :get_socket)
  end

  def recv_from_socket(socket) do
    {address, data} = case :socket.recvfrom(socket) do
      {:ok, {source, data}} -> {source, :erlang.iolist_to_binary(data)}
      {:error, reason} -> IO.puts "SHIT: #{reason}"
    end

    {address.path, data}
  end

  def send_feeder_socket(dest_node_id, message) do
    GenServer.cast(NodeRouter, {:send_socket, dest_node_id, message})
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
  def handle_call({:put, node_id, {pid, feeder_socket}}, _from, state) do
    {:reply, :ok, Map.put(state, node_id, {pid, feeder_socket})}
  end

  @impl true
  def handle_call({:get_pid, node_id}, _from, state) do
    {pid, _feeder_socket} = Map.get(state, node_id)
    {:reply, pid, state}
  end

  @impl true
  def handle_call({:get_feeder_socket_path, node_id}, _from, state) do
    {_pid, feeder_socket_path} = Map.get(state, node_id)
    {:reply, feeder_socket_path, state}
  end

  @impl true
  def handle_cast({:send_socket, dest_node_id, message}, state) do
    {_pid, feeder_socket_path} = Map.get(state, dest_node_id)

    :socket.sendto(
      state.echo_socket,
      message,
      %{family: :local, path: feeder_socket_path}
    )

    {:noreply, state}
  end
end
