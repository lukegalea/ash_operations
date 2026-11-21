defmodule AshOperations.Webhook.Signature do
  @moduledoc """
  Pure helpers for verifying a webhook signature: an HMAC-SHA256 under a shared
  secret, or an ECDSA signature under a provider's public key. HMAC comparison
  is constant-time, and both visit every candidate secret or key.
  """

  @doc "Lowercase hex HMAC-SHA256 of `message` under `secret`."
  @spec hmac_sha256_hex(binary(), iodata()) :: String.t()
  def hmac_sha256_hex(secret, message) do
    :hmac |> :crypto.mac(:sha256, secret, message) |> Base.encode16(case: :lower)
  end

  @doc """
  True when `given` (64 hex characters, either case) is the MAC of `message`
  under any one of `secrets`. No early exit; false for no secrets.
  """
  @spec valid_hex?(String.t(), [binary()], iodata()) :: boolean()
  def valid_hex?(given, secrets, message) when is_binary(given) and is_list(secrets) do
    if secrets != [] and given =~ ~r/\A[0-9a-fA-F]{64}\z/ do
      given = String.downcase(given)

      Enum.reduce(secrets, false, fn secret, acc ->
        Plug.Crypto.secure_compare(given, hmac_sha256_hex(secret, message)) or acc
      end)
    else
      false
    end
  end

  def valid_hex?(_given, _secrets, _message), do: false

  @doc """
  True when `signature` (base64 of a DER-encoded ECDSA signature) is a valid
  ECDSA signature over SHA-256 of `message` under any one of `public_keys`.

  Each key is an elliptic-curve public key as base64 DER SubjectPublicKeyInfo
  (the form a provider dashboard usually shows) or as PEM. Every key is tried,
  with no early exit, so which key matched does not show in the timing. A
  malformed signature or key, or a key that is not an EC key, never matches and
  never raises. False for no keys.
  """
  @spec valid_ecdsa_sha256?(String.t(), [String.t()], iodata()) :: boolean()
  def valid_ecdsa_sha256?(signature, public_keys, message)
      when is_binary(signature) and is_list(public_keys) do
    with true <- public_keys != [],
         {:ok, der_signature} <- Base.decode64(String.trim(signature)) do
      message = IO.iodata_to_binary(message)

      Enum.reduce(public_keys, false, fn key, acc ->
        ecdsa_verifies?(message, der_signature, key) or acc
      end)
    else
      _ -> false
    end
  end

  def valid_ecdsa_sha256?(_signature, _public_keys, _message), do: false

  defp ecdsa_verifies?(message, der_signature, key) do
    case ec_public_key(key) do
      {:ok, ec_key} -> :public_key.verify(message, :sha256, der_signature, ec_key)
      :error -> false
    end
  rescue
    _ -> false
  catch
    _, _ -> false
  end

  defp ec_public_key(key) when is_binary(key) do
    with {:ok, der} <- spki_der(key),
         {{:ECPoint, _}, {:namedCurve, _}} = ec_key <-
           :public_key.pem_entry_decode({:SubjectPublicKeyInfo, der, :not_encrypted}) do
      {:ok, ec_key}
    else
      _ -> :error
    end
  end

  defp ec_public_key(_key), do: :error

  defp spki_der(key) do
    if String.contains?(key, "-----BEGIN") do
      case :public_key.pem_decode(key) do
        [{:SubjectPublicKeyInfo, der, :not_encrypted}] -> {:ok, der}
        _ -> :error
      end
    else
      Base.decode64(String.trim(key))
    end
  end

  @doc "True when `ts` (1 to 12 digits, seconds) is within `tolerance_s` of `now_s`, either way."
  @spec fresh?(String.t(), integer(), pos_integer()) :: boolean()
  def fresh?(ts, now_s, tolerance_s) when is_binary(ts) do
    with true <- ts =~ ~r/\A[0-9]{1,12}\z/,
         {n, ""} <- Integer.parse(ts) do
      abs(now_s - n) <= tolerance_s
    else
      _ -> false
    end
  end

  def fresh?(_ts, _now_s, _tolerance_s), do: false

  @doc "The one non-empty value of a request header."
  @spec single_header(Plug.Conn.t(), String.t()) :: {:ok, String.t()} | :error
  def single_header(conn, name) do
    case Plug.Conn.get_req_header(conn, name) do
      [value] when value != "" -> {:ok, value}
      _ -> :error
    end
  end
end
