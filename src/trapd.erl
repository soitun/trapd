%%%----------------------------------------------------------------------
%%% File    : trapd.erl
%%% Author  : Ery Lee <ery.lee@gmail.com>
%%% Purpose : opengoss trapd probe
%%% Created : 19 Feb 2008
%%% Updated : 22 Nov 2009
%%% Updated : 25 May. 2012 rewrite
%%% License : http://www.opengoss.com/
%%%
%%% Copyright (C) 2012, www.opengoss.com 
%%%----------------------------------------------------------------------
-module(trapd).

-author('ery.lee@gmail.com').

-import(erlang, [send_after/3]).

-include("trapd.hrl").

-include_lib("elog/include/elog.hrl").

-include_lib("snmp/include/snmp_types.hrl").

%% api
-export([start_link/0,
		status/0,
		emit/1]).

-behaviour(gen_server).

%% gen_server callbacks
-export([init/1, 
        handle_call/3, 
        handle_cast/2, 
        handle_info/2, 
        prioritise_info/2,
        terminate/2, 
        code_change/3]).

%% Manager callback API:
-export([handle_trap/4]).

-define(SERVER, ?MODULE).

-record(state, {channel}).

%%====================================================================
%% startup and stop trapd
%%====================================================================
start_link() ->
    gen_server2:start_link({local, ?SERVER}, ?MODULE, [], []).

status() ->
    gen_server2:call(?SERVER, status).

emit(Event) ->
	gen_server2:cast(?SERVER, {emit, Event}).

init([]) ->
	ets:new(received_trapoid, [set, named_table, protected]),
	{ok, Conn} = amqp:connect(),
    Channel = open(Conn),
    State = #state{channel = Channel},
    ?INFO("trapd is starting...[ok]", []),
    {ok, State}.

open(Conn) ->
	{ok, Channel} = amqp:open_channel(Conn),

	%declare trapd topic
	amqp:topic(Channel, <<"trap">>),

	%declare topic and queue
	amqp:topic(Channel, <<"sys.watch">>),
	{ok, Q} = amqp:queue(Channel, node()),
	amqp:bind(Channel, <<"sys.watch">>, Q, <<"ping">>),
	amqp:consume(Channel, Q),

	%send presence
	Presence = {node(), trapd, available, extlib:appvsn(), <<"trapd is startup.">>},
	amqp:send(Channel, <<"presence">>, term_to_binary(Presence)),

	send_after(10000, self(), heartbeat),
	Channel.

%%--------------------------------------------------------------------
%% Function: %% handle_call(Request, From, State) -> {reply, Reply, State} |
%%                                      {reply, Reply, State, Timeout} |
%%                                      {noreply, State} |
%%                                      {noreply, State, Timeout} |
%%                                      {stop, Reason, Reply, State} |
%%                                      {stop, Reason, State}
%% Description: Handling call messages
%%--------------------------------------------------------------------
handle_call(status, _From, State) ->
    {reply, get(), State};

handle_call(Req, _From, State) ->
    {stop, {error, {badreq, Req}}, State}.

handle_cast({emit, Event}, State) ->
	amqp:send(Channel, <<"event">>, term_to_binary(Event)),
	{noreply, State};

handle_cast(Msg, State) ->
    {stop, {error, {badmsg, Msg}}, State}.

