%%%----------------------------------------------------------------------
%%% File    : trapd_ctl.erl
%%% Author  : Ery Lee <ery.lee@gmail.com>
%%% Purpose : trpad control
%%% Created : 12 Nov. 2010
%%% License : http://www.opengoss.com
%%%
%%% Copyright (C) 2012, www.opengoss.com
%%%----------------------------------------------------------------------
-module(trapd_ctl).

-author('ery.lee@gmail.com').

-include_lib("elog/include/elog.hrl").

-compile(export_all).

status() ->
    {InternalStatus, _ProvidedStatus} = init:get_status(),
    ?PRINT("node ~p is ~p.~n", [node(), InternalStatus]),
    case lists:keysearch(trapd, 1, application:which_applications()) of
    false ->
        ?PRINT("trapd is not running~n", []);
    {value,_Version} ->
        ?PRINT("trapd is running~n", [])
    end.

info() ->
	Stats = [Mod:stats() || Mod <- [trapd, trap_mapper, trap_filter, trap_parser]],
	?PRINT("~p~n", [lists:flatten(Stats)]).

received_trap() ->
    ets_print(received_trap).

emitted_trap() ->
    ets_print(emitted_trap).

dropped_trap() ->
    ets_print(dropped_trap).

filtered_trap() ->
    ets_print(filtered_trap).

ets_print(Tab) ->
    ets_print(Tab, ets:first(Tab)).

ets_print(_Tab, '$end_of_table') ->
    ok;
ets_print(Tab, Key) ->
    ?PRINT("~p~n", [ets:lookup(Tab, Key)]),
    ets_print(Tab, ets:next(Tab, Key)).

