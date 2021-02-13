defmodule EaTest do
  @moduledoc false
  use ExUnit.Case

  defmodule CacheExample do
    @moduledoc false
    use Ea

    @cached true
    def this_is_cached do
      :result
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
    def optional_arg_test(arg \\ nil) do
      arg
    end

    @cached true
    def multiple_clause_test(:a) do
      :a
    end

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

  test "caching works" do
    assert {:cached, :result} == CacheExample.this_is_cached()
  end

  test "not cached functions stay not cached (no attribute bleed)" do
    assert :result == CacheExample.this_is_not_cached()
  end

  test "attribute values are not overriden by later redeclarations" do
    assert {:cached, :expected_val} == CacheExample.attr_test()
  end

  test "caching function with optional args works" do
    assert {:cached, nil} == CacheExample.optional_arg_test()
    assert {:cached, :arg} == CacheExample.optional_arg_test(:arg)
  end

  test "adding @cached to one clause caches only that clause" do
    assert {:cached, :a} == CacheExample.multiple_clause_test(:a)
    assert :c == CacheExample.multiple_clause_test(:b)
  end

  test "adding @cached to empty function head caches all clauses" do
    assert {:cached, :result} == CacheExample.empty_function_head_test()
  end

  test "return value of function with rescue is cached" do
    assert {:cached, :result} == CacheExample.rescue_success_test()
  end

  test "return value of rescue block is cached" do
    # TODO also assert that we only access cache once
    assert {:cached, :rescued} == CacheExample.rescue_failure_test()
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
end
