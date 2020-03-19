defmodule NosniProxy.MixProject do
  use Mix.Project

  def project do
    [
      app: :nosni_proxy,
      version: "0.1.0",
      elixir: "~> 1.9",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {NosniProxy.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:httpoison, "~> 1.5"},
      {:jason, "~> 1.1"},
      {:socket, "~> 0.3"},
      {:x509, "~> 0.7"}
    ]
  end
end