handle_info({raw_trap, RawTrap}, State) ->
	incre(received),
    Sender = RawTrap#raw_trap.addr,
    STrapOid = oid2str(RawTrap#raw_trap.trapoid),
	incre(STrapOid++"@"++Sender),
    log_received(STrapOid, RawTrap),
	?INFO("~s@~s is received.~n", [STrapOid, Sender]),
	trap_parser:parse(STrapOid, RawTrap),

    case trap_filter:filter([{sender, Sender}, {trapoid, STrapOid}]) of
    true ->
		trace("~s@~s is filtered.~n", [STrapOid, Sender]),
        Filtered = get(filtered),
        put(filtered, (Filtered+1));
    false ->
        ?INFO("raw trap received: ~p", [RawTrap]),
        case trap_parser:parse(RawTrap#raw_trap.trapoid, RawTrap) of
        {ok, #trap_event{name = Name, source=Src, summary=Summary} = TrapEvent} -> 
			trace("~s@~s is parsed.~n", [STrapOid, Sender]),
			trace("emit event: name=~p, source=~p, summary=~s~n", [Name, Src, Summary]),
            log_emitted(STrapOid),
            emit_event(TrapEvent#trap_event{trapoid = STrapOid}, State);
        {error, Reason} ->
			trace("~s@~s is dropped: reason=~p~n", [STrapOid, Sender, Reason]),
            Dropped = get(dropped),
            put(dropped, (Dropped+1)),
            log_dropped(STrapOid, RawTrap, Reason),
            ?WARNING("failed to parse trap: ~p, reason: ~p", 
                    [RawTrap#raw_trap.trapoid, Reason])
        end
    end,
    {noreply, State};

handle_info({deliver, <<"ping">>, _, _}, #state{channel = Channel} = State) ->
    Presence = {node(), trapd, available, extlib:appvsn(), <<"alive">>},
    amqp:send(Channel, <<"presence">>, term_to_binary(Presence)),
    {noreply, State};

handle_info({amqp, disconnected}, State) ->
	{noreply, State#state{channel = undefined}};

handle_info({amqp, reconnected, Conn}, State) ->
	{noreply, State#state{channel = open(Conn)}};

handle_info(heartbeat, #state{channel = Channel} = State) ->
    Heartbeat = {node(), <<"alive">>, []},
    amqp:send(Channel, <<"heartbeat">>, term_to_binary(Heartbeat)),
    send_after(10000, self(), heartbeat),
    {noreply, State};

handle_info(Info, State) ->
    {stop, {error, {badinfo, Info}}, State}.

prioritise_info({deliver, <<"ping">>, _, _}, _State) ->
    10;
prioritise_info(heartbeat, _State) ->
    10;
prioritise_info({amqp, disconnected}, _State) ->
    10;
prioritise_info({amqp, reconnected, _}, _State) ->
    10;
prioritise_info(_, _State) ->
    0.

terminate(_Reason, _State) ->
	ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

emit_event(#trap_event{name = Name} = TrapEvent, 
	#state{bdn = Bdn, channel = Channel}) ->
	Key = "trap." ++ atom_to_list(Name),
    Msg = term_to_binary({trap_event, Bdn, TrapEvent}),
    amqp:publish(Channel, <<"trap">>, Msg, Key).

%% ========================================================================
%% SNMP Trapd callback functions
%% ========================================================================
handle_trap(Addr, _Port, SnmpTrap, _Data) ->
	IpAddr = to_ipstr(Addr),
	try new_raw_trap(IpAddr, SnmpTrap) of
		RawTrap -> ?SERVER ! {raw_trap, RawTrap}
	catch
		_:Error -> ?ERROR("~p, ~p ~n ~p ~n ~p", [Addr, Error, 
            erlang:get_stacktrace(), SnmpTrap])
	end.

%%--------------------------------------------------------------------
%%% Internal functions
%%--------------------------------------------------------------------
lookup_vb(Oid, Varbinds) ->
	lists:keysearch(Oid, 2, Varbinds).

delete_vb(Oid, Varbinds) ->
	lists:keydelete(Oid, 2, Varbinds).

new_raw_trap(IpAddr, SnmpTrap) ->
    case SnmpTrap of
	{Enterprise, Generic, Spec, Timestamp, Varbinds} ->
		?DEBUG("v1 trap: ~p, ~p, ~p, ~p", [Enterprise, Generic, Spec, Timestamp]),
		TrapOid = case Generic of
			0 ->[1,3,6,1,6,3,1,1,5,1];
			1 ->[1,3,6,1,6,3,1,1,5,2];
			2 ->[1,3,6,1,6,3,1,1,5,3];
			3 ->[1,3,6,1,6,3,1,1,5,4];
			4 ->[1,3,6,1,6,3,1,1,5,5];
			5 ->[1,3,6,1,6,3,1,1,5,6];
			6 ->lists:append(Enterprise, [0, Spec])
		end,
		?DEBUG("v1 trapoid ~p", [TrapOid]),
        %TODO: FUCK ZTE TRAP BUG
        {TrapOid1, Varbinds3} =
		case lookup_vb(?TRAPOID, Varbinds) of
        {value, TrapOidVb} ->
            Varbinds1 = delete_vb(?TRAPOID, Varbinds),
            Varbinds2 = delete_vb(?UPTIME, Varbinds1),
            {TrapOidVb#varbind.value, Varbinds2};
        false ->
            {TrapOid, Varbinds}
        end,
		#raw_trap{addr=IpAddr, trapoid=TrapOid1, uptime=Timestamp, varbinds=Varbinds3};
	{_ErrorStatus, _ErrorIndex, Varbinds} ->
		?DEBUG("v2 trap received: ~p", [Varbinds]),
		{value, TrapOidVb} = lookup_vb(?TRAPOID, Varbinds),
		Varbinds1 = delete_vb(?TRAPOID, Varbinds),
		{value, UptimeVb} = lookup_vb(?UPTIME, Varbinds1),
		Varbinds2 = delete_vb(?UPTIME, Varbinds1),
		#raw_trap{addr=IpAddr, trapoid=TrapOidVb#varbind.value, 
			uptime=UptimeVb#varbind.value, varbinds=Varbinds2};
	Unknown -> throw({unknow_trap, Unknown})
	end.

to_ipstr(IpTuple) ->
	{A,B,C,D} = IpTuple,
	lists:concat([A, ".", B, ".", C, ".", D]).

oid2str(Oid) ->
    string:join([integer_to_list(I) || I <- Oid], ".").

log_emitted(STrapOid) ->
    case ets:lookup(emitted_trapoid, STrapOid) of
    [] ->
        ets:insert(emitted_trapoid, {STrapOid, 1});
    [{_, Count}] ->
        ets:insert(emitted_trapoid, {STrapOid, Count+1})
    end.

log_received(STrapOid, RawTrap) ->
    Sender = RawTrap#raw_trap.addr,
    Varbinds = RawTrap#raw_trap.varbinds,
    case ets:lookup(received_trapoid, STrapOid) of
    [] ->
        ets:insert(received_trapoid, {STrapOid, 1, Sender, Varbinds});
    [{_, Count, _, _}] ->
        ets:insert(received_trapoid, {STrapOid, Count+1, Sender, Varbinds})
    end.

log_dropped(STrapOid, RawTrap, Reason) ->
    Varbinds = RawTrap#raw_trap.varbinds,
    case ets:lookup(dropped_trapoid, STrapOid) of
    [] ->
        ets:insert(dropped_trapoid, {STrapOid, Reason, Varbinds});
    _ ->
        ignore
    end.

incre(Metric) ->
    case get(Metric) of
	undefined -> put(Metric, 1);
	Val -> put(Metric, Val+1)
	end.
