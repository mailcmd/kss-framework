defmodule KSS.Job do
  @moduledoc """
  Define Job behaviour. Implementers need define `start/0`, `run/1` and optionally `refresh/1`
  callbacks.

  Public API:
    - start_link(opts)
    - stop()
    - update()
    - status()
    - update_concurrency(value)
    - status(:percent)
    - set_total(count)
    - job_stats_set_total(count)
    - job_stats_increment_partial(count \\ 1)
    - job_stats_increment_fails(count \\ 1)
    - job_stats_increment_skips(count \\ 1)
    - job_stats_reset()
      
    - [x] Add to %Job{} :start_inmediately flag.
    - [ ] Run manually the job (I must cancel next_run_timer)
    - [ ] Log any meaning event

  HOW TO USE:

  defmodule ... do
    use KSS.Job, [
      log_name: "<string>",    ## OPTIONAL, default module name
      start_supervised: <bool> ## OPTIONAL, default false
    ]
  end
  
  """

  alias Utils.DLog, as: Log

  @enforce_keys [:id, :every, :params]
  defstruct [
    :id,
    :every,            # in miliseconds
    :params,
    start_immediately: false,
    timeout: :infinity,
    
    status: :stopped,  # :stopped | :running | :waiting
    concurrency_usage: 0,
    job_pid: nil,
    current_task: nil,
    start_time: 0,
    next_run_timer: nil,
    timeout_timer: nil,
    last_result: nil,
    last_run: 0,
    last_runtime: 0,
    total: 0,
    partial: 0,
    fails: 0,
    skips: 0,
    stats_data: nil
  ]

  ###############################################################################################
  ## Callbacks
  ###############################################################################################
  @callback start() :: %KSS.Job{}
  @callback run(job :: %KSS.Job{}) :: term()
  @callback refresh(current_job :: %KSS.Job{}) :: %KSS.Job{} | {:error, term()}
  @callback children() :: list()
  @optional_callbacks [refresh: 1, children: 0]

  defmacro __using__(config \\ []) do
    quote do
      use GenServer, restart: :transient
      @behaviour unquote(__MODULE__)
      import unquote(__MODULE__)
      alias unquote(__MODULE__)

      @log_name Keyword.get(unquote(config), :log_name, to_string(__MODULE__))

      #########################################################################################
      ## Public API
      #########################################################################################
      def start_link(opts \\ []) do
        if Keyword.get(opts, :start_supervised, unquote(config)[:start_supervised]) do
          start_supervised(opts)
        else
          if not Keyword.get(opts, :hidden, false), do: unquote(__MODULE__).register_job(__MODULE__)
          GenServer.start_link(__MODULE__, [], name: __MODULE__)
        end
      end
      
      def start_supervised(sup_opts \\ []) do
        opts = [
          strategy: Keyword.get(sup_opts, :strategy, :one_for_one),
          name: __MODULE__.Supervisor
        ]
        children = children() ++ [{__MODULE__, start_supervised: false}]
        Supervisor.start_link(children, opts)
      end

      def stop(reason \\ :normal) do
        GenServer.stop(__MODULE__, reason)
      end

      def update() do
        GenServer.cast(__MODULE__, :update)
      end

      def run_now() do
        Process.send(__MODULE__, :start_job, [])
      end

      def status() do
        :sys.get_state(__MODULE__)
      end
      def status(:percent) do
        job = :sys.get_state(__MODULE__)
        100 * job.partial / job.total
      end

      def update_concurrency(value \\ 1) do
        GenServer.cast(__MODULE__, {:update_concurrency, value})
      end

      # Utils to set stats and inform progress
      def job_stats_set_total(count) do
        GenServer.cast(__MODULE__, {:stats_total_set, count})
      end
      def job_stats_increment_partial(count \\ 1) do
        GenServer.cast(__MODULE__, {:stats_progress_add, count})
      end
      def job_stats_increment_fails(count \\ 1) do
        GenServer.cast(__MODULE__, {:stats_fails_add, count})
      end
      def job_stats_increment_skips(count \\ 1) do
        GenServer.cast(__MODULE__, {:stats_skips_add, count})
      end
      def job_stats_reset() do
        GenServer.cast(__MODULE__, :stats_reset)
      end
      
      #########################################################################################
      ## GenServer callbacks
      #########################################################################################
      @impl true
      def init(_) do
        job = %Job{timeout: timeout, every: every} = start()
        if is_integer(timeout) and timeout >= every do
          {:error, "Timeout cannot be greater or equal than every!"}
        else
          {:ok, assign(job, :job_pid, self()), {:continue, {:schedule_next_run, 0}}}
        end
      end

      @impl true
      def terminate(reason, job) do
        unquote(__MODULE__).unregister_job(__MODULE__)
        {_, job} = handle_info({:abort, :stop}, job)
        {:ok, job}
      end

      # Default implementation of refresh do nothing
      @impl unquote(__MODULE__)
      def refresh(current_job), do: current_job
      defoverridable refresh: 1

      # Default implementation of children do nothing
      @impl unquote(__MODULE__)
      def children(), do: []
      defoverridable children: 0

      # The `start_immediately` parameter just count the first time, when the Job start with
      # start_link.
      # If `start_immediately` is true the job run at startup time, if not wait an `every`
      # period to run the job
      @impl true
      def handle_continue({:schedule_next_run, offset}, %Job{start_immediately: false} = job) do
        timer = Process.send_after(self(), :start_job, job.every + offset, [])
        job
        |> assign(:next_run_timer, timer)
        |> assign(:status, :waiting)
        |> noreply()
      end
      def handle_continue({:schedule_next_run, offset}, job) do
        handle_info(:start_job, assign(job, :start_immediately, false))
      end

      @impl true
      def handle_cast(:update, current_job) do
        noreply(
          case refresh(current_job) do
            %KSS.Job{} = new_job ->
              new_job
            _ ->
              current_job
          end
        )
      end

      def handle_cast({:update_concurrency, value}, job) do
        job
        |> assign(:concurrency_usage, job.concurrency_usage + value)
        |> noreply()
      end

      # stats
      def handle_cast({:stats_total_set, count}, job) do
        job
        |> assign(:total, count)
        |> noreply()
      end
      def handle_cast({:stats_progress_add, count}, job) do
        job
        |> assign(:partial, job.partial + count)
        |> noreply()
      end
      def handle_cast({:stats_fails_add, count}, job) do
        job
        |> assign(:fails, job.fails + count)
        |> noreply()
      end
      def handle_cast({:stats_skips_add, count}, job) do
        job
        |> assign(:skips, job.skips + count)
        |> noreply()
      end
      def handle_cast(:stats_reset, job) do
        job
        |> assign(:total, 0)
        |> assign(:partial, 0)
        |> assign(:fails, 0)
        |> assign(:skips, 0)
        |> assign(:stats_data, nil)
        |> noreply()
      end
      
      @impl true
      def handle_info(:start_job,  %Job{status: :running} = job) do
        noreply(job)
      end
      def handle_info(:start_job, job) do
        parent_id = self()
        start_time = System.monotonic_time()
	      # run job...
        task = Task.async(fn ->
          result = run(job)
          Process.send(parent_id, :completed_job, [])
          result
        end)

        # If set timeout take care that the job do not excede timeout
        Process.cancel_timer(job.timeout_timer || make_ref())
        timeout_timer =
          if is_integer(job.timeout) do
            Process.send_after(self(), {:abort, :timeout}, job.timeout)
          else
            nil
          end
        
        job
        |> assign(:status, :running)
        |> assign(:current_task, task)
        |> assign(:start_time, start_time)
        |> assign(:timeout_timer, timeout_timer)
        |> assign(:last_runtime, 0)
        |> assign(:last_run, System.os_time(:second))
        |> noreply()
      end
      
      def handle_info(:completed_job, job) do
        # wait one seconde to asure task is over
        Process.sleep(1_000)
        result = Task.yield(job.current_task)
        time_taken =
          System.monotonic_time()
          |> Kernel.-(job.start_time)
          |> System.convert_time_unit(:native, :millisecond)

        # If set timeout cancel abort message
        if is_reference(job.timeout_timer) do
          Process.cancel_timer(job.timeout_timer)
        end
        
        job
        |> assign(:status, :waiting)
        |> assign(:current_task, nil)
        |> assign(:timeout_timer, nil)
        |> assign(:start_time, 0)
        |> assign(:last_runtime, time_taken)
        |> assign(:last_result, result)
        |> noreply(:continue)
      end

      def handle_info({:abort, :timeout}, %{status: :running} = job) do
        Log.log(:warning, "[JOB] Job aborted by timeout")
        job
        |> abort({:aborted, :timeout})
        |> noreply(:continue)
      end
      def handle_info({:abort, :stop}, %{status: :running} = job) do
        Log.log(:warning, "[JOB] Job aborted by stop command")
        job
        |> abort({:aborted, :stop})
        |> noreply()
      end
      def handle_info({:abort, _}, job) do
        noreply(job)
      end
    end
  end

  ###############################################################################################
  ## Tools imported inside behaviour implementers
  ###############################################################################################
  def noreply(job, mode \\ nil)
  def noreply(job, :continue) do
    {:noreply, job, {:continue, {:schedule_next_run, -job.last_runtime}}}
  end
  def noreply(job, nil) do
    {:noreply, job}
  end
  
  def assign(%__MODULE__{} = job, key, value) do
    Map.put(job, key, value)
  end

  def abort(job, reason) do
    Task.shutdown(job.current_task, :brutal_kill)
        
    # If set timeout cancel abort message
    if is_reference(job.timeout_timer) do
      Process.cancel_timer(job.timeout_timer)
    end

    job
    |> assign(:status, :waiting)
    |> assign(:current_task, nil)
    |> assign(:timeout_timer, nil)
    |> assign(:start_time, 0)
    |> assign(:last_runtime, job.timeout)
    |> assign(:last_result, reason)
  end
  
  ###############################################################################################
  ## Private tools
  ###############################################################################################
  def register_job(module) do
    KSS.Job.GlobalStorage.add_job(module)
  end
  def unregister_job(module) do
    KSS.Job.GlobalStorage.remove_job(module)
  end
end
