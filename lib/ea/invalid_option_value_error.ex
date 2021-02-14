defmodule Ea.InvalidOptionValueError do
  defexception [:message]

  def new(invalid_value, option_name, expectation) do
    %__MODULE__{
      message:
        "Invalid value #{Macro.to_string(invalid_value)} was passed for the #{
          inspect(option_name)
        } Ea option. Expected: #{expectation}."
    }
  end
end
