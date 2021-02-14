defmodule Ea.Time do
  @moduledoc false

  @callback monotonic_milliseconds() :: integer()
  def monotonic_milliseconds do
    System.monotonic_time(:millisecond)
  end
end
