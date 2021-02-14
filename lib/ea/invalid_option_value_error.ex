defmodule Ea.InvalidOptionValueError do
  defexception [:message]

  def new(invalid_value, option_name, allowed_option_values) do
    %__MODULE__{
      message:
        "Invalid value #{invalid_value} was passed for the #{inspect(option_name)} Ea option. Allowed values: #{
          inspect(allowed_option_values)
        }"
    }
  end
end
