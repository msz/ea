defmodule Ea do
  @moduledoc """
  The main Ea module.
  """

  @default_backend Application.compile_env!(:ea, :default_backend)

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

  def __on_definition__(env, kind, name, params, guards, body) do
    {open_fun_name, open_fun_params, open_fun_cached_value} =
      Module.get_attribute(env.module, :ea_open_fun, {nil, [], nil})

    cached_value =
      if {name, length(params)} == {open_fun_name, length(open_fun_params)} and
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
                    length(params)
                  }. Please only define one."
        end
      end

    attrs = extract_attributes(env.module, body)

    Module.put_attribute(
      env.module,
      :ea_redefined_fun,
      {kind, name, params, guards, body, attrs, cached_value}
    )

    unless {name, length(params)} == {open_fun_name, length(open_fun_params)} do
      new_open_fun_cached_value = if body == nil, do: cached_value, else: nil
      Module.put_attribute(env.module, :ea_open_fun, {name, params, new_open_fun_cached_value})
    end
  end

  defmacro __before_compile__(env) do
    Module.delete_attribute(env.module, :ea_open_fun)
    redefined_funs = env.module |> Module.get_attribute(:ea_redefined_fun) |> Enum.reverse()
    Module.delete_attribute(env.module, :ea_redefined_fun)

    {_, funs_with_caching} =
      redefined_funs
      # We don't have anything to redefine for empty clauses
      |> reject_empty_clauses()
      # No need to redefine functions where no clauses have any caching
      |> reject_not_cached_funs()
      |> Enum.reduce({[], []}, fn {kind, name, params, guard, body, attrs, cached_value},
                                  {prev_funs, all} ->
        override_clause =
          params
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

        # Even if some params are unused, they will be used as part of the
        # caching mechanism, so we need to adjust that.
        params = turn_unused_params_into_used(params)

        decorated_body = apply_caching(env.module, name, params, body, cached_value)

        def_clause =
          case guard do
            [] ->
              quote do
                unquote(kind)(unquote(name)(unquote_splicing(params)), unquote(decorated_body))
              end

            _ ->
              quote do
                unquote(kind)(
                  unquote(name)(unquote_splicing(params)) when unquote_splicing(guard),
                  unquote(decorated_body)
                )
              end
          end

        arity = length(params)

        if {name, arity} in prev_funs do
          {prev_funs, [def_clause | attr_expressions ++ all]}
        else
          {[{name, arity} | prev_funs], [def_clause, override_clause | attr_expressions ++ all]}
        end
      end)

    Enum.reverse(funs_with_caching)
  end

  defp turn_unused_params_into_used(params) do
    Enum.map(params, fn
      {name, meta, val} ->
        new_name =
          name
          |> Atom.to_string()
          |> String.split("_")
          |> strip_empty_strings_from_list_head()
          |> Enum.join()
          |> String.to_atom()

        {new_name, meta, val}

      literal_value ->
        literal_value
    end)
  end

  defp strip_empty_strings_from_list_head(["" | rest]) do
    strip_empty_strings_from_list_head(rest)
  end

  defp strip_empty_strings_from_list_head(other) do
    other
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
      &match?({_kind, _name, _params, _guards, nil, _attrs, _cached_value}, &1)
    )
  end

  defp reject_not_cached_funs(redefined_funs) do
    not_cached_funs =
      redefined_funs
      |> Enum.group_by(
        fn {_kind, name, params, _guards, _body, _attrs, _cached_value} ->
          {name, length(params)}
        end,
        fn {_kind, _name, _params, _guards, _body, _attrs, cached_value} ->
          cached_value
        end
      )
      |> Enum.filter(fn {_name_and_arity, cached_values} ->
        Enum.all?(cached_values, &is_nil/1)
      end)
      |> Enum.map(fn {name_and_arity, _cached_values} -> name_and_arity end)

    Enum.reject(redefined_funs, fn {_kind, name, params, _guards, _body, _attrs, _cached_value} ->
      {name, length(params)} in not_cached_funs
    end)
  end

  defp implied_arities(params) do
    arity = Enum.count(params)

    default_count =
      params
      |> Enum.filter(fn
        {:\\, _, _} -> true
        _ -> false
      end)
      |> Enum.count()

    :lists.seq(arity, arity - default_count, -1)
  end

  defp apply_caching(module, name, params, [do: body], cached_value) do
    [do: apply_caching(module, name, params, body, cached_value)]
  end

  defp apply_caching(module, name, params, [do: body, rescue: rescue_block], cached_value) do
    [
      do: apply_caching(module, name, params, body, cached_value),
      rescue:
        Enum.map(rescue_block, fn {:->, meta, [match, match_body]} ->
          {:->, meta,
           [match, apply_cache_failure_case(module, name, params, match_body, cached_value)]}
        end)
    ]
  end

  defp apply_caching(_module, _name, _params, body, nil) do
    body
  end

  defp apply_caching(module, name, params, body, true) do
    # We will refer to these params in the body, but this comes from the function
    # head and might contain a default value. We want to refer to a `param \\ :default_value`
    # as just `param` in the body.
    params = strip_default_values(params)

    quote do
      {backend_module, backend_opts} = unquote(@default_backend)

      case backend_module.get(unquote(module), unquote(name), unquote(params), backend_opts) do
        {:ok, value} ->
          value

        {:error, :no_value} ->
          unquote(apply_cache_failure_case(module, name, params, body, true))
      end
    end
  end

  def apply_cache_failure_case(module, name, params, body, _cache_value) do
    quote do
      {backend_module, backend_opts} = unquote(@default_backend)

      result = unquote(body)
      backend_module.put(unquote(module), unquote(name), unquote(params), result, backend_opts)
      result
    end
  end

  defp strip_default_values(params) do
    Enum.map(params, fn
      {:\\, _, [{param, _, nil}, _default_value]} -> Macro.var(param, nil)
      param -> param
    end)
  end
end
