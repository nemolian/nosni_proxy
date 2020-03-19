# NosniProxy

Install elixir (>= 1.9) and then run `./entrypoint.sh`.

On the first launch the program will generate two file. `ca.pem` and `ca_key.pem`.

You will need to install `ca.pem` as a root certificate in your system or application (Firefox for example).

After that set https_proxy to `127.0.0.1:8080` and then you will be able to bypass censorship based on SNI sniffing.

## Important

Keep in mind that we do not send the SNI correctly, So the webserver won't send us the correct certificate hence the
validation of server certificate is not possible (easily!). I wouldn't recommend logging in or sending sensitive information with
this approach.

Also some services are censored by their server's IP Address. In this case bypassing SNI won't help.
