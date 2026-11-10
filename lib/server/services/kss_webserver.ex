defmodule KSS.Webserver do
  @moduledoc """
  """
  alias KSS.ChannelsMaster
  import KSS.Utils

  use KSS.HTTPServer

  @config Application.compile_env(:kss, :local_config, [])
  @external_interpreters @config[:external_interpreters] || []

  ###################################################################################
  # Index HTML
  ###################################################################################
  get "/" do
    index_file = File.read!("priv/layout/index.html")

    main_html =
      opts
      |> Keyword.fetch!(:root_dir)
      |> Kernel.<>(@config[:main_file])
      |> File.read!()
      # |> expand_html()

    bindings =
      opts
      |> Keyword.merge([main: main_html])
      |> Keyword.merge(@config)

    # TODO: manage errors in evaluation
    html = Code.eval_string("\"\"\"\n#{index_file}\n\"\"\"", bindings) |> elem(0)

    Logger.log(:notice, "[KSS][HTTP] Main index loaded")

    conn
    |> assign(:init_options, opts)
    |> put_resp_content_type("text/html")
    |> send_resp(200, html)
  end

  ###################################################################################
  # KSS Client JS and fixed content
  ###################################################################################
  get "/kss.js" do
    kss_js = File.read!("priv/layout/js/kss.js")
    conn
    |> assign(:init_options, opts)
    |> put_resp_content_type("text/javascript")
    |> send_resp(200, kss_js)
  end

  get "/dproxy.js" do
    dproxy_js = File.read!("priv/layout/js/dproxy.js")
    conn
    |> assign(:init_options, opts)
    |> put_resp_content_type("text/javascript")
    |> send_resp(200, dproxy_js)
  end

  get "/favicon.ico" do
    icon =
      case Keyword.get(@config, :favicon) do
        nil ->
          "data:image/x-icon;base64,iVBORw0KGgoAAAANSUhEUgAAABAAAAAQEAYAAABPYyMiAAAABmJLR0T" <>
            "///////8JWPfcAAAACXBIWXMAAABIAAAASABGyWs+AAAAF0lE" <>
            "QVRIx2NgGAWjYBSMglEwCkbBSAcACBAAAeaR9cIAAAAASUVORK5CYII="
        file_name ->
          Application.get_env(:kss, :http)[:root_dir]
          |> Kernel.<>("/#{file_name}")
          |> File.read!()
      end
    conn
    |> put_resp_content_type("image/x-icon")
    |> send_resp(200, icon)
  end

  ###################################################################################
  # Custom JSs and CSSs
  ###################################################################################
  get "/@" <> file_name do
    try do
      content =
        Application.get_env(:kss, :http)[:root_dir]
        |> Kernel.<>("/#{file_name}")
        |> File.read!()

      type = Path.extname(file_name) == ".js" && "javascript" || "css"
      conn
      |> assign(:init_options, opts)
      |> put_resp_content_type("text/#{type}")
      |> send_resp(200, content)
    rescue
      _ ->
        conn
        |> Map.put(:request_path, file_name)
        |> call(opts)
    end
  end

  ###################################################################################
  # Custom Interpreters
  ###################################################################################

  for %{
        name: name,
        real_dir: real_dir,
        virtual_dir: virtual_dir,
        extension: extension,
        module: module,
        function: function
      } <- @external_interpreters do

    IO.write "Building #{name} interpreter... "
    
    get "/#{unquote(virtual_dir)}/" <> script_path do
      filename = "#{unquote(real_dir)}/" <> script_path
      cond do
        not File.exists?(filename) ->
          conn
          |> put_resp_content_type("text/plain")
          |> IO.inspect
          |> send_resp(404, "404 Not Found!\n")
          
        Path.extname(filename) == unquote(extension) ->
          get =
            conn
            |> Plug.Conn.fetch_query_params()
            |> Map.get(:query_params)
            |> Map.to_list()

          cookies =
            conn
            |> Plug.Conn.fetch_cookies()
            |> Map.get(:cookies)
            |> Map.to_list()

          run_interpreter(
            conn,
            unquote(module),
            unquote(function),
            [filename, get, [], cookies, conn.req_headers]
          )
          
        true -> 
          type = Path.extname(filename) == ".js" && "javascript" || "css"
          conn
          |> put_resp_content_type("text/#{type}")
          |> send_resp(200, File.read!(filename))
          
      end
    end

    post "/#{unquote(virtual_dir)}/" <> script_path do
      filename = "#{unquote(real_dir)}/" <> script_path
      cond do
        not File.exists?(filename) ->
          conn
          |> put_resp_content_type("text/plain")
          |> IO.inspect
          |> send_resp(404, "404 Not Found!\n")
          
        Path.extname(filename) == unquote(extension) ->
          get =
            conn
            |> Plug.Conn.fetch_query_params()
            |> Map.get(:query_params)
            |> Map.to_list()

          cookies =
            conn
            |> Plug.Conn.fetch_cookies()
            |> Map.get(:cookies)
            |> Map.to_list()

          post =
            conn
            |> read_body()
            |> elem(1)
            |> Plug.Conn.Query.decode()
            |> Map.to_list()

          run_interpreter(
            conn,
            unquote(module),
            unquote(function),
            [filename, get, post, cookies, conn.req_headers]
          )
          
        true -> 
          type = Path.extname(filename) == ".js" && "javascript" || "css"
          conn
          |> put_resp_content_type("text/#{type}")
          |> send_resp(200, File.read!(filename))
          
      end
    end
    
    IO.puts "ready!"
    
  end
  
  ###################################################################################
  # EventSource loop
  ###################################################################################
  get "/eventsource" do
    Logger.log(:notice, "[KSS][EventSource] Connection open")
    conn
    |> put_resp_header("X-Accel-Buffering", "no")
    |> put_resp_header("Content-Type", "text/event-stream")
    |> put_resp_header("Cache-Control", "no-cache")
    |> send_chunked(200)
    |> KSS.EventSource.loop()
    Logger.log(:notice, "[KSS][EventSource] Connection closed")
  end

  ###################################################################################
  # API REST
  ###################################################################################

  post "/push/channel:" <> channel do
    Logger.log(:notice, "[KSS][API] Push request from API - Event to channel '#{channel}'")
    check_authorize_user(conn)
    {json, conn} = check_json_body(conn)

    # if conn do not pass the checks, the request never reach the code below
    Logger.log(:notice, "[KSS][API] Pushing event to channel '#{channel}'")
    event = string_keys_to_atom(json)
    channel |> String.to_atom() |> ChannelsMaster.push_event(event)
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, "{\"result_ok\": true}\n")
  end

  get "/list/channels" do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, JSON.encode!(ChannelsMaster.list_channels()))
  end

  ###################################################################################
  # Private tools
  ###################################################################################

  defp check_authorize_user(conn) do
    auth =
      conn.req_headers
      |> Enum.into(%{})
      |> Map.get("authorization")
    user_pass = @config[:api_user_pass]

    with {1, "Basic " <> b64} <- {1, auth},
         {2, ^user_pass} <- {2, Base.decode64!(b64)} do
      conn
    else
      {1, _} ->
        conn
        |> send_resp(401, "Error: No authorization sent!\n")
      _ ->
        conn
        |> send_resp(403, "Error: bad user/pass!\n")
    end
  end

  defp check_json_body(conn) do
    {:ok, body, conn} = read_body(conn)
    body =
      case body do
        "q=" <> _ -> body |> URI.decode_query(%{}, :www_form) |> Map.get("q")
        _ -> body
      end

    case JSON.decode(body) do
      {:ok, json} ->
        {json, conn}
      _ ->
        conn
        |> send_resp(400, "Malformed json request!\n")
    end
  end

  def run_interpreter(conn, module, function, params) do
    module
    |> apply(function, params)
    |> case do
      {:ok, body, headers} ->
        headers 
        |> Enum.reduce(conn, fn h, cn ->
          [k | v] = String.split(h, ":")
          put_resp_header(cn, k, Enum.join(v, ":"))
        end)
        |> send_resp(200, body)

      {:error, msg} ->
        conn
        |> put_resp_content_type("text/plain")
        |> send_resp(500, "500 - #{msg}\n")
    end
  end 
end
