defmodule Ea.Backends.SimpleBackendTest do
  alias Ea.Backends.SimpleBackend
  alias Ea.TimeMock

  use ExUnit.Case, async: true
  use Hammox.Protect, module: SimpleBackend, behaviour: Ea.Backend

  import Hammox

  @name :simple_backend_test

  setup :setup_backend
  setup :verify_on_exit!

  test "fetching nonexistent key results in :error" do
    assert :error == fetch(SomeModule, :some_function, [], name: @name)
  end

  test "putting and fetching succeeds" do
    put(SomeModule, :some_function, [], :value, :never, name: @name)
    assert {:ok, :value} == fetch(SomeModule, :some_function, [], name: @name)
  end

  test "putting for one set of args does not affect other args" do
    put(SomeModule, :some_function, [:one_arg], :value, :never, name: @name)
    assert :error == fetch(SomeModule, :some_function, [:another_arg], name: @name)
  end

  test ":error when value expires" do
    Hammox.expect(TimeMock, :monotonic_milliseconds, fn -> 0 end)
    Hammox.expect(TimeMock, :monotonic_milliseconds, fn -> 10_000 end)

    put(SomeModule, :some_function, [], :value, 5000, name: @name)
    assert :error == fetch(SomeModule, :some_function, [], name: @name)
  end

  test ":error when key is invalidated" do
    put(SomeModule, :some_function, [], :value, :never, name: @name)
    invalidate(SomeModule, :some_function, [], name: @name)
    assert :error == fetch(SomeModule, :some_function, [], name: @name)
  end

  test "invalidate_all invalidates all values for function" do
    put(SomeModule, :some_function, [:one_arg], :one_value, :never, name: @name)
    put(SomeModule, :some_function, [:another_arg], :another_value, :never, name: @name)

    put(SomeModule, :some_function, [:one_arg, :another_arg], :yet_another_value, :never,
      name: @name
    )

    invalidate_all(SomeModule, :some_function, 1, name: @name)

    assert :error == fetch(SomeModule, :some_function, [:one_arg], name: @name)
    assert :error == fetch(SomeModule, :some_function, [:another_arg], name: @name)

    assert {:ok, :yet_another_value} ==
             fetch(SomeModule, :some_function, [:one_arg, :another_arg], name: @name)
  end

  defp setup_backend(_context) do
    [backend: SimpleBackend.start_link(name: @name)]
  end
end
