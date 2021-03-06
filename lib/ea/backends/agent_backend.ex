defmodule Ea.Backends.AgentBackend do
  @moduledoc """
  Simple, Agent-based in-memory caching backend.
  """
  use Agent

  @behaviour Ea.Backend

  @time Application.get_env(:ea, :time) || Ea.Time

  def start_link(opts) do
    name = get_name(opts)
    Agent.start_link(fn -> %{} end, name: name)
  end

  @impl true
  def fetch(module, function_name, args, opts) do
    name = get_name(opts)
    mfa = {module, function_name, args}

    case Agent.get(name, &Map.fetch(&1, mfa)) do
      {:ok, {value, expiry_timestamp}} ->
        if expiry_timestamp == :never or @time.monotonic_milliseconds() < expiry_timestamp do
          {:ok, value}
        else
          :ok = Agent.update(name, &Map.delete(&1, mfa))
          :error
        end

      :error ->
        :error
    end
  end

  @impl true
  def put(module, function_name, args, value, expiry, opts) do
    name = get_name(opts)
    mfa = {module, function_name, args}

    expiry_timestamp =
      case expiry do
        :never -> :never
        expiry when is_integer(expiry) -> @time.monotonic_milliseconds() + expiry
      end

    :ok = Agent.update(name, &Map.put(&1, mfa, {value, expiry_timestamp}))
  end

  @impl true
  def invalidate(module, function_name, args, opts) do
    name = get_name(opts)
    mfa = {module, function_name, args}

    :ok = Agent.update(name, &Map.delete(&1, mfa))
  end

  @impl true
  def invalidate_all(module, function_name, arity, opts) do
    name = get_name(opts)

    :ok =
      Agent.update(name, fn state ->
        state
        |> Enum.reject(fn {{cached_module, cached_function_name, cached_args}, _cache_value} ->
          module == cached_module and function_name == cached_function_name and
            length(cached_args) == arity
        end)
        |> Enum.into(%{})
      end)
  end

  defp get_name(opts) do
    case Keyword.fetch(opts, :name) do
      {:ok, name} ->
        name

      :error ->
        raise ArgumentError,
              "You need to pass the :name of your AgentBackend instance as a backend option"
    end
  end
end
