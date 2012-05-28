%%%----------------------------------------------------------------------
%%% File    : trapd_log.erl
%%% Author  : Ery Lee <ery.lee@gmail.com>
%%% Purpose : trapd log
%%% Updated : 28 May 2012
%%% License : http://www.opengoss.com/
%%%
%%% Copyright (C) 2012, www.opengoss.com 
%%%----------------------------------------------------------------------
-module(trapd_log).

-author('ery.lee@gmail.com').

-include("trapd.hrl").

-include_lib("elog/include/elog.hrl").

-include_lib("snmp/include/snmp_types.hrl").

-export([start_link/0,
		log/2]).

-behaviour(gen_server).

-export([init/1, 
        handle_call/3, 
        handle_cast/2, 
        handle_info/2, 
        terminate/2, 
        code_change/3]).

-define(SERVER, ?MODULE).

start_link() ->
    gen_server2:start_link({local, ?MODULE}, ?MODULE, [], []).

log(Type, Data) ->
	gen_server2:cast(?MODULE, {log, Type, Data}).

init([]) ->
    ets:new(received_trap, [set, named_table, protected]),
    ets:new(emitted_trap, [set, named_table, protected]),
    ets:new(filtered_trap, [set, named_table, protected]),
    ets:new(dropped_trap, [set, named_table, protected]),
    ?INFO("~p is starting...[ok]", [?MODULE]),
    {ok, state}.

handle_call(Req, _From, State) ->
    {stop, {error, {badreq, Req}}, State}.

handle_cast({log, received, Trap}, State) ->
	#trap2{addr = Addr, trapoid = TrapOid, varbinds = Varbinds} = Trap,
	?INFO("~s@~s is received.~n", [TrapOid, Addr]),
	TrapKey = lists:concat([TrapOid, "@", Addr]),
    case ets:lookup(received_trap, TrapKey) of
    [{_, Count, _}] ->
        ets:insert(received_trap, {TrapKey, Count+1, Varbinds});
    [] ->
        ets:insert(received_trap, {TrapKey, 1, Varbinds})
    end,
	{noreply, State};

handle_cast({log, filtered, Trap}, State) ->
	#trap2{addr = Addr, trapoid = TrapOid} = Trap,
	TrapKey = lists:concat([TrapOid, "@", Addr]),
	?INFO("~s is filtered.", [TrapKey]),
    case ets:lookup(filtered_trap, TrapKey) of
    [{_, Count, _}] ->
        ets:insert(filtered_trap, {TrapKey, Count+1});
    [] ->
        ets:insert(filtered_trap, {TrapKey, 1})
    end,
	{noreply, State};

handle_cast({log, dropped, {Reason, Trap}}, State) ->
    #trap2{addr=Addr, trapoid=TrapOid, varbinds=Varbinds} = Trap,
	TrapKey = lists:concat([TrapOid, "@", Addr]),
	?INFO("~s is dropped.~n", [TrapKey]),
    ets:insert(dropped_trap, {TrapKey, Reason, Varbinds}),
	{noreply, State};

handle_cast({log, emitted, #trap2{addr = Addr, trapoid = TrapOid}}, State) ->
	TrapKey = lists:concat([TrapOid, "@", Addr]),
	?INFO("~s is emitted.~n", [TrapKey]),
    case ets:lookup(emitted_trap, TrapKey) of
    [{_, Count}] ->
        ets:insert(emitted_trap, {TrapKey, Count+1});
    [] ->
        ets:insert(emitted_trap, {TrapKey, 1})
    end,
	{noreply, State};

handle_cast(Msg, State) ->
    {stop, {error, {badmsg, Msg}}, State}.

handle_info(Info, State) ->
    {stop, {error, {badinfo, Info}}, State}.

terminate(_Reason, _State) ->
	ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

