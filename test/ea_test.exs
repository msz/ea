defmodule EaTest do
  @moduledoc false
  use ExUnit.Case

  import Hammox

  defmock(BackendMock, for: Ea.Backend)

  @backend_opts :ea |> Application.compile_env!(:default_backend) |> elem(1)

  defmodule CacheExample do
    @moduledoc false
    use Ea

    @cached true
    def this_is_cached do
      :result
    end

    @cached true
    def this_is_cached_with_param(param) do
      param
    end

    @cached true
    def this_is_cached_with_unused_param(_param) do
      :baked_in_value
    end

    def this_is_not_cached do
      :result
    end

    @attr_test_val :expected_val
    @cached true
    def attr_test do
      @attr_test_val
    end

    @attr_test_val :overriden_val

    @cached true
    def default_param_test(param \\ nil) do
      param
    end

    def multiple_clause_test(:a) do
      :a
    end

    @cached true
    def multiple_clause_test(:b) do
      :c
    end

    @cached true
    def empty_function_head_test

    def empty_function_head_test, do: :result

    @cached true
    def rescue_success_test do
      :result
    rescue
      _ -> :rescued
    end

    @cached true
    def rescue_failure_test do
      raise "boom"
    rescue
      _ -> :rescued
    end
  end

  setup :verify_on_exit!

  test "caching works" do
    setup_cache_pass(CacheExample, :this_is_cached, [])

    assert :cached == CacheExample.this_is_cached()
  end

  test "caching function with param works" do
    setup_cache_pass(CacheExample, :this_is_cached_with_param, [:val])

    assert :cached == CacheExample.this_is_cached_with_param(:val)
  end

  test "unused params are still used as params for caching" do
    setup_cache_pass(CacheExample, :this_is_cached_with_unused_param, [:val])

    assert :cached == CacheExample.this_is_cached_with_unused_param(:val)
  end

  test "not cached functions stay not cached (no attribute bleed)" do
    assert :result == CacheExample.this_is_not_cached()
  end

  test "attribute values are not overriden by later redeclarations" do
    setup_cache_fail(CacheExample, :attr_test, [], :expected_val)
    assert :expected_val == CacheExample.attr_test()
  end

  test "caching function with default params works" do
    setup_cache_pass(CacheExample, :default_param_test, [nil])
    assert :cached == CacheExample.default_param_test()

    setup_cache_pass(CacheExample, :default_param_test, [:value])
    assert :cached == CacheExample.default_param_test(:value)
  end

  test "adding @cached to one clause caches only that clause" do
    assert :a == CacheExample.multiple_clause_test(:a)

    setup_cache_pass(CacheExample, :multiple_clause_test, [:b])
    assert :cached == CacheExample.multiple_clause_test(:b)
  end

  test "adding @cached to empty function head caches all clauses" do
    setup_cache_pass(CacheExample, :empty_function_head_test, [])
    assert :cached == CacheExample.empty_function_head_test()
  end

  test "return value of function with rescue is cached" do
    setup_cache_fail(CacheExample, :rescue_success_test, [], :result)
    assert :result == CacheExample.rescue_success_test()
  end

  test "return value of rescue block is cached" do
    setup_cache_fail(CacheExample, :rescue_failure_test, [], :rescued)
    assert :rescued == CacheExample.rescue_failure_test()
  end

  test "fails with multiple @cached attributes for one function" do
    module_string = """
      defmodule CacheExample do
        use Ea

        @cached false
        @cached true
        def this_is_cached do
          nil
        end
      end
    """

    assert_raise Ea.MultipleCachedAttributesError, fn -> Code.compile_string(module_string) end
  end

  defp setup_cache_pass(module, name, args) do
    expect(BackendMock, :get, fn ^module, ^name, ^args, @backend_opts ->
      {:ok, :cached}
    end)
  end

  defp setup_cache_fail(module, name, args, expected_value) do
    expect(BackendMock, :get, fn ^module, ^name, ^args, @backend_opts ->
      {:error, :no_value}
    end)

    expect(BackendMock, :put, fn ^module, ^name, ^args, ^expected_value, @backend_opts ->
      :ok
    end)
  end
end
