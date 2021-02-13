defmodule Ea.Backend do
  @moduledoc """
  Cache backend specification for Ea.
  """

  @callback get(module :: module(), function_name :: atom(), args :: [any()], opts :: Keyword.t()) ::
              {:ok, any()} | {:error, :no_value}
  @callback put(
              module :: module(),
              function_name :: atom(),
              args :: [any()],
              value :: any(),
              opts :: Keyword.t()
            ) ::
              :ok
  @callback invalidate(
              module :: module(),
              function_name :: atom(),
              args :: [any()],
              opts :: Keyword.t()
            ) :: :ok
end
