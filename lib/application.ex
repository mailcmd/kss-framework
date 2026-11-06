defmodule KSS.Application do
  @moduledoc false

  use Application
  require Logger
  alias Utils.DLog, as: Log
  
  @config Application.compile_env!(:kss, :http)
  @local_config Application.compile_env(:kss, :local_config, [])

  @impl true
  def start(_type, _args) do
    Application.get_env(:kss, :dlog, []) |> Log.init()
    Logger.configure(level: Application.get_env(:logger, :level))

    port = Keyword.get(@local_config, :port, Keyword.fetch!(@config, :port))
    sport = Keyword.get(@local_config, :https_port, Keyword.fetch!(@config, :https_port))

    http_server =
      if is_list(port) do
        Enum.map(port, &cowboy_child(&1))
      else
        [ cowboy_child(port) ]
      end

    # sorry for this :'(
    https_server =
      if @local_config[:https] do
        if is_list(sport) do
          Enum.map(sport, &cowboy_child(&1, :https))
        else
          [ cowboy_child(sport, :https) ]
        end
      else
        []
      end

    children = http_server ++ https_server ++ [
      # Channels manager
      {KSS.ChannelsMaster, [:broadcast]},
      # Events manager
      {KSS.EventsMaster,
        {
          Keyword.get(@local_config, :events_pop_interval),
          Keyword.get(@local_config, :websocket_manager)
        }
      },
      # Permanent Storage
      {KSS.PermanentStorage, []},
      # Jobs Supervisor
      KSS.Job.GlobalStorage,
      KSS.Job.Supervisor
    ]
    # User defined APP
    ++ (@local_config[:app_supervisor] && [@local_config[:app_supervisor]] || [])

    opts = [strategy: :one_for_one, name: KSS.Supervisor]

    Logger.log(:notice,
               "[KSS] Starting KSS services in ports "<>
               "#{inspect port} #{inspect (@local_config[:https] && sport || "")}..."
    )
    Supervisor.start_link(children, opts)
  end

  defp dispatcher do
    [
      {:_,
       [
         {
           "/websocket", KSS.Websocket, [
             websocket_manager: Keyword.get(@local_config, :websocket_manager)
           ]
         },
         {:_, Plug.Cowboy.Handler, {KSS.Webserver, @config}},
       ]
      }
    ]
  end

  defp cowboy_child(port, scheme \\ :http)
  defp cowboy_child(port, :http) do
    Supervisor.child_spec(
      {
        Plug.Cowboy,
        scheme: :http,
        plug: {KSS.Webserver, @config},
        options: [
          port: port,
          ref: {:ranch_listener, "http_#{port}"},
          dispatch: dispatcher()
        ]
      },
      id: {:cowboy, port}
    )
  end

  defp cowboy_child({port, keyfile, certfile}, :https) do
    Supervisor.child_spec(
      {
        Plug.Cowboy,
        scheme: :https,
        plug: {KSS.Webserver, @config},
        options: [
          port: port,
          ref: {:ranch_listener, "https_#{port}"},
          dispatch: dispatcher(),
          keyfile: keyfile,
          certfile: certfile,
          otp_app: :secure_app
        ]
      },
      id: {:cowboy, port}
    )
  end

  defp cowboy_child(port, :https) do
    Supervisor.child_spec(
      {
        Plug.Cowboy,
        scheme: :https,
        plug: {KSS.Webserver, @config},
        options: [
          port: port,
          ref: {:ranch_listener, "https_#{port}"},
          dispatch: dispatcher(),
          keyfile: Keyword.get(@local_config, :keyfile),
          certfile: Keyword.get(@local_config, :certfile),
          otp_app: :secure_app
        ]
      },
      id: {:cowboy, port}
    )
  end
  
end
