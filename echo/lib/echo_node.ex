defmodule EchoNode do
  require Logger
  use GenServer

  def start_link(state) do
    GenServer.start_link(__MODULE__, state)
  end

  def set_bound_echo_socket(pid, socket) do
    GenServer.call(pid, {:set_socket, socket})
  end

  defp create_message_reply(state, message, reply_msg_type, extra_body_values) do
    message_id = state.current_message_id

    base_body_values = %{
      type: reply_msg_type,
      in_reply_to: message.body.msg_id
    }

    reply_message = %{
      src: state.node_id,
      dest: message.src,
      body: Map.merge(base_body_values, extra_body_values)
    }

    new_state = Map.put(state, :current_message_id, message_id + 1)

    {new_state, reply_message}
  end

  defp create_message_to_node(state, dst_node, msg_type, extra_body_values) do
    message_id = state.current_message_id

    base_body_values = %{
      type: msg_type
    }

    message = %{
      src: state.node_id,
      dest: dst_node,
      body: Map.merge(base_body_values, extra_body_values)
    }

    new_state = Map.put(state, :current_message_id, message_id + 1)

    {new_state, message}
  end

  defp send_message(json_message) do
    GenServer.cast(self(), {:send, json_message})
  end

  @impl true
  def init(state) do
    Logger.add_handlers(:echo)
    Logger.info("Started da node")
    new_state = Map.put(state, :current_message_id, 0)
    new_state = Map.put(new_state, :values, MapSet.new())

    {:ok, new_state}
  end

  @impl true
  def handle_call({:set_socket, socket}, _from, state) do
    {:reply, :ok, Map.put(state, :echo_socket, socket)}
  end

  @impl true
  def handle_call({:put, node_id, {pid, feeder_socket}}, _from, state) do
    {:reply, :ok, Map.put(state, node_id, {pid, feeder_socket})}
  end

  @impl true
  def handle_call({:start_comms, socket_name, feeder_socket}, _from, state) do
    {:ok, socket} = :socket.open(:local, :dgram, %{})
    :socket.bind(socket, %{family: :local, path: "/tmp/echo/node-#{socket_name}.sock"})
    new_state = Map.put(state, :socket, socket) |> Map.put(:feeder_socket, feeder_socket)
    self = self()
    Task.Supervisor.start_child(Echo.TaskSupervisor, fn -> receive_loop(self, socket) end)

    {:reply, :ok, new_state}
  end

  @impl true
  def handle_cast({:init, message}, state) do
    node_id = message.body.node_id
    Logger.info("Got info message with id #{node_id}")
    new_state = Map.put(state, :node_id, node_id)

    response = %{
      src: node_id,
      dest: message.src,
      body: %{
        type: "init_ok",
        in_reply_to: message.body.msg_id
      }
    }

    send_message(Jason.encode!(response))

    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:echo, message}, state) do
    response = %{
      src: state.node_id,
      dest: message.src,
      body: %{
        type: "echo_ok",
        msg_id: message.body.msg_id,
        in_reply_to: message.body.msg_id,
        echo: message.body.echo
      }
    }

    send_message(Jason.encode!(response))

    {:noreply, state}
  end

  @impl true
  def handle_cast({:generate, message}, state) do
    response = %{
      src: state.node_id,
      dest: message.src,
      body: %{
        type: "generate_ok",
        msg_id: message.body.msg_id,
        in_reply_to: message.body.msg_id,
        id: UUID.uuid4()
      }
    }

    send_message(Jason.encode!(response))

    {:noreply, state}
  end

  @impl true
  def handle_cast({:broadcast, message}, state) do
    try do
      new_value = message.body.message

      new_state =
        if MapSet.member?(state.values, new_value) do
          state
        else
          Map.put(state, :values, MapSet.put(state.values, new_value))
        end

      {new_state, response} = create_message_reply(new_state, message, :broadcast_ok, %{})
      send_message(Jason.encode!(response))

      {:noreply, new_state}
    rescue
      e ->
        Logger.error(Exception.format(:error, e, __STACKTRACE__))
        reraise e, __STACKTRACE__
    end
  end

  @impl true
  def handle_cast({:read, message}, state) do
    try do
      {new_state, response} =
        create_message_reply(state, message, :read_ok, %{messages: MapSet.to_list(state.values)})

        send_message(Jason.encode!(response))

      {:noreply, new_state}
    rescue
      e ->
        Logger.error(Exception.format(:error, e, __STACKTRACE__))
        reraise e, __STACKTRACE__
    end
  end

  @impl true
  def handle_cast({:topology, message}, state) do
    try do
      # get neigbours for this node
      new_state =
        Map.put(state, :neighbours, Map.get(message.body.topology, String.to_atom(state.node_id)))

      # initialize gossip cache for each neigbour node to a new Map of empty MapSet(s)
      new_state =
        Map.put(
          new_state,
          :gossip_cache,
          Enum.reduce(new_state.neighbours, %{}, fn node_id, acc ->
            Map.put(acc, node_id, MapSet.new())
          end)
        )

      self = self()
      # start gossip loop that will perform periodic gossip to neighbours in the background
      Task.Supervisor.start_child(Echo.TaskSupervisor, fn -> gossip_loop(self) end)

      {new_state, response} = create_message_reply(new_state, message, :topology_ok, %{})
      send_message(Jason.encode!(response))

      {:noreply, new_state}
    rescue
      e ->
        Logger.error(Exception.format(:error, e, __STACKTRACE__))
        reraise e, __STACKTRACE__
    end
  end

  @impl true
  def handle_cast({:send, message}, state) do
    Logger.info "gonna send from #{inspect(state.socket)}"
    :socket.sendto(
      state.socket,
      message,
      %{family: :local, path: state.feeder_socket}
    )
    Logger.info "sent to #{state.feeder_socket}"

    {:noreply, state}
  end

  @impl true
  def handle_cast(:do_gossip, state) do
    try do
      # check if state of Node is ready to gossip
      neighbours = Map.get(state, :neighbours)
      has_gossip_cache = Map.get(state, :gossip_cache)

      # gossip to every neighbour. State is updated with each gossip, so reduce the final new state after all gossiping
      if neighbours && has_gossip_cache do
        new_state =
          Enum.reduce(neighbours, state, fn node_id, _acc ->
            gossip_to_node(state, node_id, state)
          end)

        {:noreply, new_state}
      else
        {:noreply, state}
      end
    rescue
      e ->
        Logger.error(Exception.format(:error, e, __STACKTRACE__))
        reraise e, __STACKTRACE__
    end
  end

  @impl true
  def handle_cast({:gossip, message}, state) do
    try do
      # if gossip_cache is not in state, this node is not ready for gossip message yet
      new_values_set = MapSet.new(message.body.values)

      unless Map.get(state, :gossip_cache) do
        {:noreply, state}
      else
        # update values of this node
        new_state = Map.put(state, :values, MapSet.union(state.values, new_values_set))

        # update values that this node knows about the node that sent this gossip message
        new_state = %{
          new_state
          | :gossip_cache =>
              Map.put(
                new_state.gossip_cache,
                message.src,
                MapSet.union(Map.get(new_state.gossip_cache, message.src), new_values_set)
              )
        }

        # Logger.info(
        #   "Node #{new_state.node_id} just handled a gossip from node #{message.src}.\nValues received: #{inspect(new_values_set)}\n" <>
        #     "Current gossip cache: #{inspect(new_state.gossip_cache)}"
        # )

        {:noreply, new_state}
      end
    rescue
      e ->
        Logger.error(Exception.format(:error, e, __STACKTRACE__))
        reraise e, __STACKTRACE__
    end
  end

  defp gossip_to_node(state, dst_node, state) do
    try do
      # only gossip values that we are not sure the destination node knows about
      gossip_values = MapSet.difference(state.values, Map.get(state.gossip_cache, dst_node))

      # Logger.info(
      # "Node #{state.node_id} about to gossip to node #{dst_node}.\nValues being sent: #{inspect(gossip_values)}\n" <>
      #       "Current gossip cache: #{inspect(state.gossip_cache)}"
      # )

      if not Enum.empty?(gossip_values) do
        {new_state, message} =
          create_message_to_node(state, dst_node, :gossip, %{
            values: MapSet.to_list(gossip_values)
          })

        send_message(Jason.encode!(message))

        new_state
      else
        state
      end
    rescue
      e ->
        Logger.error(Exception.format(:error, e, __STACKTRACE__))
        reraise e, __STACKTRACE__
    end
  end

  defp receive_loop(pid, socket) do
    {:ok, data} = :socket.recv(socket)
    Logger.info "Got something from node socket"
    message = Jason.decode!(data, keys: :atoms)
    message_type = message.body.type
    GenServer.cast(pid, {String.to_atom(message_type), message})

    receive_loop(pid, socket)
  end

  defp gossip_loop(pid) do
    GenServer.cast(pid, :do_gossip)
    Process.sleep(100)
    gossip_loop(pid)
  end
end
