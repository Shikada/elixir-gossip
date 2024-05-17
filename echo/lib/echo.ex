defmodule Echo do
  use Application

  @moduledoc """
  Documentation for `Echo`.
  """

  def start(_type, _args) do
    children = [
      {NodeMapper, %{}},
      {Task.Supervisor, name: Echo.TaskSupervisor}
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
    Task.Supervisor.start_child(Echo.TaskSupervisor, &io_loop/0)
  end

  defp io_loop() do
    input_json = IO.read(:stdio, :line)
    message = Jason.decode!(input_json, keys: :atoms)
    message_type = message.body.type

    if message_type == "init" do
      {:ok, pid} = EchoNode.start_link(%{})
      GenServer.call(NodeMapper, {:put, message.dest, pid})
    end

    dispatch_message(
      GenServer.call(NodeMapper, {:get, message.dest}),
      {String.to_atom(message_type), message}
    )

    io_loop()
  end

  defp dispatch_message(node_pid, {:init, message}) do
    GenServer.cast(node_pid, {:init, message})
  end

  defp dispatch_message(node_pid, {:echo, message}) do
    GenServer.cast(node_pid, {:echo, message})
  end

  defp dispatch_message(node_pid, {:generate, message}) do
    GenServer.cast(node_pid, {:generate, message})
  end

  defp dispatch_message(node_pid, {:broadcast, message}) do
    GenServer.cast(node_pid, {:broadcast, message})
  end

  defp dispatch_message(node_pid, {:read, message}) do
    GenServer.cast(node_pid, {:read, message})
  end

  defp dispatch_message(node_pid, {:topology, message}) do
    GenServer.cast(node_pid, {:topology, message})
  end

  defp dispatch_message(node_pid, {:gossip, message}) do
    GenServer.cast(node_pid, {:gossip, message})
  end
end
