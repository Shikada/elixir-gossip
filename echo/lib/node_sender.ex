defmodule NodeSender do
  use GenServer

  def start_link(state) do
    GenServer.start_link(__MODULE__, state)
  end

  @impl true
  def init(state) do
    {:ok, state}
  end

  @impl true
  def handle_cast({:send, message}, state) do
    :socket.sendto(
      state.socket,
      message,
      %{family: :local, path: state.feeder_socket}
    )

    {:noreply, state}
  end
end
