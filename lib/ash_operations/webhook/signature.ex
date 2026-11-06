defmodule AshOperations.Webhook.Signature do
  @moduledoc """
  Pure helpers for verifying an HMAC-SHA256 webhook signature. Comparison is
  constant-time and visits every candidate secret.
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
