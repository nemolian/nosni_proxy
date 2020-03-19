defmodule NosniProxy.Utils do
  @moduledoc """
  Utils for socket, TLS and DNS
  """

  require Logger

  @doc """
  Resolves a DNS A record securely.
  """
  def secure_arecord_resolve!(host) do
    cache = Application.get_env(:elixir_http_proxy, :resolve_cache, %{})

    case cache[host] do
      nil ->
        dns = resolve_dns!(host)
        Application.put_env(:elixir_http_proxy, :resolve_cache, Map.put(cache, host, dns))
        dns

      dns ->
        Logger.debug("Cached #{host}")
        dns
    end
  end

  def verify_cert(_host, _socket) do
    # {:ok, der} = Socket.SSL.certificate(socket)
    # {:ok, cert} = X509.Certificate.from_der(der)

    # TODO: Implement verification

    :ok
  end

  @doc """
  Loads the existing or creates a new CA authority.
  """
  def load_ca(path \\ "", name \\ "ca") do
    if File.exists?(Path.join(path, "#{name}.pem")) do
      Logger.info("CA cert will load from disk...")

      {:ca, pem_file!(Path.join(path, "#{name}.pem"), :cert),
       pem_file!(Path.join(path, "#{name}_key.pem"), :key)}
    else
      Logger.warn("CA cert not found on disk, Creating a new one...")
      ca_key = X509.PrivateKey.new_ec(:secp256r1)

      ca =
        X509.Certificate.self_signed(
          ca_key,
          "/C=US/ST=CA/L=San Francisco/O=Acme/CN=ECDSA Root CA",
          template: :root_ca
        )

      File.write!(Path.join(path, "#{name}.pem"), X509.Certificate.to_pem(ca))
      File.write!(Path.join(path, "#{name}_key.pem"), X509.PrivateKey.to_pem(ca_key))
      {:ca, ca, ca_key}
    end
  end

  @doc """
  Read a pem encoded certificate.
  """
  def pem_file!(filename, :cert) do
    filename
    |> File.read!()
    |> X509.Certificate.from_pem!()
  end

  @doc """
  Read a pem encoded key.
  """
  def pem_file!(filename, :key) do
    filename
    |> File.read!()
    |> X509.PrivateKey.from_pem!()
  end

  @doc """
  Returns an existing certificate or creates a new one with given subject.
  """
  def get_or_create_cert({:ca, ca, ca_key}, subject) do
    if File.exists?("cache/#{subject}.der") do
      Logger.debug("Loading cert from disk #{subject}")
      {:ok, File.read!("cache/#{subject}.der"), File.read!("cache/#{subject}_key.der")}
    else
      Logger.debug("Creating new cert for #{subject}")
      key = X509.PrivateKey.new_ec(:secp256r1)

      cert =
        key
        |> X509.PublicKey.derive()
        |> X509.Certificate.new("/C=US/ST=CA/L=San Francisco/O=Acme/CN=Sample", ca, ca_key,
          extensions: [subject_alt_name: X509.Certificate.Extension.subject_alt_name([subject])]
        )

      key_der = X509.PrivateKey.to_der(key)
      cert_der = X509.Certificate.to_der(cert)

      File.write!("cache/#{subject}.der", cert_der)
      File.write!("cache/#{subject}_key.der", key_der)

      Logger.info("Spoofed cert for #{subject}")

      {:ok, cert_der, key_der}
    end
  end

  @doc """
  Stream data from src socket to dst socket.
  """
  def stream(dst, src) do
    data = Socket.Stream.recv!(src)

    if not is_nil(data) do
      Socket.Stream.send!(dst, data)

      stream(dst, src)
    end
  end

  @doc """
  Stream SSL data from src to dst.
  """
  def ssl_stream(dst, src) do
    data =
      case src do
        {:sslsocket, _, _} ->
          Socket.Stream.recv!(src)

        _ ->
          {:ok, data} = :ssl.recv(src, 0, 5000)
          data
      end

    if not is_nil(data) do
      case dst do
        {:sslsocket, _, _} ->
          Socket.Stream.send!(dst, data)

        _ ->
          :ok = :ssl.send(dst, data)
      end

      ssl_stream(dst, src)
    end
  end

  @doc """
  Read HTTP Target.
  """
  def read_http_target(request) do
    case :gen_tcp.recv(request, 0) do
      {:ok, <<"CONNECT ", rest::binary>>} ->
        [target | _] = String.split(rest, " ")
        [host, port] = String.split(target, ":")
        {:ok, :ssl, host, String.to_integer(port)}

      {:ok, http_data} ->
        {:ok, :http, http_data}
    end
  end

  ###
  # Helpers
  ###

  defp resolve_dns!(host) do
    case HTTPoison.get("https://cloudflare-dns.com/dns-query?name=#{host}&type=A",
           accept: "application/dns-json"
         ) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        host_ip = Jason.decode!(body)["Answer"] |> List.last() |> Map.fetch!("data")
        Logger.debug("RESOLVER #{host} => #{host_ip}")
        host_ip

      error ->
        raise "Name not resolved #{inspect(error)}"
    end
  end
end
