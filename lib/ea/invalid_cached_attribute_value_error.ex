defmodule Ea.InvalidCachedAttributeValueError do
  defexception [:message]

  def new(invalid_value) do
    %__MODULE__{
      message:
        "Invalid @cached attribute value passed: #{inspect(invalid_value)}. It needs to be true (never expire) or a positive integer representing expiry time."
    }
  end
end
