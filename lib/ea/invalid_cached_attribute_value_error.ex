defmodule Ea.InvalidCachedAttributeValueError do
  defexception [:message]

  def new(invalid_value) do
    %__MODULE__{
      message: """
      Invalid @cached attribute value passed: #{inspect(invalid_value)}. It needs to be one of:
      - true (never expire)
      - positive integer representing expiry time in seconds
      - a 2-tuple where the first element is a positive integer representing expiry time, and the second element is an atom designating the time unit (one of: :millisecond, :second, :minute)
      """
    }
  end
end
