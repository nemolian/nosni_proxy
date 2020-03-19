defmodule NosniProxy.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  def start(_type, _args) do
    port = read_integer_env("PROXY_PORT") || 8080

    children = [
      # Starts a worker by calling: NosniProxy.Worker.start_link(arg)
      # {NosniProxy.Worker, arg}
      {NosniProxy, port: port}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: NosniProxy.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp read_integer_env(env) do
    case System.get_env(env) do
      nil ->
        nil

      val ->
        {int, ""} = Integer.parse(val)
        int
    end
  end
end
