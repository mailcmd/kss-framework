defmodule KSS.Job.GlobalStorage do
  @moduledoc """
  App garbage storage
  """

  use Agent

  def start_link(_) do
    Agent.start_link(fn -> %{jobs: []} end, name: __MODULE__)
  end

  def add_job(module) do
    if not (get_jobs() |> Enum.member?(module)) do
      Agent.update(__MODULE__, fn %{jobs: jobs} -> %{jobs: [module | jobs]} end)
    end
  end

  def remove_job(module) do
    Agent.update(__MODULE__, fn %{jobs: jobs} -> %{jobs: List.delete(jobs, module)} end)
  end

  def get_jobs() do
    Agent.get(__MODULE__, fn %{jobs: jobs} -> jobs end)
  end
end
