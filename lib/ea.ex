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
    Module.delete_attribute(env.module, :ea_open_fun)
    redefined_funs = env.module |> Module.get_attribute(:ea_redefined_fun) |> Enum.reverse()
    Module.delete_attribute(env.module, :ea_redefined_fun)

    {_, funs_with_caching} =
      redefined_funs
      # We don't have anything to redefine for empty clauses
      |> reject_empty_clauses()
      # No need to redefine functions where no clauses have any caching
      |> reject_not_cached_funs()
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

        # Even if some args are unused, they will be used as part of the
        # caching mechanism, so we need to adjust that.
        args = turn_unused_args_into_used(args)

        decorated_body = apply_caching(env.module, name, args, body, cached_value)

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

  defp turn_unused_args_into_used(args) do
    Enum.map(args, fn
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
      &match?({_kind, _name, _args, _guards, nil, _attrs, _cached_value}, &1)
    )
  end

  defp reject_not_cached_funs(redefined_funs) do
    not_cached_funs =
      redefined_funs
      |> Enum.group_by(
        fn {_kind, name, args, _guards, _body, _attrs, _cached_value} ->
          {name, length(args)}
        end,
        fn {_kind, _name, _args, _guards, _body, _attrs, cached_value} ->
          cached_value
        end
      )
      |> Enum.filter(fn {_name_and_arity, cached_values} ->
        Enum.all?(cached_values, &is_nil/1)
      end)
      |> Enum.map(fn {name_and_arity, _cached_values} -> name_and_arity end)

    Enum.reject(redefined_funs, fn {_kind, name, args, _guards, _body, _attrs, _cached_value} ->
      {name, length(args)} in not_cached_funs
    end)
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

  defp apply_caching(module, name, args, [do: body], cached_value) do
    [do: apply_caching(module, name, args, body, cached_value)]
  end

  defp apply_caching(module, name, args, [do: body, rescue: rescue_block], cached_value) do
    [
      do: apply_caching(module, name, args, body, cached_value),
      rescue:
        Enum.map(rescue_block, fn {:->, meta, [match, match_body]} ->
          {:->, meta,
           [match, apply_cache_failure_case(module, name, args, match_body, cached_value)]}
        end)
    ]
  end

  defp apply_caching(_module, _name, _args, body, nil) do
    body
  end

  defp apply_caching(module, name, args, body, true) do
    # We will refer to these args in the body, but this comes from the function
    # head and might contain a default value. We want to refer to a `arg \\ :default_value`
    # as just `arg` in the body.
    args = strip_default_values(args)

    quote do
      {backend_module, backend_opts} = unquote(@default_backend)

      case backend_module.get(unquote(module), unquote(name), unquote(args), backend_opts) do
        {:ok, value} ->
          value

        {:error, :no_value} ->
          unquote(apply_cache_failure_case(module, name, args, body, true))
      end
    end
  end

  def apply_cache_failure_case(module, name, args, body, _cache_value) do
    quote do
      {backend_module, backend_opts} = unquote(@default_backend)

      result = unquote(body)
      backend_module.put(unquote(module), unquote(name), unquote(args), result, backend_opts)
      result
    end
  end

  defp strip_default_values(args) do
    Enum.map(args, fn
      {:\\, _, [{arg, _, nil}, _default_value]} -> Macro.var(arg, nil)
      arg -> arg
    end)
  end
end
