-module(hyper_array).
-behaviour(hyper_register).
-export([new/1,
         set/3,
         max_merge/1,
         max_merge/2,
         reduce_precision/2,
         bytes/1,
         register_sum/1,
         register_histogram/1,
         zero_count/1,
         encode_registers/1,
         decode_registers/2,
         compact/1]).


new(P) ->
    M = m(P),
    array:new([{size, M}, {fixed, true}, {default, 0}]).

set(Index, Value, A) ->
    case array:get(Index, A) of
        R when R > Value ->
            A;
        _ ->
            array:set(Index, Value, A)
    end.

fold(F, Acc, A) ->
    array:sparse_foldl(F, Acc, A).

max_merge(As) ->
    [First | Rest] = As,
    lists:foldl(fun max_merge/2, First, Rest).

max_merge(Left, Right) ->
    fold(fun (Index, L, Registers) ->
                 case array:get(Index, Registers) of
                     R when R < L ->
                         set(Index, L, Registers);
                     _ ->
                         Registers
                 end
         end, Right, Left).

reduce_precision(NewP, A) ->
    OldP = trunc(math:log2(array:size(A))),
    ChangeP = OldP - NewP,
    Empty = new(NewP),
    array:sparse_foldl(fun(I, V, Acc) ->
        ChangeV = I rem m(ChangeP),
        set(I bsr ChangeP, changeV(V, ChangeV, ChangeP), Acc)
     end,Empty, A).

bytes(A) ->
    erts_debug:flat_size(A) * 8.

register_sum(A) ->
    array:foldl(fun (_, Value, Sum) ->
                               Sum + math:pow(2, -Value)
                       end, 0, A).

register_histogram(A) ->
    Size = array:size(A),
    P = trunc(math:log2(Size)),
    array:foldl(fun (_, Value, Acc) ->
                    maps:update_with(Value, fun(V) -> V + 1 end , 1, Acc) end,
                    maps:from_keys(lists:seq(0, 64 - P), 0), A).

zero_count(A) ->
    array:foldl(fun (_, 0, Sum) -> Sum + 1;
                    (_, _, Sum) -> Sum
                end, 0, A).

compact(A) ->
    A.

encode_registers(A) ->
    iolist_to_binary(
      lists:reverse(
        array:foldl(fun (_, V, Acc) -> [<<V:8/integer>> | Acc] end,
                    [], A))).

decode_registers(Bytes, P) ->
    do_decode_registers(Bytes, 0, new(P)).

do_decode_registers(<<>>, _, A) ->
    A;
do_decode_registers(<<Value:8/integer, Rest/binary>>, I, A) ->
    NewA = case Value of
               0 -> A;
               N -> array:set(I, N, A)
           end,
    do_decode_registers(Rest, I+1, NewA).

%% INTERNALS

m(P) ->
    trunc(math:pow(2, P)).

changeV(0, _ChangeV, _ChangeP) ->
    0;
changeV(V, 0, ChangeP) ->
    V + ChangeP;
changeV(_V, ChangeV, ChangeP) ->
    leading_zeroes(ChangeV, ChangeP).

leading_zeroes(V, Max) ->
    Max - trunc(math:log2(V)).

