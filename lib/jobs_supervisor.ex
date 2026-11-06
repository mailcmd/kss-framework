defmodule KSS.Job.Supervisor do
  use Supervisor
  
  @config Application.compile_env(:kss, :jobs_supervisor)

  def start_link(_) do
    Supervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_) do
    children = @config[:children] || []

    Supervisor.init(children, strategy: :one_for_one)
  end

end
