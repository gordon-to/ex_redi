defmodule ExRedi.MixProject do
  use Mix.Project

  @github "https://github.com/l1h3r/ex_redi"

  def project do
    [
      app: :ex_redi,
      version: "0.1.0",
      elixir: "~> 1.6",
      name: "ExRedi",
      package: package(),
      description: description(),
      source_url: @github,
      homepage_url: @github,
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      test_coverage: [tool: ExCoveralls]
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {ExRedi, []}
    ]
  end

  defp description do
    ~s(A simple Elixir client for RediSearch)
  end

  defp package do
    [
      files: ["lib", "mix.exs", "README.md", "LICENSE.md"],
      maintainers: ["l1h3r"],
      licenses: ["MIT"],
      links: %{"Github" => @github}
    ]
  end

  defp deps do
    [
      {:redix, "~> 0.7.0"},
      {:ex_doc, "~> 0.18.3", only: :dev},
      {:credo, "~> 0.9.0", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 0.5.1", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.8.1", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases do
    [
      lint: ["dialyzer", "credo", "test"]
    ]
  end
end
