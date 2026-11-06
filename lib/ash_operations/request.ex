defmodule AshOperations.Request do
  @moduledoc """
  Builds a transport request for a declared operation from the action's
  arguments: path placeholders filled (each value exactly one encoded path
  segment), query parameters under their provider names, and a JSON or
  multipart body.
  """

  alias AshOperations.{Operation, Param, Transport}

  @spec build(Operation.t(), map()) :: {:ok, Transport.request()} | {:error, String.t()}
  def build(%Operation{} = operation, arguments) do
    with {:ok, path} <- fill_path(operation, arguments),
         {:ok, body} <- body(operation, arguments) do
      {:ok,
       %{method: operation.method, path: path, query: query(operation, arguments), body: body}}
    end
  end

  defp fill_path(%Operation{path: path} = operation, arguments) do
    by_name = Map.new(operation.params, &{Atom.to_string(&1.name), &1})

    Operation.placeholder_regex()
    |> Regex.split(path, include_captures: true)
    |> Enum.reduce_while({:ok, []}, fn segment, {:ok, acc} ->
      case fill_segment(segment, by_name, arguments) do
        {:ok, part} -> {:cont, {:ok, [part | acc]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, parts} -> {:ok, parts |> Enum.reverse() |> Enum.join()}
      error -> error
    end
  end

  defp fill_segment(segment, by_name, arguments) do
    with [name] <- Regex.run(Operation.placeholder_regex(), segment, capture: :all_but_first),
         :error <- path_segment(Map.get(arguments, by_name[name].name)) do
      {:error, "invalid value for path param #{name}"}
    else
      nil -> {:ok, segment}
      {:ok, encoded} -> {:ok, encoded}
    end
  end

  # One value is exactly one segment: `/` is encoded and dot segments refused,
  # so an argument can never walk the request to another endpoint.
  defp path_segment(value) when is_binary(value) and value not in ["", ".", ".."],
    do: {:ok, URI.encode(value, &URI.char_unreserved?/1)}

  defp path_segment(value) when is_integer(value), do: {:ok, Integer.to_string(value)}
  defp path_segment(_), do: :error

  defp query(%Operation{params: params}, arguments) do
    for %Param{in: :query} = param <- params,
        item <- present(arguments, param) do
      {Param.wire_name(param), scalar(item)}
    end
  end

  defp present(arguments, %Param{name: name}) do
    case Map.get(arguments, name) do
      nil -> []
      value -> List.wrap(value)
    end
  end

  defp body(%Operation{request: :none}, _arguments), do: {:ok, nil}

  defp body(%Operation{request: :json, params: params}, arguments) do
    {:ok,
     {:json,
      for %Param{in: :body} = p <- params, not is_nil(Map.get(arguments, p.name)), into: %{} do
        {Param.wire_name(p), json_value(Map.get(arguments, p.name))}
      end}}
  end

  defp body(%Operation{request: :multipart, params: params}, arguments) do
    params
    |> Enum.filter(&(&1.in == :part and not is_nil(Map.get(arguments, &1.name))))
    |> Enum.reduce_while({:ok, []}, fn p, {:ok, acc} ->
      case part(Map.get(arguments, p.name)) do
        {:ok, value} -> {:cont, {:ok, [{Param.wire_name(p), value} | acc]}}
        :error -> {:halt, {:error, "invalid value for multipart part #{p.name}"}}
      end
    end)
    |> case do
      {:ok, parts} -> {:ok, {:multipart, Enum.reverse(parts)}}
      error -> error
    end
  end

  defp part(value) when is_binary(value), do: {:ok, value}

  defp part(%{content: content, filename: filename} = file)
       when is_binary(content) and is_binary(filename) do
    {:ok,
     {content,
      filename: filename, content_type: Map.get(file, :content_type, "application/octet-stream")}}
  end

  defp part(%{"content" => content, "filename" => filename} = file),
    do: part(%{content: content, filename: filename, content_type: file["content_type"]})

  defp part(_), do: :error

  defp scalar(value) when is_binary(value), do: value
  defp scalar(value) when is_boolean(value), do: to_string(value)
  defp scalar(value) when is_atom(value), do: Atom.to_string(value)
  defp scalar(value) when is_integer(value), do: Integer.to_string(value)
  defp scalar(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp scalar(%Date{} = value), do: Date.to_iso8601(value)
  defp scalar(%Decimal{} = value), do: Decimal.to_string(value, :normal)
  defp scalar(value), do: to_string(value)

  defp json_value(value) when is_boolean(value) or is_nil(value), do: value
  defp json_value(value) when is_atom(value), do: Atom.to_string(value)
  defp json_value(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp json_value(%Date{} = value), do: Date.to_iso8601(value)
  # Jason would write a Decimal as a string; providers expect a number. A raw
  # fragment keeps every digit (no float on the way out).
  defp json_value(%Decimal{} = value), do: Jason.Fragment.new(Decimal.to_string(value, :normal))
  defp json_value(value) when is_list(value), do: Enum.map(value, &json_value/1)

  defp json_value(value) when is_map(value) and not is_struct(value),
    do: Map.new(value, fn {k, v} -> {to_string(k), json_value(v)} end)

  defp json_value(value), do: value
end
