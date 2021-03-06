defmodule Ea.Backend do
  @moduledoc """
  Cache backend specification for Ea.
  """

  @callback fetch(
              module :: module(),
              function_name :: atom(),
              args :: [any()],
              opts :: Keyword.t()
            ) ::
              {:ok, any()} | :error
  @callback put(
              module :: module(),
              function_name :: atom(),
              args :: [any()],
              value :: any(),
              expiry :: pos_integer() | :never,
              opts :: Keyword.t()
            ) ::
              :ok
  @callback invalidate(
              module :: module(),
              function_name :: atom(),
              args :: [any()],
              opts :: Keyword.t()
            ) :: :ok
  @callback invalidate_all(
              module :: module(),
              function_name :: atom(),
              arity :: arity(),
              opts :: Keyword.t()
            ) :: :ok

  @optional_callbacks invalidate_all: 4
end
