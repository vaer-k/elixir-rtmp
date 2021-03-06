defmodule VideoChat.RTMP.Connection do
  @moduledoc """
  RTMP client connection
  """
  use GenServer
  alias VideoChat.RTMP.Connection
  alias VideoChat.RTMP.Handshake

  @state %{
    server_timestamp: nil,
    time: nil
  }

  def start_link(server, socket, opts) do
    GenServer.start_link(__MODULE__, {server, socket}, opts)
  end

  def init({server, socket}) do
    GenServer.cast(self(), {:accept, socket})

    {:ok, Enum.into(%{server: server, socket: socket}, @state)}
  end

  def init(_opts), do: {:error, :invalid_options}

  @doc """
  Async calls to accept connections

  """
  def handle_cast({:accept, socket}, state) do
    case :gen_tcp.accept(socket, 120_000) do
      {:ok, client} -> register_client(client, state)
      {:error, :timeout} -> start_another(state)
    end

    {:noreply, state}
  end

  @doc """
  External calls
  """
  def handle_info({:tcp, from, _ip, _port, message}, state) do
    IO.inspect("[Connection] TCP message")
    IO.inspect(from)

    {:noreply, state}
  end

  def handle_info({:tcp, from, message}, state) do
    case message do
      <<0x03>> ->
        {:noreply, Handshake.send_s0(from, state)}

      <<0x03, time::bytes-size(4), 0, 0, 0, 0, rand::bytes-size(1528)>> ->
        Handshake.send_s0(from, state)
        {:noreply, Handshake.send_s1(from, {time, rand}, state)}

      <<_server_timestamp::bytes-size(4), _time::bytes-size(4), _rand::bytes-size(1528)>> ->
        {:noreply, Handshake.send_s2(from, state)}

      _ ->
        IO.inspect("[Connection] AMF message")
        IO.inspect(byte_size(message))
        IO.inspect(message)

        {:noreply, state}
    end
  end

  def handle_info({:tcp_closed, from}, state) do
    IO.inspect("[Connection] Closed")

    GenServer.cast(state.server, {:unregister_client, from})
    GenServer.stop(self(), :normal)

    {:noreply, state}
  end

  @doc """
  Register the client with the server
  """
  def register_client(client, state) do
    IO.inspect("[Connection] Registered")
    IO.inspect(client)
    {:ok, _pid} = Connection.start_link(state.server, state.socket, [])
    :ok = GenServer.cast(state.server, {:register_client, client})
  end

  @doc """
  Starts another client

  Thie function will be called after a connection timeout
  """
  def start_another(state) do
    IO.inspect("[Connection] Timeout. Starting another process")
    {:ok, _pid} = Connection.start_link(state.server, state.socket, [])
    GenServer.stop(self(), :normal)
  end
end
