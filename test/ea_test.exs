defmodule EaTest do
  @moduledoc false
  use ExUnit.Case

  import Hammox

  alias Ea.BackendMock
  alias Ea.BackendMockSecondary

  @backend_opts :ea |> Application.compile_env!(:default_backend) |> elem(1)

  defmodule EmptyBackend do
    @moduledoc false
  end

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

    @cached 1000
    def this_is_cached_positive_integer do
      :result
    end

    @cached {1000, :millisecond}
    def this_is_cached_milliseconds do
      :result
    end

    @cached {1000, :second}
    def this_is_cached_seconds do
      :result
    end

    @cached {1000, :minute}
    def this_is_cached_minutes do
      :result
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

    def single_invalidation_test do
      invalidate_cache(:this_is_cached_with_param, [:arg])
    end

    def invalidate_all_test do
      invalidate_cache(:this_is_cached_with_param, 1)
    end
  end

  defmodule CacheExampleCustomBackend do
    @moduledoc false
    use Ea, backend: BackendMockSecondary

    @cached true
    def this_is_cached, do: :result
  end

  defmodule CacheExampleCustomBackendWithOpts do
    @moduledoc false
    use Ea, backend: {BackendMockSecondary, name: :backend_name}

    @cached true
    def this_is_cached, do: :result
  end

  defmodule CacheExampleEmptyBackend do
    @moduledoc false

    use Ea, backend: EmptyBackend

    def invalidate_all_test do
      invalidate_cache(:some_func, 1)
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

  test "cached attribute value is passed as :never if it's true" do
    setup_cache_fail(CacheExample, :this_is_cached, [], :result, :never)

    assert :result == CacheExample.this_is_cached()
  end

  test "cached attribute value is interpreted as seconds and converted to milliseconds when it's a positive integer" do
    setup_cache_fail(CacheExample, :this_is_cached_positive_integer, [], :result, 1000 * 1000)

    assert :result == CacheExample.this_is_cached_positive_integer()
  end

  test "cached attribute value as milliseconds is passed without conversion" do
    setup_cache_fail(CacheExample, :this_is_cached_milliseconds, [], :result, 1000)

    assert :result == CacheExample.this_is_cached_milliseconds()
  end

  test "cached attribute value as seconds is converted to milliseconds" do
    setup_cache_fail(CacheExample, :this_is_cached_seconds, [], :result, 1000 * 1000)

    assert :result == CacheExample.this_is_cached_seconds()
  end

  test "cached attribute value as minutes is converted to milliseconds" do
    setup_cache_fail(CacheExample, :this_is_cached_minutes, [], :result, 1000 * 1000 * 60)

    assert :result == CacheExample.this_is_cached_minutes()
  end

  test "fails with negative @cached attribute value" do
    module_string = """
      defmodule CacheExampleNegativeValue do
        use Ea

        @cached -1
        def this_is_cached do
          nil
        end
      end
    """

    assert_raise Ea.InvalidCachedAttributeValueError, fn -> Code.compile_string(module_string) end
  end

  test "fails with zero @cached attribute value" do
    module_string = """
      defmodule CacheExampleZeroValue do
        use Ea

        @cached 0
        def this_is_cached do
          nil
        end
      end
    """

    assert_raise Ea.InvalidCachedAttributeValueError, fn -> Code.compile_string(module_string) end
  end

  test "fails with invalid @cached attribute value" do
    module_string = """
      defmodule CacheExampleInvalidValue do
        use Ea

        @cached :some_atom
        def this_is_cached do
          nil
        end
      end
    """

    assert_raise Ea.InvalidCachedAttributeValueError, fn -> Code.compile_string(module_string) end
  end

  test "unused params are still used as params for caching" do
    setup_cache_pass(CacheExample, :this_is_cached_with_unused_param, [:val])

    assert :cached == CacheExample.this_is_cached_with_unused_param(:val)
  end

  test "not cached functions stay not cached (no attribute bleed)" do
    assert :result == CacheExample.this_is_not_cached()
  end

  test "attribute values are not overriden by later redeclarations" do
    setup_cache_fail(CacheExample, :attr_test, [], :expected_val, :never)
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
    setup_cache_fail(CacheExample, :rescue_success_test, [], :result, :never)
    assert :result == CacheExample.rescue_success_test()
  end

  test "return value of rescue block is cached" do
    setup_cache_fail(CacheExample, :rescue_failure_test, [], :rescued, :never)
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

  test "fails when :backend option value is an invalid value" do
    module_string = """
      defmodule CacheExample do
        use Ea, backend: 1
      end
    """

    assert_raise Ea.InvalidOptionValueError, fn -> Code.compile_string(module_string) end
  end

  test "fails when :backend option value is a tuple of invalid values" do
    module_string = """
      defmodule CacheExample do
        use Ea, backend: {SomeBackend, :invalid}
      end
    """

    assert_raise Ea.InvalidOptionValueError, fn -> Code.compile_string(module_string) end
  end

  test "uses the backend from the :backend option" do
    expect(BackendMockSecondary, :fetch, fn CacheExampleCustomBackendWithOpts,
                                            :this_is_cached,
                                            [],
                                            [name: :backend_name] ->
      {:ok, :cached}
    end)

    assert :cached == CacheExampleCustomBackendWithOpts.this_is_cached()
  end

  test "when the :backend opt is a plain atom, it passes empty list of backend opts" do
    expect(BackendMockSecondary, :fetch, fn CacheExampleCustomBackend, :this_is_cached, [], [] ->
      {:ok, :cached}
    end)

    assert :cached == CacheExampleCustomBackend.this_is_cached()
  end

  test "cache invalidation works for a list of args" do
    expect(BackendMock, :invalidate, fn CacheExample,
                                        :this_is_cached_with_param,
                                        [:arg],
                                        @backend_opts ->
      :ok
    end)

    assert :ok == CacheExample.single_invalidation_test()
  end

  test "cache invalidation works for arity" do
    expect(BackendMock, :invalidate_all, fn CacheExample,
                                            :this_is_cached_with_param,
                                            1,
                                            @backend_opts ->
      :ok
    end)

    assert :ok == CacheExample.invalidate_all_test()
  end

  test "when backend does not implement invalidate_all/4, a well formed Ea error is returned" do
    assert_raise Ea.NoInvalidateAllInBackendError, fn ->
      CacheExampleEmptyBackend.invalidate_all_test()
    end
  end

  defp setup_cache_pass(module, name, args) do
    expect(BackendMock, :fetch, fn ^module, ^name, ^args, @backend_opts ->
      {:ok, :cached}
    end)
  end

  defp setup_cache_fail(module, name, args, expected_value, expected_expiry) do
    expect(BackendMock, :fetch, fn ^module, ^name, ^args, @backend_opts ->
      :error
    end)

    expect(BackendMock, :put, fn ^module,
                                 ^name,
                                 ^args,
                                 ^expected_value,
                                 ^expected_expiry,
                                 @backend_opts ->
      :ok
    end)
  end
end
