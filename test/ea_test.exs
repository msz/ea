defmodule EaTest do
  use ExUnit.Case

  defmodule CacheExample do
    use Ea

    @cached true
    def this_is_cached do
      :result
    end
  end

  test "is cached" do
    assert {:cached, :result} = CacheExample.this_is_cached()
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
