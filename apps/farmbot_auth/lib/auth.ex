defmodule Farmbot.Auth do
  @moduledoc """
    Gets a token and device information
  """
  @modules Application.get_env(:farmbot_auth, :callbacks) ++ [Farmbot.Auth]
  @path Application.get_env(:farmbot_filesystem, :path)

  use GenServer
  require Logger
  alias Farmbot.FileSystem.ConfigStorage, as: CS
  alias Farmbot.Token

  @doc """
    Gets the public key from the API
  """
  def get_public_key(server) do
    case HTTPotion.get("#{server}/api/public_key") do
      %HTTPotion.ErrorResponse{message: message} ->
        {:error, message}
      %HTTPotion.Response{body: body, headers: _headers, status_code: 200} ->
        {:ok, RSA.decode_key(body)}
    end
  end

  @doc """
    Returns the list of callback modules.
  """
  def modules, do: @modules

  @doc """
    Encrypts the key with the email, pass, and server
  """
  def encrypt(email, pass, pub_key) do
    f = Poison.encode!(%{"email": email,
                         "password": pass,
                         "id": Nerves.Lib.UUID.generate,
                         "version": 1})
    |> RSA.encrypt({:public, pub_key})
    |> String.Chars.to_string
    {:ok, f}
  end

  @doc """
    Get a token from the server with given token
  """
  @spec get_token_from_server(binary, String.t) :: {:ok, Token.t} | {:error, atom}
  def get_token_from_server(secret, server) do
    # I am not sure why this is done this way other than it works.
    payload = Poison.encode!(%{user: %{credentials: :base64.encode_to_string(secret) |> String.Chars.to_string }} )
    case HTTPotion.post "#{server}/api/tokens", [body: payload, headers: ["Content-Type": "application/json"]] do
      # Any other http error.
      %HTTPotion.ErrorResponse{message: reason} -> {:error, reason}
      # bad Password
      %HTTPotion.Response{body: _, headers: _, status_code: 422} -> {:error, :bad_password}
      # Token invalid. Need to try to get a new token here.
      %HTTPotion.Response{body: _, headers: _, status_code: 401} -> {:error, :expired_token}
      # We won
      %HTTPotion.Response{body: body, headers: _headers, status_code: 200} ->
        # save the secret to disk.
        Farmbot.FileSystem.transaction fn() ->
          :ok = File.write(@path <> "/secret", :erlang.term_to_binary(secret))
        end
        Poison.decode!(body) |> Map.get("token") |> Token.create
    end
  end

  @doc """
    Gets the token.
    Will return a token if one exists, nil if not.
    Returns {:error, reason} otherwise
  """
  def get_token do
    GenServer.call(__MODULE__, :get_token)
  end

  @doc """
    Gets teh server
    will return either {:ok, server} or {:ok, nil}
  """
  @spec get_server :: {:ok, nil} | {:ok, String.t}
  def get_server, do: GenServer.call(CS, {:get, Authorization, :server})

  @spec put_server(String.t | nil) :: no_return
  defp put_server(server) when is_nil(server) or is_binary(server),
    do: GenServer.cast(CS, {:put, Authorization, {:server, server}})

  @doc """
    Tries to log into web services with whatever auth method is stored in state.
  """
  @spec try_log_in :: {:ok, Token.t} | {:error, atom}
  def try_log_in do
    case GenServer.call(__MODULE__, :try_log_in) do
      {:ok, %Token{} = token} ->
        do_callbacks(token)
      error ->
        Logger.error ">> Could not log in! #{inspect error}"
    end
  end
  @doc """
    Casts credentials to the Auth GenServer
  """
  @spec interim(String.t, String.t, String.t) :: no_return
  def interim(email, pass, server) do
    GenServer.cast(__MODULE__, {:interim, {email,pass,server}})
  end

  @doc """
    Reads the secret file from disk
  """
  @spec get_secret :: {:ok, nil | binary}
  def get_secret do
    case File.read(@path <> "/secret") do
      {:ok, sec} -> {:ok, :erlang.binary_to_term(sec)}
      _ -> {:ok, nil}
    end
  end

  @doc """
    Application entry point
  """
  def start(_type, args) do
    Logger.debug(">> Starting Authorization services")
    start_link(args)
  end

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__ )
  end

  # Genserver stuff
  def init(_args), do: get_secret

  # casted creds, store them until something is ready to actually try a log in.
  def handle_cast({:interim, {email, pass, server}},_) do
    Logger.debug ">> Got some new credentials."
    put_server(server)
    {:noreply, {email,pass,server}}
  end

  def handle_call(:try_log_in, _, {email, pass, server}) do
    Logger.debug ">> is trying to log in with credentials."
    with {:ok, pub_key} <- get_public_key(server),
         {:ok, secret } <- encrypt(email, pass, pub_key),
         {:ok, %Token{} = token} <- get_token_from_server(secret, server)
    do
      {:reply, {:ok, token}, token}
    else
      e ->
        Logger.error ">> error getting token #{inspect e}"
        put_server(nil)
        {:reply, e, nil}
    end
  end

  def handle_call(:try_log_in, _, secret) when is_binary(secret) do
    Logger.debug ">> is trying to log in with a secret."
    with {:ok, server} <- get_server,
         {:ok, %Token{} = token} <- get_token_from_server(secret, server)
    do
      {:reply, {:ok, token}, token}
    else
      e ->
        Logger.error ">> error getting token #{inspect e}"
        put_server(nil)
        {:reply, e, nil}
    end
  end

  def handle_call(:try_log_in, _, %Token{} = _token) do
    Logger.warn ">> already has a token. Fetching another."
    with {:ok, server} <- get_server,
         {:ok, secret} <- get_secret,
         {:ok, %Token{} = token} <- get_token_from_server(secret, server)
    do
      {:reply, {:ok, token}, token}
    else
      e ->
        Logger.error ">> error getting token #{inspect e}"
        put_server(nil)
        {:reply, e, nil}
    end
  end

  def handle_call(:try_log_in, _, nil) do
    Logger.error ">> can't log in because i have no token or credentials!"
    {:reply, {:error, :no_token}, nil}
  end


  # if we do have a token.
  def handle_call(:get_token, _from, %Token{} = token) do
    {:reply, {:ok, token}, token}
  end

  # if we dont.
  def handle_call(:get_token, _, not_token) do
    {:reply, nil, not_token}
  end

  # when we get a token.
  def handle_info({:authorization, token}, _) do
    {:noreply, token}
  end

  def terminate(:normal, state) do
    Logger.debug("AUTH DIED: #{inspect state}")
  end

  def terminate(reason, state) do
    Logger.error("AUTH DIED: #{inspect {reason, state}}")
  end

  defp do_callbacks(token) do
    spawn(fn ->
      Enum.all?(@modules, fn(module) ->
        send(module, {:authorization, token})
      end)
    end)
  end
end
