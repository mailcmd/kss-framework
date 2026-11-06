defmodule KSS.MixProject do
  use Mix.Project

  def project do
    [
      app: :kss,
      version: "0.1.0",
      elixir: "~> 1.20",
      compilers: Mix.compilers(),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :inets, :ssl],
      mod: {KSS.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:plug_cowboy, "~> 2.9.0"},
      # {:php_ex, git: "https://github.com/mailcmd/php_ex.git"}
      # Specific for the app below
    ]
  end
  
  defp aliases() do
    [
      # "deps.get": ["deps.get", "update_cordjs"],
      setup: ["cmd scripts/install.sh"],
      update_kssjs: ["cmd scripts/update_kssjs.sh"],
    ]
  end
end
