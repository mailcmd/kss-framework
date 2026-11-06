defmodule KSS.Job.Dummy do
  use KSS.Job, log_name: "DummyJob", start_supervised: false
  alias Utils.DLog, as: Log
  
  @config Application.compile_env(:kss, :dummy_job, [])

  @impl true
  def start do
    Log.log(:notice, "[#{@log_name}] Initializing Job")
    KSS.ChannelsMaster.add_channel(:the_time)
    %Job{
      id: __MODULE__ ,
      every: 0,
      timeout: @config[:none] || :infinity,
      start_immediately: @config[:start_immediately] || true,
      params: []
    }
  end

  @impl true
  def run(job) do
    Log.log(:notice, "[#{@log_name}] Sending dummy datas...")    
    time = NaiveDateTime.utc_now() |> to_string()    
    KSS.DummyManager.send_to_channel(:the_time, %{action: "upd", sandbox: "main", key: ".time", data: time})
    Process.sleep(1000)
    run(job)
  end

end