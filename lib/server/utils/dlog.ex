defmodule Utils.DLog do
  @levels %{
    emergency: 1,
    alert: 2,
    critical: 3,
    error: 4,
    warning: 5,
    notice: 6,
    info: 7,
    debug: 8
  }

  @colors %{
    emergency: IO.ANSI.light_red()<>IO.ANSI.white_background(),
    alert: IO.ANSI.light_red()<>IO.ANSI.white_background(),
    critical: IO.ANSI.light_red()<>IO.ANSI.white_background(),
    error: IO.ANSI.light_red(),
    warning: IO.ANSI.light_yellow(),
    notice: IO.ANSI.light_green(),
    info: IO.ANSI.default_color(),
    debug: IO.ANSI.light_blue()
  }

  def init(options \\ []) do
    level = Keyword.get(options, :level, :notice)
    console = Keyword.get(options, :console, true)
    path = Keyword.get(options, :path, "/tmp/dlog.log")
    # gmt = Keyword.get(options, :gmt, -10800)
    mode = Keyword.get(options, :mode, :append)


    :ets.new(:direct_log, [
      :ordered_set,
      :public,
      :named_table,
      read_concurrency: true,
      write_concurrency: true
    ])
    :ets.insert(:direct_log, {:level, level})
    :ets.insert(:direct_log, {:filename, path})
    :ets.insert(:direct_log, {:console, console})
    :ets.insert(:direct_log, {:mode, mode})
    # :ets.insert(:direct_log, {:gmt, gmt})

    {:ok, file} = File.open(path, [mode])
    :ets.insert(:direct_log, {:file, file})
  end

  def reopen() do
    [{_, filename}] = :ets.lookup(:direct_log, :filename)
    set_path(filename)
  end

  def set_level(level) do
    :ets.insert(:direct_log, {:level, level})
  end

  def set_path(filename) do
    [{_, file}] = :ets.lookup(:direct_log, :file)
    [{_, mode}] = :ets.lookup(:direct_log, :mode)
    File.close(file)
    {:ok, file} = File.open(filename, [mode])
    :ets.insert(:direct_log, {:file, file})
    :ets.insert(:direct_log, {:filename, filename})
    file
  end

  def console(console), do: :ets.insert(:direct_log, {:console, console})

  # def log(lvl, text), do: :ok
  def log(lvl, text) do
    [{_, level}] = :ets.lookup(:direct_log, :level)
    [{_, console}] = :ets.lookup(:direct_log, :console)
    if @levels[level] - @levels[lvl] >= 0 do
      # [{_, gmt}] = :ets.lookup(:direct_log, :gmt)
      [{_, file}] = :ets.lookup(:direct_log, :file)
      message = "#{NaiveDateTime.local_now()} - [#{lvl}] #{text}"
      try do 
        IO.puts(file, message)
      rescue
        _ ->
          file = reopen()
          IO.puts(file, message)
      end
      if console, do: IO.puts(@colors[lvl]<>message<>IO.ANSI.reset())
    end
  end
end
