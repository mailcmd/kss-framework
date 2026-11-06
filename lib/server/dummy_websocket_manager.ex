defmodule KSS.DummyManager do
  use KSS.Websocket.Manager
  alias Utils.DLog, as: Log
  alias KSS.ChannelsMaster  

  ################################################################################################
  # Callbacks 
  ################################################################################################
  @impl true
  def process_connection(conn, :open) do
    peer_id = conn[:qs]
    pids =
      (recover(:current_connections) || [])
      |> Enum.filter(&(Process.alive?(&1)))
    store(:current_connections, [conn.pid | pids])
    store({:peer, peer_id}, conn.pid)
  end
  def process_connection(conn, :closed) do
    peer_id = conn[:qs]
    pids =
      recover(:current_connections)
      |> Kernel.||([])
      |> List.delete(conn.pid)

    store(:current_connections, pids)
    erase({:peer, peer_id})
    peer_id
      |> ChannelsMaster.get_client_channels()
      |> Enum.each(fn channel ->
        ChannelsMaster.unsubscribe(peer_id, channel)
      end)
  end
  
  @impl true
  def process_events(_), do: :ok

  ################################################################################################
  # Callbacks for messages
  ################################################################################################
  @impl true
  def process_message(%{"action" => "subscribe"} = msg, state) do
    peer_id = state.conn[:qs];
    case ChannelsMaster.subscribe(peer_id, String.to_atom(msg["channel"])) do
      :ok ->
        msg
        |> put_in(["result_ok"], true)
        |> put_in(["subs"], ChannelsMaster.get_client_channels(peer_id))

      _ ->
        msg
        |> put_in(["result_ok"], false)
        |> put_in(["subs"], ChannelsMaster.get_client_channels(peer_id))
      end

    reply(state, msg)
  end

  def process_message(%{"action" => "unsubscribe"} = msg, state) do
    peer_id = state.conn[:qs];
    case ChannelsMaster.unsubscribe(peer_id, String.to_atom(msg["channel"])) do
      :ok ->
        msg
        |> put_in(["result_ok"], true)
        |> put_in(["subs"], ChannelsMaster.get_client_channels(peer_id))

      _ ->
        msg
        |> put_in(["result_ok"], false)
        |> put_in(["subs"], ChannelsMaster.get_client_channels(peer_id))
      end

    reply(state, msg)
  end

  def process_message(msg, state) do
    Log.log(:warning, "[KSS][Websocket][Processor] Unknwon message #{inspect msg}")
    reply(state, msg)
  end

  ################################################################################################
  ## API
  ################################################################################################
  
  def send_to_channel(channel, event) do
    event =
      event
      |> put_in([:channel], channel)
      |> put_in([:ts], System.os_time(:second))

    channel 
    |> get_channel_clients()
    |> send_event(event)
  end  

  ################################################################################################
  ## Private Tools
  ################################################################################################

  defp store(key, value) do
    :persistent_term.put({:kss, key}, value)
    :ok
  end

  defp recover(key) do
    :persistent_term.get({:kss, key}, nil)
  end

  defp erase(key) do
    :persistent_term.erase({:kss, key})
  end
  
  defp get_channel_clients(:broadcast), do: recover(:current_connections) || []
  defp get_channel_clients(channel) do
    channel
    |> ChannelsMaster.get_channel_clients()
    |> Enum.map(fn peer_id -> recover({:peer, peer_id}) end)
    |> Enum.filter(&(&1!=nil))
    |> Enum.filter(&Process.alive?/1)
  end

  defp send_event([], _), do: :ok
  defp send_event([pid | pids], event) do
    Logger.log(:debug,
               "[SSB][Websocket][Processor] Sending to #{inspect pid} #{inspect event}")
    send(pid, JSON.encode!(event))
    send_event(pids, event)
  end
end
