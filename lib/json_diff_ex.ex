defmodule JsonDiffEx do
  @moduledoc """
  This is the documentation of JsonDiffEx.

  There are no runtime dependencies and it should be easy
  to use.

  You can use the javascript library
  [jsondiffpatch](https://github.com/benjamine/jsondiffpatch)
  with it since it get's it's diff format from it.

  It contains both diff and patch

  ## Example

  ### Diff

  Simple example:

      iex> JsonDiffEx.diff %{"test" => 1}, %{"test" => 2}
      %{"test" => [1, 2]}

  Now with list:

      iex> JsonDiffEx.diff %{"test" => [1,2,3]}, %{"test" => [2,3]}
      %{"test" => %{"_0" => [1, 0, 0], "_t" => "a"}}

  Now with a map in the map:

      iex> JsonDiffEx.diff %{"test" => %{"1": 1}}, %{"test" => %{"1": 2}}
      %{"test" => %{"1": [1, 2]}}

  Now with a map in an list in the map:

      iex> JsonDiffEx.diff %{"test" => [%{"1": 1}]}, %{"test" => [%{"1": 2}]}
      %{"test" => %{"0" => %{"1": [1, 2]}, "_t" => "a"}}

  ### Patch

  Simple example of a patch:

      iex> JsonDiffEx.patch %{"test" => 1}, %{"test" => [1, 2]}
      %{"test" => 2}

  Now a patch with list:

      iex> JsonDiffEx.patch %{"test" => [1,2,3]},
      ...> %{"test" => %{"_0" => [1, 0, 0], "_t" => "a"}}
      %{"test" => [2,3]}

  Now a patch with a map in the map:

      iex> JsonDiffEx.patch %{"test" => %{"1": 1}}, %{"test" => %{"1": [1, 2]}}
      %{"test" => %{"1": 2}}

  Now with a map in an list in the map:

      iex> JsonDiffEx.patch %{"test" => [%{"1": 1}]},
      ...> %{"test" => %{"0" => %{"1": [1, 2]}, "_t" => "a"}}
      %{"test" => [%{"1": 2}]}

  """

  @spec split_underscore({binary, list}) :: boolean
  defp split_underscore({<<"_", _>>, [value, 0, 0]}) when is_map(value) do
    false
  end

  defp split_underscore(_) do
    true
  end

  @spec all_checked(list, map) :: list
  defp all_checked([], deleted_map) do
    Map.to_list(deleted_map)
  end

  defp all_checked([head | tail], deleted_map) do
    case head do
      {i, [value]} when is_map(value) ->
        neg_i = "_" <> i
        case Map.fetch(deleted_map, neg_i) do
          {:ok, [value2, 0, 0]} -> [{i, do_diff(value2, value)} | all_checked(tail, Map.delete(deleted_map, neg_i))]
          _ -> [head | all_checked(tail, deleted_map)]
        end
      _ -> [head | all_checked(tail, deleted_map)]
    end
  end

  @spec do_diff(list, list) :: map
  defp do_diff(l1, l2) when is_list(l1) and is_list(l2) do
    map1 = l1 |> Enum.with_index |> Enum.into(%{})
    map2 = l2 |> Enum.with_index |> Enum.into(%{})
    {rest_map2, new_list} = Enum.reduce(map1, {map2, %{}},
      fn({k, i1}, {new_map2, acc}) ->
        case Map.get(new_map2, k) do
          nil -> {new_map2, Map.put(acc, "_" <> <<i1 + 48>>, [k, 0, 0])}
          ^i1 -> {Map.delete(new_map2, k), acc}
          i2 -> {Map.delete(new_map2, k),
                 Map.put(acc, "_" <> <<i1 + 48>>, ["", i2, 3])}
        end
      end
    )
    new_list2 = Enum.reduce(rest_map2, new_list,
      fn({k2, i3}, acc) ->
        Map.put(acc, <<i3 + 48>>, [k2])
      end
    )
    {_shift, new_list3} = Enum.reduce(new_list2, {0, new_list2}, fn
      ({_ , [_, 0, 0]}, {shift_length, acc}) -> {shift_length + 1, acc}
      ({_, [_]}, {shift_length, acc}) -> {shift_length - 1, acc}
      ({<<"_", x>>, ["", y, 3]}, {shift_length, acc}) when (x - 48) - y === shift_length ->
        {shift_length, Map.delete(acc, <<"_", x>>)}
      (_, {shift_length, acc}) -> {shift_length, acc}
      end
    )
    case Enum.split_while(new_list3, &split_underscore/1) do
      {[], []} -> new_list3
      {_, []} -> new_list3
      {check, deleted} ->
        deleted_map = Enum.into(deleted, %{})
        all_checked(check, deleted_map)
    end
    |> Enum.concat([{"_t", "a"}])
    |> Enum.into(%{})
  end

  @spec do_diff(binary | integer | float, binary | integer | float) :: map
  defp do_diff(i1, i2) when not (is_list(i1) and is_list(i2))
                    and not (is_map(i1) and is_map(i2)) do
    case i1 === i2 do
      true -> nil
      false -> [i1, i2]
    end
  end

  @spec do_diff(map, map) :: map
  defp do_diff(map1, map2) when is_map(map1) and is_map(map2) do
    keys_non_uniq = Enum.concat(Map.keys(map1), Map.keys(map2))
    keys_non_uniq
    |> Enum.uniq
    |> Enum.map(fn(k) ->
      case Map.has_key?(map1, k) do
        true ->
          case Map.has_key?(map2, k) do
            true -> {k, do_diff(Map.get(map1, k), Map.get(map2, k))}
            false -> {k, [Map.get(map1, k), 0, 0]}
          end
        false -> {k, [Map.get(map2, k)]}
      end
    end)
    |> Enum.filter(fn({_,v}) -> v !== nil end)
    |> Enum.into(%{})
  end

  @doc """
  Diff only supports Elixir's Map format but they can contain,
  lists, other maps and anything that can be compared like strings,
  numbers and boolean.
  """
  @spec diff(map, map) :: map
  def diff(map1, map2) when is_map(map1) and is_map(map2) do
    do_diff(map1, map2)
  end

  defp do_patch_shift(list1, <<index1>>, value1) do
    list1
    |> Enum.map(fn({<<k>>,v}) ->
      case k >= index1 do
        true ->  {<<k + 1>>, v}
        false -> {<<k>>, v}
      end
    end)
    |> Enum.into([{<<index1>>, value1}])
    |> Enum.into(%{})
  end

  defp do_patch_list(list1, new_list1, diff1, i) do
    si = <<i + 48>>
    {list2, new_list2, has_changed1, has_deleted1} =
      case Map.get(diff1, "_" <> si, false) do
        [_, 0, 0] -> {Map.delete(list1, si), new_list1, true, true}
        ["", new_i, 3] ->
          {
            list1,
            Map.put(new_list1, <<new_i + 48>>, Map.get(list1, si)), true, false
          }
        false -> {list1, new_list1, false, false}
      end
    diff2 = Map.delete(diff1, "_" <> si)
    {list3, new_list3, has_changed2} = case Map.get(diff2, si, false) do
      [new_value] -> case has_deleted1 do
        true -> {list2, Map.put(new_list2, si, new_value), true}
        false ->
          {
            do_patch_shift(list2, si, new_value),
            Map.put(new_list2, si, new_value),
            true
          }
      end
      new_diff when is_map(new_diff) ->
        new_value = list2 |> Map.fetch!(si)
        |> do_patch(new_diff)
        {list2, Map.put(new_list2, si, new_value), true}
      false ->
        has_keys1 = {Map.has_key?(new_list2, si), Map.has_key?(list2, si)}
        case has_keys1 do
          {false, true} ->
            {list2, Map.put(new_list2, si, Map.get(list2, si)), true}
          {true, _} -> {list2, new_list2, true}
          {false, false} -> {list2, new_list2, false}
        end
    end
    diff3 = Map.delete(diff2, si)
    case map_size(diff3) === 0 and not (has_changed1 or has_changed2) do
      true -> new_list3
        |> Enum.map(fn({_k, v}) -> v end)
      false -> do_patch_list(list3, new_list3, diff3, i + 1)
    end
  end

  defp do_patch(map1, diff1) do
    diff2 = diff1 |> Enum.map(fn({k, v}) ->
      case v do
        [new_value] -> {k, new_value}
        _ -> {k, v}
      end
    end)
    |> Enum.into(%{})
    Map.merge(map1, diff2, fn(_k, v_map, v_diff) ->
      case v_diff do
        [^v_map, new_value] -> new_value
        new_map when is_map(new_map) ->
          case Map.get(new_map, "_t", false) === "a" do
            true ->
              v_diff2 = Map.delete(v_diff, "_t")
              v_map
              |> Enum.with_index
              |> Enum.map(fn({v, k}) -> {<<k + 48>>,v} end)
              |> Enum.into(%{})
              |> do_patch_list(%{}, v_diff2, 0)
            false -> do_patch(v_map, v_diff)
          end
      end
    end)
  end

  @doc """
  Patch only supports Elixir's Map format.
  """
  @spec patch(map, map) :: map
  def patch(map1, diff1) when is_map(map1) and is_map(diff1) do
    do_patch(map1, diff1)
  end
end
