defmodule ExRediTest do
  use ExUnit.Case

  @index "myIdx"

  @schema ~w(title TEXT WEIGHT 5.0 SORTABLE body TEXT)

  setup do
    if ExRedi.exists?(@index) do
      assert :ok = ExRedi.drop(@index)
    end

    assert :ok = ExRedi.create(@index, @schema)

    :ok
  end

  test "create/2 with valid schema" do
    assert true = ExRedi.exists?(@index)
    assert :ok = ExRedi.drop(@index)
    assert :ok = ExRedi.create(@index, @schema)
    assert {:ok, info} = ExRedi.info(@index)
    assert {"index_name", @index} in info
  end

  test "create/2 with bad schema" do
    result = ExRedi.create(@index, ["foo", "BAR", "WEIGHT", "baz"])
    assert {:error, "Could not parse field spec"} = result
  end

  test "drop/1" do
    assert :ok = ExRedi.drop(@index)

    result = ExRedi.info(@index)
    assert {:error, "Unknown Index name"} = result
  end

  test "add/3" do
    doc = ["title", "foo", "body", "bar"]
    expected = [%{"id" => "1", "title" => "foo", "body" => "bar"}]

    assert :ok = ExRedi.add(@index, "1", doc)
    assert {:ok, ^expected} = ExRedi.search(@index, "foo")
  end

  test "add/3 when existing record" do
    doc = ["title", "foo", "body", "bar"]
    new = ["title", "bar", "body", "baz"]
    expected = [%{"id" => "1", "title" => "bar", "body" => "baz"}]

    assert :ok = ExRedi.add(@index, "1", doc)
    assert {:error, "Document already in index"} = ExRedi.add(@index, "1", new)
    assert :ok = ExRedi.add(@index, "1", new, replace: true)
    assert {:ok, []} = ExRedi.search(@index, "foo")
    assert {:ok, ^expected} = ExRedi.search(@index, "bar")
  end

  test "add_multi/2" do
    docs = [
      {"1", ["title", "doc-1", "body", "foo"]},
      {"2", ["title", "doc-2", "body", "bar"]},
      {"3", ["title", "doc-3", "body", "baz"]}
    ]

    assert [:ok, :ok, :ok] = ExRedi.add_multi(@index, docs)
    assert {:ok, search} = ExRedi.search(@index, "1|2")

    ids = Enum.map(search, &Map.get(&1, "id"))
    Enum.each(1..2, &assert(to_string(&1) in ids))
  end

  test "add_hash/2" do
    {:ok, pid} = start_supervised(Redix)

    assert "OK" = Redix.command!(pid, ["HMSET", "doc-1", "title", "hello world"])
    assert {:ok, []} = ExRedi.search(@index, "@title:hello")
    assert :ok = ExRedi.add_hash(@index, "doc-1")
    assert {:ok, search} = ExRedi.search(@index, "@title:hello")
    assert [%{"id" => "doc-1", "title" => "hello world"}] = search
  end

  test "get/2" do
    doc1 = ["title", "foo", "body", "bar"]
    doc2 = ["title", "bar", "body", "baz"]
    expected = %{"id" => "1", "body" => "bar", "title" => "foo"}

    assert :ok = ExRedi.add(@index, "1", doc1)
    assert :ok = ExRedi.add(@index, "2", doc2)
    assert {:ok, ^expected} = ExRedi.get(@index, "1")
  end

  test "mget/2" do
    doc1 = ["title", "foo", "body", "bar"]
    doc2 = ["title", "bar", "body", "baz"]

    expected = [
      %{"id" => "2", "title" => "bar", "body" => "baz"},
      %{"id" => "1", "title" => "foo", "body" => "bar"}
    ]

    assert :ok = ExRedi.add(@index, "1", doc1)
    assert :ok = ExRedi.add(@index, "2", doc2)
    assert {:ok, ^expected} = ExRedi.mget(@index, ["2", "1", "3"])
  end

  test "del/2" do
    docs = [
      {"1", ["title", "doc-1", "body", "foo"]},
      {"2", ["title", "doc-2", "body", "bar"]},
      {"3", ["title", "doc-3", "body", "baz"]}
    ]

    expected = %{"id" => "1", "body" => "foo", "title" => "doc-1"}

    assert [:ok, :ok, :ok] = ExRedi.add_multi(@index, docs)
    assert {:ok, 1} = ExRedi.del(@index, "2")
    assert {:ok, []} = ExRedi.search(@index, "@title:doc-2")
    assert {:ok, ^expected} = ExRedi.get(@index, "1")
    assert {:ok, 1} = ExRedi.del(@index, "1")
    assert {:ok, nil} = ExRedi.get(@index, "1")
  end

  test "info/1" do
    doc = ["title", "foo", "body", "bar"]

    assert :ok = ExRedi.add(@index, "1", doc)
    assert {:ok, data} = ExRedi.info(@index)
    assert {"num_docs", "1"} in data
    assert {"max_doc_id", "1"} in data
    assert {"num_terms", "2"} in data
  end

  test "search/2 basic" do
    docs = [
      {"1", ["title", "doc-1", "body", "foo"]},
      {"2", ["title", "doc-2", "body", "bar"]},
      {"3", ["title", "doc-3", "body", "baz"]}
    ]

    assert [:ok, :ok, :ok] = ExRedi.add_multi(@index, docs)
    assert {:ok, search} = ExRedi.search(@index, "1|2", withscores: true)
    assert Enum.count(search) == 2

    Enum.each(search, fn %{"id" => id} = doc ->
      {_, other} = Enum.find(docs, &(elem(&1, 0) === id))

      assert Map.get(doc, "title") in other
    end)
  end

  test "search/2 field selector" do
    doc = ["title", "foo", "body", "bar"]

    assert :ok = ExRedi.add(@index, "1", doc)
    assert {:ok, search} = ExRedi.search(@index, "@title:foo")
    assert Enum.count(search) == 1
    assert [%{"title" => "foo"}] = search
    assert {:ok, search2} = ExRedi.search(@index, "@body:foo")
    assert Enum.empty?(search2)
  end

  test "search/3 infields" do
    docs = [
      {"1", ["title", "doc-1", "body", "foo bar"]},
      {"2", ["title", "doc-2", "body", "bar baz"]}
    ]

    assert [:ok, :ok] = ExRedi.add_multi(@index, docs)
    assert {:ok, search} = ExRedi.search(@index, "foo|barz", infields: ["1", "body"])
    assert Enum.count(search) == 1
    assert {:ok, search2} = ExRedi.search(@index, "foo|2", infields: ["2", "title", "body"])
    assert Enum.count(search2) == 2
  end

  test "search/3 no content" do
    docs = [
      {"1", ["title", "doc-1", "body", "foo bar"]},
      {"2", ["title", "doc-2", "body", "bar baz"]}
    ]

    assert [:ok, :ok] = ExRedi.add_multi(@index, docs)
    assert {:ok, search} = ExRedi.search(@index, "@title:2", nocontent: true)
    assert Enum.count(search) == 1
    assert [%{"id" => "2"}] = search
  end

  test "search/3 no content/with scores" do
    docs = [
      {"1", ["title", "doc-1", "body", "foo bar"], "1"},
      {"2", ["title", "doc-2", "body", "bar baz"], "0.25"}
    ]

    Enum.each(docs, fn {id, doc, score} ->
      assert :ok = ExRedi.add(@index, id, doc, score: score)
    end)

    assert {:ok, search} = ExRedi.search(@index, "@title:2", nocontent: true, withscores: true)
    assert Enum.count(search) == 1
    assert [%{"id" => "2"}] = search
    assert [%{"score" => "0.5"}] = search
  end

  test "search/3 limit" do
    docs = [
      {"1", ["title", "doc-1", "body", "567"]},
      {"2", ["title", "doc-2", "body", "789"]},
      {"3", ["title", "doc-3", "body", "123"]},
      {"4", ["title", "doc-4", "body", "345"]}
    ]

    assert [:ok, :ok, :ok, :ok] = ExRedi.add_multi(@index, docs)
    assert {:ok, search} = ExRedi.search(@index, "*", limit: ["0", "3"], sortby: ["body", "asc"])
    assert Enum.count(search) == 3
    assert %{"id" => "4"} = Enum.at(search, 0)
    assert %{"id" => "3"} = Enum.at(search, 1)
    assert %{"id" => "2"} = Enum.at(search, 2)
    assert {:ok, search2} = ExRedi.search(@index, "*", limit: ["2", "3"], sortby: ["body", "asc"])
    assert Enum.count(search2) == 2
    assert %{"id" => "2"} = Enum.at(search2, 0)
    assert %{"id" => "1"} = Enum.at(search2, 1)
  end

  test "search/3 sortby" do
    docs = [
      {"1", ["title", "2004", "body", "foo bar"]},
      {"2", ["title", "2014", "body", "bar baz"]}
    ]

    assert [:ok, :ok] = ExRedi.add_multi(@index, docs)
    assert {:ok, search} = ExRedi.search(@index, "@body:bar", sortby: ["title", "asc"])
    assert Enum.count(search) == 2
    assert %{"id" => "1"} = Enum.at(search, 0)
    assert %{"id" => "2"} = Enum.at(search, 1)
    assert {:ok, search2} = ExRedi.search(@index, "@body:bar", sortby: ["title", "desc"])
    assert %{"id" => "2"} = Enum.at(search2, 0)
    assert %{"id" => "1"} = Enum.at(search2, 1)
  end

  test "search/3 return" do
    docs = [
      {"1", ["title", "doc-foo", "body", "foo bar"]},
      {"2", ["title", "doc-baz", "body", "bar baz"]}
    ]

    assert [:ok, :ok] = ExRedi.add_multi(@index, docs)
    assert {:ok, search} = ExRedi.search(@index, "@title:foo", return: ["1", "body"])
    assert Enum.count(search) == 1

    [found] = search

    assert %{"id" => "1", "body" => "foo bar"} = found
    assert found |> Map.get("title") |> is_nil()
  end
end
