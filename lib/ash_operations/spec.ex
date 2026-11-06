defmodule AshOperations.Spec do
  @moduledoc """
  A vendored OpenAPI 3.x JSON document, read at compile time.

  The file is pinned by sha-256 rather than by its `info.version`: providers
  often leave that at a placeholder, and the sha is what proves the bytes the
  declarations were checked against are the bytes in the repository.
  """

  alias AshOperations.Operation

  @methods ~w(get post put patch delete)

  @type t :: %{sha256: String.t(), endpoints: MapSet.t({atom(), String.t()})}

  @doc "Read and index a spec file. Paths are relative to the current directory (the project root)."
  @spec load(String.t()) :: {:ok, t()} | {:error, String.t()}
  def load(path) do
    with {:ok, bytes} <- read(path),
         {:ok, doc} <- decode(path, bytes) do
      {:ok, %{sha256: sha256(bytes), endpoints: endpoints(doc)}}
    end
  end

  @doc "Lowercase hex sha-256 of some bytes."
  def sha256(bytes), do: :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)

  @doc "Whether the spec publishes `method` on a path of this shape."
  def endpoint?(%{endpoints: endpoints}, method, path),
    do: MapSet.member?(endpoints, {method, Operation.path_shape(path)})

  defp read(path) do
    case File.read(path) do
      {:ok, bytes} -> {:ok, bytes}
      {:error, reason} -> {:error, "cannot read spec #{path}: #{:file.format_error(reason)}"}
    end
  end

  defp decode(path, bytes) do
    case Jason.decode(bytes) do
      {:ok, %{"paths" => paths} = doc} when is_map(paths) -> {:ok, doc}
      {:ok, _} -> {:error, "spec #{path} has no `paths` object"}
      {:error, _} -> {:error, "spec #{path} is not valid JSON"}
    end
  end

  defp endpoints(%{"paths" => paths}) do
    for {path, item} <- paths,
        is_map(item),
        {method, _op} <- item,
        method in @methods,
        into: MapSet.new() do
      {String.to_existing_atom(method), Operation.path_shape(path)}
    end
  end
end
