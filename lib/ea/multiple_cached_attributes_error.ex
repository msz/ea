defmodule Ea.MultipleCachedAttributesError do
  defexception [:message]

  def new(module, name, arity) do
    %__MODULE__{
      message:
        "More than one @cached attribute defined for #{module}.#{name}/#{arity}. Please only define one."
    }
  end
end
