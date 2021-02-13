defmodule Ea do
  @moduledoc """
  The main Ea module.
  """

  defmodule MultipleCachedAttributesError do
    defexception [:message]
  end

  defmacro __using__(_) do
    quote do
      @on_definition Ea
      @before_compile Ea

      Module.register_attribute(__MODULE__, :cached, accumulate: true)
      Module.register_attribute(__MODULE__, :ea_redefined_fun, accumulate: true)
    end
  end

  def __on_definition__(env, kind, name, args, guards, body) do
    {open_fun_name, open_fun_args, open_fun_cached_value} =
      Module.get_attribute(env.module, :ea_open_fun, {nil, [], nil})

    cached_value =
      if {name, length(args)} == {open_fun_name, length(open_fun_args)} and
           open_fun_cached_value != nil do
        open_fun_cached_value
      else
        case Module.get_attribute(env.module, :cached) do
          [] ->
            nil

          [cached_value] ->
            Module.delete_attribute(env.module, :cached)
            cached_value

          [_ | _] ->
            raise MultipleCachedAttributesError,
                  "More than one @cached attribute defined for #{env.module}.#{name}/#{
                    length(args)
                  }. Please only define one."
        end
      end

    attrs = extract_attributes(env.module, body)

    Module.put_attribute(
      env.module,
      :ea_redefined_fun,
      {kind, name, args, guards, body, attrs, cached_value}
    )

    unless {name, length(args)} == {open_fun_name, length(open_fun_args)} do
      new_open_fun_cached_value = if body == nil, do: cached_value, else: nil
      Module.put_attribute(env.module, :ea_open_fun, {name, args, new_open_fun_cached_value})
    end
  end

  defmacro __before_compile__(env) do
    redefined_funs = env.module |> Module.get_attribute(:ea_redefined_fun) |> Enum.reverse()
    Module.delete_attribute(env.module, :ea_redefined_fun)

    {_, funs_with_caching} =
      redefined_funs
      # We don't have anything to redefine for empty clauses
      |> reject_empty_clauses()
      |> Enum.reduce({[], []}, fn {kind, name, args, guard, body, attrs, cached_value},
                                  {prev_funs, all} ->
        override_clause =
          args
          |> implied_arities()
          |> Enum.map(
            &quote do
              defoverridable [{unquote(name), unquote(&1)}]
            end
          )

        attr_expressions =
          Enum.map(attrs, fn {attr, value} ->
            {:@, [], [{attr, [], [Macro.escape(value)]}]}
          end)

        decorated_body = apply_caching(body, cached_value)

        def_clause =
          case guard do
            [] ->
              quote do
                unquote(kind)(unquote(name)(unquote_splicing(args)), unquote(decorated_body))
              end

            _ ->
              quote do
                unquote(kind)(
                  unquote(name)(unquote_splicing(args)) when unquote_splicing(guard),
                  unquote(decorated_body)
                )
              end
          end

        arity = length(args)

        if {name, arity} in prev_funs do
          {prev_funs, [def_clause | attr_expressions ++ all]}
        else
          {[{name, arity} | prev_funs], [def_clause, override_clause | attr_expressions ++ all]}
        end
      end)

    Enum.reverse(funs_with_caching)
  end

  defp extract_attributes(module, body) do
    {_, attrs} =
      Macro.postwalk(body, %{}, fn
        {:@, _, [{attr, _, nil}]} = n, attrs ->
          attrs = Map.put(attrs, attr, Module.get_attribute(module, attr))
          {n, attrs}

        n, attrs ->
          {n, attrs}
      end)

    attrs
  end

  defp reject_empty_clauses(redefined_funs) do
    Enum.reject(
      redefined_funs,
      &match?({_kind, _fun, _args, _guards, nil, _attrs, _cached_value}, &1)
    )
  end

  defp implied_arities(args) do
    arity = Enum.count(args)

    default_count =
      args
      |> Enum.filter(fn
        {:\\, _, _} -> true
        _ -> false
      end)
      |> Enum.count()

    :lists.seq(arity, arity - default_count, -1)
  end

  defp apply_caching([do: body], cached_value) do
    [do: apply_caching(body, cached_value)]
  end

  defp apply_caching([do: body, rescue: rescue_block], cached_value) do
    [
      do: apply_caching(body, cached_value),
      rescue:
        Enum.map(rescue_block, fn {:->, meta, [match, match_body]} ->
          {:->, meta, [match, apply_caching(match_body, cached_value)]}
        end)
    ]
  end

  defp apply_caching(body, nil) do
    body
  end

  defp apply_caching(body, _cached_value) do
    quote do
      result = unquote(body)
      {:cached, result}
    end
  end
end
