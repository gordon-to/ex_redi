defmodule ExRedi.Parser do
  @moduledoc """
  Handles parsing/formatting of RediSearch results.

  **For Internal Use**
  """
  @type id :: ExRedi.id()

  @type opts :: ExRedi.opts()

  @type fields :: [binary]

  @spec info([binary]) :: map
  def info(result) do
    result
    |> chunk()
    |> Map.update!("gc_stats", &chunk/1)
  end

  @spec member([binary] | nil, id) :: map | nil
  def member(fields, id)
  def member(nil, _), do: nil

  def member(fields, id) do
    fields
    |> chunk()
    |> Map.put("id", id)
  end

  @spec search(list | nil, opts) :: [map] | []
  def search(results, opts)
  def search([0], _), do: []

  def search([_ | results], opts) do
    results
    |> Enum.chunk_every(chunk_size(opts, 2))
    |> Enum.map(fn
      [id, value, fields] ->
        fields
        |> member(id)
        |> Map.put("score", value)

      [id, fields] when is_list(fields) ->
        member(fields, id)

      [id, score] when is_binary(score) ->
        %{"id" => id, "score" => score}

      [id] ->
        %{"id" => id}
    end)
  end

  @spec chunk(fields) :: map
  defp chunk(fields) do
    fields
    |> Enum.chunk_every(2)
    |> Enum.map(&List.to_tuple/1)
    |> Enum.into(%{})
  end

  @spec chunk_size(opts, integer) :: integer
  defp chunk_size([], size), do: size
  defp chunk_size([{:withscores, true} | tail], size), do: chunk_size(tail, size + 1)
  defp chunk_size([{:nocontent, true} | tail], size), do: chunk_size(tail, size - 1)
  defp chunk_size([_ | tail], size), do: chunk_size(tail, size)
end
