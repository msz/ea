defmodule Ea do
  @moduledoc """
  The main Ea module.
  """

  @default_backend Application.compile_env!(:ea, :default_backend)
  @time_units [:millisecond, :second, :minute]

  defmacro __using__(opts) do
    validate_ea_opts(opts)

    quote do
      @on_definition Ea
      @before_compile Ea

      @ea_opts unquote(opts)

      Module.register_attribute(__MODULE__, :cached, accumulate: true)
      Module.register_attribute(__MODULE__, :ea_redefined_fun, accumulate: true)
    end
  end

  def __on_definition__(env, kind, name, params, guards, body) do
    {open_fun_name, open_fun_params, open_fun_expiry} =
      Module.get_attribute(env.module, :ea_open_fun, {nil, [], nil})

    expiry =
      if {name, length(params)} == {open_fun_name, length(open_fun_params)} and
           open_fun_expiry != nil do
        open_fun_expiry
      else
        case Module.get_attribute(env.module, :cached) do
          [] ->
            nil

          [cached_attr_value] ->
            Module.delete_attribute(env.module, :cached)
            cached_attr_value_to_expiry(cached_attr_value)

          [_ | _] ->
            raise Ea.MultipleCachedAttributesError.new(env.module, name, length(params))
        end
      end

    attrs = extract_attributes(env.module, body)

    Module.put_attribute(
      env.module,
      :ea_redefined_fun,
      {kind, name, params, guards, body, attrs, expiry}
    )

    unless {name, length(params)} == {open_fun_name, length(open_fun_params)} do
      new_open_fun_expiry = if body == nil, do: expiry, else: nil

      Module.put_attribute(
        env.module,
        :ea_open_fun,
        {name, params, new_open_fun_expiry}
      )
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
      |> Enum.reduce({[], []}, fn {kind, name, params, guard, body, attrs, expiry},
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

        decorated_body = apply_caching(env.module, name, params, body, expiry)

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

  defp validate_ea_opts(opts) do
    validate_time_unit(Keyword.get(opts, :time_unit))
  end

  defp validate_time_unit(nil), do: :ok

  defp validate_time_unit(time_unit) when time_unit in @time_units,
    do: :ok

  defp validate_time_unit(time_unit),
    do: raise(Ea.InvalidOptionValueError.new(time_unit, :time_unit, @time_units))

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
      &match?({_kind, _name, _params, _guards, nil, _attrs, _expiry}, &1)
    )
  end

  defp reject_not_cached_funs(redefined_funs) do
    not_cached_funs =
      redefined_funs
      |> Enum.group_by(
        fn {_kind, name, params, _guards, _body, _attrs, _expiry} ->
          {name, length(params)}
        end,
        fn {_kind, _name, _params, _guards, _body, _attrs, expiry} ->
          expiry
        end
      )
      |> Enum.filter(fn {_name_and_arity, expiries} ->
        Enum.all?(expiries, &is_nil/1)
      end)
      |> Enum.map(fn {name_and_arity, _expiries} -> name_and_arity end)

    Enum.reject(redefined_funs, fn {_kind, name, params, _guards, _body, _attrs, _expiry} ->
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

  defp apply_caching(module, name, params, [do: body], expiry) do
    [do: apply_caching(module, name, params, body, expiry)]
  end

  defp apply_caching(module, name, params, [do: body, rescue: rescue_block], expiry) do
    [
      do: apply_caching(module, name, params, body, expiry),
      rescue:
        Enum.map(rescue_block, fn {:->, meta, [match, match_body]} ->
          {:->, meta, [match, apply_cache_failure_case(module, name, params, match_body, expiry)]}
        end)
    ]
  end

  defp apply_caching(_module, _name, _params, body, nil) do
    body
  end

  defp apply_caching(module, name, params, body, expiry) do
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
          unquote(apply_cache_failure_case(module, name, params, body, expiry))
      end
    end
  end

  def apply_cache_failure_case(module, name, params, body, expiry) do
    quote do
      {backend_module, backend_opts} = unquote(@default_backend)

      result = unquote(body)

      backend_module.put(
        unquote(module),
        unquote(name),
        unquote(params),
        result,
        unquote(expiry),
        backend_opts
      )

      result
    end
  end

  defp strip_default_values(params) do
    Enum.map(params, fn
      {:\\, _, [{param, _, nil}, _default_value]} -> Macro.var(param, nil)
      param -> param
    end)
  end

  defp cached_attr_value_to_expiry(true), do: :never
  defp cached_attr_value_to_expiry(millis) when is_integer(millis) and millis > 0, do: millis

  defp cached_attr_value_to_expiry(invalid),
    do: raise(Ea.InvalidCachedAttributeValueError.new(invalid))
end
