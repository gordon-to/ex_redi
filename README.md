# ExRedi

A simple Elixir client for [RediSearch](http://redisearch.io/)

## Installation

```elixir
def deps do
  [
    {:ex_redi, "~> 0.1.0"}
  ]
end
```

## Usage

Create/Drop an index

```elixir
iex> ExRedi.create("myIdx", ["player", "TEXT", "games", "NUMERIC", "SORTABLE"])
:ok

iex> ExRedi.drop("myIdx")
:ok
```

Add some documents

```elixir
iex> ExRedi.add("myIdx", "1", ["player", "foo", "games", 5])
:ok

iex> docs = [
...>   {"2", ["player", "bar", "games", 8]},
...>   {"3", ["player", "baz", "games", 4]}
...> ]
...> ExRedi.add_multi("myIdx", docs)
[:ok, :ok]
```

Find some documents

```elixir
iex> ExRedi.search("myIdx", "foo")
{:ok, [%{"games" => "5", "id" => "1", "player" => "foo"}]}

iex> ExRedi.search("myIdx", "nothing")
{:ok, []}

iex> ExRedi.search("myIdx", "@games:[3 5]")
{:ok, [
  %{"games" => "4", "id" => "3", "name" => "baz"},
  %{"games" => "5", "id" => "1", "name" => "foo"}
]}
```

Get a specific document

```elixir
iex> ExRedi.get("myIdx", "2")
{:ok, %{"games" => "8", "id" => "2", "player" => "bar"}}

iex> ExRedi.get("myIdx", "not-a-doc")
{:ok, nil}
```

Remove a document from the index

```elixir
iex> ExRedi.del("myIdx", "3")
{:ok, 1}
```
