defmodule ExRedi do
  @moduledoc """
  Documentation for ExRedi.
  """
  use Application

  alias ExRedi.{
    Options,
    Parser
  }

  @typedoc "The name of your RediSearch index"
  @type index :: binary | atom

  @typedoc "RediSearch query string"
  @type query :: binary

  @typedoc "RediSearch schema definition"
  @type schema :: [binary]

  @typedoc "RediSearch field definition"
  @type fields :: [binary]

  @typedoc "Document ID"
  @type id :: binary | integer

  @typedoc "Document format for multi-ops"
  @type doc :: {id, fields}

  @typedoc "Operation options"
  @type opts :: keyword

  @typedoc "Error returned from a failed operation"
  @type error :: {:error, binary}

  @redis ExRedi.Redis

  @score "1.0"

  defguardp is_index(term) when is_binary(term) or is_atom(term)

  @doc false
  def start(_type, _args) do
    children = [
      {Redix, [[], [name: @redis]]}
    ]

    opts = [
      strategy: :one_for_one,
      name: ExRedi.Supervisor
    ]

    Supervisor.start_link(children, opts)
  end

  @doc """
  Creates an index with the given spec.

  [More Info](http://redisearch.io/Commands/#ftcreate)

  ## Examples

      iex> ExRedi.create("myIdx", ["title", "TEXT", "WEIGHT", "5.0", "body", "TEXT"])
      :ok

      iex> ExRedi.create("myIdx", ["title", "TEXT"])
      {:error, "Index already exists. Drop it first!"}

  """
  @spec create(index, schema, opts) :: :ok | error
  def create(index, schema, opts \\ []) when is_index(index) do
    args = ["FT.CREATE", index, build_opts(:create, opts), "SCHEMA", schema]

    with {:ok, "OK"} <- command(args) do
      :ok
    end
  end

  @doc """
  Deletes all the keys associated with the index.

  [More Info](http://redisearch.io/Commands/#ftdrop)

  ## Examples

      iex> ExRedi.create("myIdx", ["title", "TEXT"])
      :ok
      iex> ExRedi.drop("myIdx")
      :ok
      iex> ExRedi.info("myIdx")
      {:error, "Unknown Index name"}

      iex> ExRedi.drop("notMyIdx")
      {:error, "Unknown Index name"}

  """
  @spec drop(index) :: :ok | error
  def drop(index) when is_index(index) do
    with {:ok, "OK"} <- command(["FT.DROP", index]) do
      :ok
    end
  end

  @doc """
  Checks if the index exists.

  ## Examples

      iex> exists?("myIdx")
      true

      iex> exists?("notMyIdx")
      false

  """
  @spec exists?(index) :: boolean
  def exists?(index) when is_index(index) do
    with {:ok, data} <- info(index) do
      Map.get(data, "index_name") === to_string(index)
    else
      _ ->
        false
    end
  end

  @doc """
  Adds a document to the index.

  [More Info](http://redisearch.io/Commands/#ftadd)

  ## Example

      iex> ExRedi.add("myIdx", "1", ["title", "foo", "body", "bar"])
      :ok

  """
  @spec add(index, id, fields, opts) :: :ok | error
  def add(index, id, fields, opts \\ []) do
    {score, opts} = Keyword.pop(opts, :score, @score)

    args = ["FT.ADD", index, id, score, build_opts(:add, opts), "FIELDS", fields]

    with {:ok, "OK"} <- command(args) do
      :ok
    end
  end

  @doc """
  Adds multiple document to the index via Redis 'MULTI'.

  [More Info](http://redisearch.io/Commands/#ftadd)

  ## Example

      iex> docs = [
      ...>   {"1", ["title", "foo", "body", "hello"]},
      ...>   {"2", ["title", "bar", "body", "world"]}
      ...> ]
      ...> ExRedi.add_multi("myIdx", docs)
      [:ok, :ok]

  """
  @spec add_multi(index, [doc], opts) :: [:ok, ...] | error
  def add_multi(index, docs, opts \\ []) when is_index(index) do
    Enum.map(docs, fn {id, fields} ->
      # TODO: Actually use Redis MULTI
      add(index, id, fields, opts)
    end)
  end

  @doc """
  Adds a document to the index from an existing HASH key in Redis.

  [More Info](http://redisearch.io/Commands/#ftaddhash)

  ## Examples

      iex> Redix.command(:ex_redi, ["HMSET", "doc-1", "title", "hello world"])
      {:ok, "OK"}
      iex> ExRedi.add_hash("myIdx", "doc-1")
      :ok

      iex> ExRedi.add_hash("myIdx", "nothing-here")
      {:error, "Could not load document"}

  """
  @spec add_hash(index, id, opts) :: :ok | error
  def add_hash(index, id, opts \\ []) when is_index(index) do
    {score, opts} = Keyword.pop(opts, :score, @score)

    args = ["FT.ADDHASH", index, id, score, build_opts(:add, opts)]

    with {:ok, "OK"} <- command(args) do
      :ok
    end
  end

  @doc """
  Returns the full contents of a document.

  [More Info](http://redisearch.io/Commands/#ftget)
  """
  @spec get(index, id) :: map | error
  def get(index, id) when is_index(index) do
    with {:ok, result} <- command(["FT.GET", index, id]) do
      result
      |> Parser.member(id)
      |> wrap(:ok)
    end
  end

  @doc """
  Returns the full contents of multiple documents.

  [More Info](http://redisearch.io/Commands/#ftmget)
  """
  @spec mget(index, [id]) :: [map] | error
  def mget(index, ids) when is_index(index) do
    with {:ok, result} <- command(["FT.MGET", index, ids]) do
      result
      |> Enum.zip(ids)
      |> Enum.map(fn
        {nil, _} -> nil
        {result, id} -> Parser.member(result, id)
      end)
      |> Enum.reject(&is_nil/1)
      |> wrap(:ok)
    end
  end

  @doc """
  Deletes a document from the index.

  Returns 1 if the document was removed from the index, otherwise 0.

  [More Info](http://redisearch.io/Commands/#ftdel)

  ## Examples

      iex> ExRedi.del("myIdx", "1")
      1

      iex> ExRedi.del("myIdx", "nothing-here")
      0

  """
  @spec del(index, id) :: integer | error
  def del(index, id) when is_index(index) do
    command(["FT.DEL", index, id, "DD"])
  end

  @doc """
  Returns information and statistics on the index.

  [More Info](http://redisearch.io/Commands/#ftinfo)

  ## Example

    iex> ExRedi.info("myIdx")
    %{
      "bytes_per_record_avg" => "...",
      "doc_table_size_mb" => "...",
      "fields" => [...],
      ...
    }

  """
  @spec info(index) :: map | error
  def info(index) when is_index(index) do
    with {:ok, result} <- command(["FT.INFO", index]) do
      result
      |> Parser.info()
      |> wrap(:ok)
    end
  end

  @doc """
  Searches the index with the given query, returning either documents or ids.

  [More Info](http://redisearch.io/Commands/#ftsearch)

  [Syntax](http://redisearch.io/Query_Syntax)
  """
  @spec search(index, query, opts) :: [map] | error
  def search(index, query, opts \\ []) when is_index(index) do
    args = ["FT.SEARCH", index, query, build_opts(:search, opts)]

    with {:ok, result} <- command(args) do
      result
      |> Parser.search(opts)
      |> wrap(:ok)
    end
  end

  @doc """
  Runs a search query and performs aggregate transformations on the results.

  [More Info](http://redisearch.io/Commands/#ftaggregate)

  [Overview](http://redisearch.io/Aggregations)
  """
  @spec aggregate(index, query, opts) :: list | error
  def aggregate(index, query, opts \\ []) when is_index(index) do
    command(["FT.AGGREGATE", index, query, build_opts(:aggregate, opts)])
  end

  @doc """
  Prints the execution plan for a query

  [More Info](http://redisearch.io/Commands/#ftexplain)
  """
  @spec explain(index, query) :: :ok | error
  def explain(index, query) when is_index(index) do
    with {:ok, result} <- command(["FT.EXPLAIN", index, query]) do
      IO.puts(result)
    end
  end

  @doc """
  Returns the distinct tags indexed in a Tag field.

  [More Info](http://redisearch.io/Commands/#fttagvals)
  """
  @spec tag_vals(index, field :: binary) :: list | error
  def tag_vals(index, field) when is_index(index) do
    command(["FT.TAGVALS", index, field])
  end

  @doc """
  Adds a suggestion string to an auto-complete suggestion dictionary.

  [More Info](http://redisearch.io/Commands/#ftsugadd)
  """
  @spec add_suggestion(key :: binary, string :: binary, opts) :: integer | error
  def add_suggestion(key, string, opts \\ []) do
    {score, opts} = Keyword.pop(opts, :score, @score)

    command(["FT.SUGADD", key, string, score, build_opts(:sugadd, opts)])
  end

  @doc """
  Gets completion suggestions for a prefix.

  [More Info](http://redisearch.io/Commands/#ftsugget)
  """
  @spec get_suggestion(key :: binary, prefix :: binary, opts) :: list | error
  def get_suggestion(key, prefix, opts \\ []) do
    command(["FT.SUGGET", key, prefix, build_opts(:sugget, opts)])
  end

  @doc """
  Deletes a string from a suggestion index.

  Returns 1 if the string was removed, otherwise 0.

  [More Info](http://redisearch.io/Commands/#ftsugdel)
  """
  @spec delete_suggestion(key :: binary, string :: binary) :: integer | error
  def delete_suggestion(key, string) do
    command(["FT.SUGDEL", key, string])
  end

  @doc """
  Gets the size of an auto-complete suggestion dictionary.

  [More Info](http://redisearch.io/Commands/#ftsuglen)
  """
  @spec suggestion_length(key :: binary) :: integer | error
  def suggestion_length(key) do
    command(["FT.SUGLEN", key])
  end

  # ======= #
  # Private #
  # ======= #

  defp build_opts(key, opts), do: Options.build(key, opts)

  defp wrap(term, tag), do: {tag, term}

  defp command(args) do
    Redix.command(@redis, List.flatten(args))
  rescue
    error in Redix.Error ->
      {:error, Exception.message(error)}
  end
end
