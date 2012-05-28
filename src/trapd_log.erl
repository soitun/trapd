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

-export([start_link/0, stats/0, log/2]).

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

stats() ->
	gen_server2:call(?MODULE, stats).

log(Type, Data) ->
	gen_server2:cast(?MODULE, {log, Type, Data}).

init([]) ->
	[put(M, 0) || M <- [received, emitted, dropped]],
    ets:new(received_trap, [set, named_table, protected]),
    ets:new(emitted_trap, [set, named_table, protected]),
    ets:new(dropped_trap, [set, named_table, protected]),
    ?INFO("~p is starting...[ok]", [?MODULE]),
    {ok, state}.

handle_call(stats, _From, State) ->
    Reply = [{dropped, get(dropped)},
			{received, get(received)},
			{filtered, get(filtered)}],
    {reply, Reply, State};

handle_call(stop, _From, State) ->
    {stop, normal, ok, State};

handle_call(Req, _From, State) ->
    {stop, {error, {badreq, Req}}, State}.

handle_cast({log, received, Trap}, State) ->
	put(received, get(received) + 1),
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

handle_cast({log, emitted, TrapOid}, State) ->
	put(emitted, get(emitted) + 1),
    case ets:lookup(emitted_trap, TrapOid) of
    [{_, Count}] ->
        ets:insert(emitted_trap, {TrapOid, Count+1});
    [] ->
        ets:insert(emitted_trap, {TrapOid, 1})
    end,
	{noreply, State};

handle_cast({log, filtered, Trap}, State) ->
	put(filtered, get(filtered) + 1),
	%trace("~s@~s is filtered.~n", [STrapOid, Sender]),
	{noreply, State};

handle_cast({log, dropped, {Reason, Trap}}, State) ->
	put(dropped, get(dropped) + 1),
    #trap2{addr=Addr, trapoid=TrapOid, varbinds=Varbinds} = Trap,
	TrapKey = lists:concat([TrapOid, "@", Addr]),
    ets:insert(dropped_trap, {TrapKey, Reason, Varbinds}),
	{noreply, State};

handle_cast(Msg, State) ->
    {stop, {error, {badmsg, Msg}}, State}.

handle_info(Info, State) ->
    {stop, {error, {badinfo, Info}}, State}.

terminate(_Reason, _State) ->
	ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.


