defmodule EaTest do
  use ExUnit.Case

  defmodule CacheExample do
    use Ea

    @cached true
    def this_is_cached do
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
  end

  test "caching works" do
    assert {:cached, :result} == CacheExample.this_is_cached()
  end

  test "attribute values are not overriden by later redeclarations" do
    assert {:cached, :expected_val} == CacheExample.attr_test()
  end

  test "caching function with optional args works" do
    assert {:cached, nil} == CacheExample.optional_arg_test()
    assert {:cached, :arg} == CacheExample.optional_arg_test(:arg)
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
