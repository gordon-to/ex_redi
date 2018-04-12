defmodule ExRedi.Options do
  @moduledoc """
  Handles parsing/formatting of user-supplied options.

  **For Internal Use**
  """
  @type opts :: ExRedi.opts()

  @type key :: atom

  @type flags :: [binary]

  @type params :: [[binary], ...]

  # Flags (Boolean Options)
  #
  # Flags can only be true or false:
  #   [verbatim: true, withscores: true, withsortkeys: false]
  #
  @flags [
    create: ~w(nooffsets nofreqs nohl nofields)a,
    add: ~w(nosave replace partial)a,
    search: ~w(nocontent inorder nostopwords withscores verbatim)a,
    aggregate: [],
    sugadd: ~w(incr)a,
    sugget: ~w(withscores withpayloads fuzzy)a
  ]

  # Params (List Options)
  #
  # Params need to be an array of values:
  #   [limit: ["0", "10"], sortby: ["url", "desc"], return: ["2", "title"]]
  #
  @params [
    create: ~w(stopwords)a,
    add: ~w(language)a,
    search: ~w(
      return limit infields inkeys slop filter
      geofilter language expander scorer sortby
    )a,
    aggregate: ~w(groupby sortby apply limit)a,
    sugadd: ~w(payload)a,
    sugget: ~w(max)a
  ]

  @keys ~w(create add search aggregate sugadd sugget)a

  @spec build(key, opts) :: [flags | params, ...]
  def build(key, opts) when key in @keys do
    flags(key, opts) ++ params(key, opts)
  end

  @spec flags(key, opts) :: flags
  defp flags(key, opts) do
    @flags
    |> Keyword.fetch!(key)
    |> Enum.filter(&Keyword.get(opts, &1))
    |> Enum.map(&keyify/1)
  end

  @spec params(key, opts) :: params
  defp params(key, opts) do
    @params
    |> Keyword.fetch!(key)
    |> Enum.filter(&Keyword.has_key?(opts, &1))
    |> Enum.map(&[keyify(&1) | Keyword.fetch!(opts, &1)])
  end

  @spec keyify(atom) :: binary
  defp keyify(atom) do
    atom
    |> Atom.to_string()
    |> String.upcase()
  end
end
