defmodule Echo do
  use Application

  @moduledoc """
  Documentation for `Echo`.
  """
  @echo_socket_path "/tmp/echo/echo.sock"
  @feeder_socket_name_regex ~r/feeder-out-(.{8})/

  def start(_type, _args) do
    children = [
      {NodeRouter, %{}},
      {SocketRouter, %{}},
      {Task.Supervisor, name: Echo.TaskSupervisor}
    ]

    {:ok, supervisor} = Supervisor.start_link(children, strategy: :one_for_one)
    # Task.Supervisor.start_child(Echo.TaskSupervisor, &io_loop/0)

    # delete socket file if it already exist (from previous run)
    # if the file already exists then :socket.bind call will error
    if not File.exists?("/tmp/echo/") do
      File.mkdir("/tmp/echo/")
    end
    File.rm(@echo_socket_path)
    {:ok, socket} = :socket.open(:local, :dgram, %{})
    :socket.bind(socket, %{family: :local, path: @echo_socket_path})
    # SocketRouter.set_bound_echo_socket(socket)
    Task.Supervisor.start_child(Echo.TaskSupervisor, fn -> recv_echo_socket_loop(socket) end)

    {:ok, supervisor}
  end

  # defp io_loop() do
  #   input_json = IO.read(:stdio, :line)
  #   message = Jason.decode!(input_json, keys: :atoms)
  #   message_type = message.body.type

  #   if message_type == "init" do
  #     {:ok, pid} = EchoNode.start_link(%{})
  #     GenServer.call(NodeRouter, {:put, message.dest, pid})
  #   end

  #   dispatch_message(
  #     GenServer.call(NodeRouter, {:get, message.dest}),
  #     {String.to_atom(message_type), message}
  #   )

  #   io_loop()
  # end

  defp recv_echo_socket_loop(socket) do
    {source, data} = NodeRouter.recv_from_socket(socket)
    message = Jason.decode!(data, keys: :atoms)
    message_type = message.body.type

    if message_type == "init" do
      # List.last gets the capture from this regex
      socket_name = Regex.run(@feeder_socket_name_regex, source) |> List.last()
      {:ok, pid} = EchoNode.start_link(%{})
      EchoNode.set_bound_echo_socket(pid, socket)
      GenServer.call(pid, {:start_comms, socket_name, "/tmp/echo/feeder-in-#{socket_name}.sock"})
      GenServer.cast(pid, {:init, message})
    end

    recv_echo_socket_loop(socket)
  end

  # defp dispatch_message(node_pid, {:init, message}) do
  #   GenServer.cast(node_pid, {:init, message})
  # end

  # defp dispatch_message(node_pid, {:echo, message}) do
  #   GenServer.cast(node_pid, {:echo, message})
  # end

  # defp dispatch_message(node_pid, {:generate, message}) do
  #   GenServer.cast(node_pid, {:generate, message})
  # end

  # defp dispatch_message(node_pid, {:broadcast, message}) do
  #   GenServer.cast(node_pid, {:broadcast, message})
  # end

  # defp dispatch_message(node_pid, {:read, message}) do
  #   GenServer.cast(node_pid, {:read, message})
  # end

  # defp dispatch_message(node_pid, {:topology, message}) do
  #   GenServer.cast(node_pid, {:topology, message})
  # end

  # defp dispatch_message(node_pid, {:gossip, message}) do
  #   GenServer.cast(node_pid, {:gossip, message})
  # end
end
