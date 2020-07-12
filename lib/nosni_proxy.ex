defmodule NosniProxy do
  @moduledoc """
  Proxy module
  """

  import NosniProxy.Utils

  require Logger

  # Timeout of 20 minutes per connection
  @socket_timeout 20 * 60 * 1000
  @host_extractor_regex ~r/^[A-Z]+ http:\/\/([A-Za-z.]+):?([0-9]+)?/

  def child_spec(opts) do
    %{id: __MODULE__, start: {__MODULE__, :start_link, [opts]}}
  end

  def start_link(port: port) do
    ca = load_ca()
    {:ok, socket} = :gen_tcp.listen(port, [:binary, active: false, packet: :raw, reuseaddr: true])

    File.mkdir("cache")

    Logger.info("Accepting connections on port #{port}")

    {:ok, spawn_link(__MODULE__, :accept, [socket, ca])}
  end

  @doc """
  Accepts a socket, initiate TLS in case of tls then proxy request.
  """
  def accept(socket, ca) do
    {:ok, request} = :gen_tcp.accept(socket)

    pid =
      spawn(fn ->
        with {:ok, :ssl, host, port} <- read_http_target(request),
             host_ip <- secure_arecord_resolve!(host),
             {:ok, cert, key} <- get_or_create_cert(ca, host),
             {:remote_connect, {:ok, remote}} <-
               {:remote_connect, connect_ssl_remote(host_ip, port)},
             {:verify_cert, :ok} <- {:verify_cert, verify_cert(host, remote)},
             :ok <- :gen_tcp.send(request, "HTTP/1.1 200\r\n\r\n"),
             {:user_handshake, {:ok, request_ssl}} <-
               {:user_handshake,
                :ssl.handshake(request,
                  cert: cert,
                  key: {:ECPrivateKey, key},
                  versions: [:"tlsv1.2", :"tlsv1.1", :tlsv1]
                )} do
          Logger.debug("Connection succeeded #{host}:#{port}")

          tasks =
            Task.yield_many(
              [
                Task.async(fn -> ssl_stream(remote, request_ssl) end),
                Task.async(fn -> ssl_stream(request_ssl, remote) end)
              ],
              @socket_timeout
            )

          Enum.map(tasks, fn {task, _res} ->
            Task.shutdown(task, :brutal_kill)
          end)

          Logger.debug("Stream finished!")
        else
          {:ok, :http, data} ->
            process_http(request, data)

          {:verify_cert, error} ->
            Logger.error("cert verify error: #{error}")

          error ->
            Logger.error("error: #{inspect(error)}")
        end
      end)

    :gen_tcp.controlling_process(request, pid)

    accept(socket, ca)
  end

  @doc """
  Process a plain text http request.
  """
  def process_http(request, data) do
    {:ok, host, port} = get_http_host_and_port(data)

    host_ip = secure_arecord_resolve!(host)

    remote = Socket.TCP.connect!(host_ip, port)

    :ok = :gen_tcp.send(remote, data)

    tasks =
      Task.yield_many(
        [
          Task.async(fn -> stream(remote, request) end),
          Task.async(fn -> stream(request, remote) end)
        ],
        @socket_timeout
      )

    Enum.map(tasks, fn {task, _res} ->
      Task.shutdown(task, :brutal_kill)
    end)

    Logger.debug("HTTP finished!")
  end

  defp get_http_host_and_port(data) do
    case Regex.run(@host_extractor_regex, data) do
      [_, host, port] ->
        {:ok, host, String.to_integer(port)}

      [_, host] ->
        {:ok, host, 80}

      nil ->
        Logger.error("Bad http data: #{inspect(data)}")
        :error
    end
  end
end
