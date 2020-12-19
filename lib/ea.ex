defmodule Ea do
  @moduledoc """
  The main Ea module.
  """

  defmodule MultipleCachedAttributesError do
    defexception [:message]
  end

  def hello do
    :world
  end

  defmacro __using__(_) do
    quote do
      @on_definition Ea
      @before_compile Ea

      Module.register_attribute(__MODULE__, :cached, accumulate: true)
    end
  end

  def __on_definition__(env, kind, name, args, guards, body) do
    case Module.get_attribute(env.module, :cached) do
      [] ->
        nil

      [cached_value] ->
        Module.put_attribute(
          env.module,
          :cached_func,
          {kind, name, args, guards, body, cached_value}
        )

        Module.delete_attribute(env.module, :cached)

      [_ | _] ->
        raise MultipleCachedAttributesError,
              "More than one @cached attribute defined for #{env.module}.#{name}/#{length(args)}. Please only define one."
    end
  end

  def __before_compile__(env) do
  end
end
