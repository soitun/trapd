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
-export([start_link/0, emit/1]).

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

emit(Event) ->
	gen_server2:cast(?SERVER, {emit, Event}).

init([]) ->
	{ok, Conn} = amqp:connect(),
    Channel = open(Conn),
    ?INFO("trapd is starting...[ok]", []),
    {ok, #state{channel = Channel}}.

open(Conn) ->
	{ok, Channel} = amqp:open_channel(Conn),
	{ok, Q} = amqp:queue(Channel, node()),

	%declare trapd topic
	amqp:topic(Channel, <<"oss.event">>),
	%declare topic and queue
	amqp:topic(Channel, <<"sys.watch">>),
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
handle_call(Req, _From, State) ->
    {stop, {error, {badreq, Req}}, State}.

handle_cast({emit, #event{name = Name} = Event}, #state{channel = Chan} = State) ->
	NewEvent = enrich(Event),
	trapd_log:log(emitted, NewEvent),
	Key = "event." ++ atom_to_list(Name),
	amqp:publish(Chan, <<"oss.event">>, term_to_binary(NewEvent), Key),
	{noreply, State};

handle_cast(Msg, State) ->
    {stop, {error, {badmsg, Msg}}, State}.

handle_info({trap, Trap}, State) ->
	trapd_log:log(received, Trap),
	trap_parser:parse(Trap),
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


%% ========================================================================
%% SNMP Trapd callback functions
%% ========================================================================
handle_trap(Addr, _Port, SnmpTrap, _Data) ->
	try new_trap(trapd_misc:ipaddr(Addr), SnmpTrap) of
		Trap -> ?SERVER ! {trap, Trap}
	catch
		_:Error -> ?ERROR("~p, ~p ~n ~p ~n ~p", [Addr, Error, 
            erlang:get_stacktrace(), SnmpTrap])
	end.

%%--------------------------------------------------------------------
%%% Internal functions
%%--------------------------------------------------------------------

%add timestamp, manager, from
enrich(Event) -> 
	Event#event{timestamp = extbif:timestamp(),
				manager = node(),
				from = trap}.

lookup_vb(Oid, Varbinds) ->
	lists:keysearch(Oid, 2, Varbinds).

delete_vb(Oid, Varbinds) ->
	lists:keydelete(Oid, 2, Varbinds).

new_trap(IpAddr, SnmpTrap) ->
    case SnmpTrap of
	{Enterprise, Generic, Spec, UpTime, Varbinds} ->
		?DEBUG("v1 trap: ~p, ~p, ~p, ~p ~p", [Enterprise, Generic, Spec, UpTime, Varbinds]),
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
		#trap2{addr=IpAddr,
			  trapoid=mib_oid:to_str(TrapOid1),
			  uptime=UpTime,
			  varbinds=Varbinds3};
	{_ErrorStatus, _ErrorIndex, Varbinds} ->
		?DEBUG("v2 trap received: ~p", [Varbinds]),
		{value, TrapOidVb} = lookup_vb(?TRAPOID, Varbinds),
		Varbinds1 = delete_vb(?TRAPOID, Varbinds),
		{value, UptimeVb} = lookup_vb(?UPTIME, Varbinds1),
		Varbinds2 = delete_vb(?UPTIME, Varbinds1),
		#trap2{addr=IpAddr,
			  trapoid=mib_oid:to_str(TrapOidVb#varbind.value), 
			  uptime=UptimeVb#varbind.value,
			  varbinds=Varbinds2};
	Unknown -> 
		throw({unknow_trap, Unknown})
	end.

