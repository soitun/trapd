%%%----------------------------------------------------------------------
%%% File    : trap_mapper.erl
%%% Author  : Ery Lee <ery.lee@gmail.com>
%%% Purpose : Trap Mapper
%%% Created : 26 May 2012
%%% License : http://www.opengoss.com
%%%
%%% Copyright (C) 2012, www.monit.cn
%%%----------------------------------------------------------------------
-module(trap_mapper).

-author('ery.lee@gmail.com').

-include("trapd.hrl").

-include_lib("elog/include/elog.hrl").

-include_lib("snmp/include/snmp_types.hrl").

-export([start_link/1, mapping/2]).

-behavior(gen_server).

-export([init/1, 
        handle_call/3, 
        handle_cast/2, 
        handle_info/2, 
        terminate/2,
        code_change/3]).

%%--------------------------------------------------------------------
%% Function: start_link() -> {ok,Pid} | ignore | {error,Error}
%% Description: Starts the server
%%--------------------------------------------------------------------
start_link(Dir) ->
    gen_server2:start_link({local, ?MODULE}, ?MODULE, [Dir], []).

mapping(TrapOid, Tokens) ->
    gen_server2:cast(?MODULE, {mapping, TrapOid, Tokens}).

%%--------------------------------------------------------------------
%% Function: init(Args) -> {ok, State} |
%%                         {ok, State, Timeout} |
%%                         ignore               |
%%                         {stop, Reason}
%% Description: Initiates the server
%%--------------------------------------------------------------------
init([Dir]) ->
    {ok, MapperFiles} = file:list_dir(Dir),
    ets:new(trap_mapper, [set, named_table]),
    lists:foreach(fun(File) -> 
        case lists:suffix(".mapper", File) of
        true -> 
            ?INFO("load mapper file: ~p", [File]),
            case file:consult(filename:join(Dir, File)) of 
            {ok, Terms} ->
                lists:foreach(fun({mapper, Oid, Name, Attrs}) -> 
					ets:insert(trap_mapper, {Oid, Name, Attrs})
                end, Terms);
            {error, Reason} ->
                ?ERROR("Can't load trap mapper file ~p : ~p", [File, Reason])
            end;
        false ->
            ignore
        end
    end, MapperFiles),
    {ok, state}.

handle_call(Req, _From, State) ->
    {stop, {error, {badreq, Req}}, State}.

handle_cast({mapping, TrapOid, Tokens}, State) ->
    case ets:lookup(trap_mapper, TrapOid) of
    [Mapper] ->
		Event = mapping(Mapper, Tokens),
		trapd:emit(Event);
    [] -> 
        ?WARNING("no mapper for: ~p", [TrapOid]),
    end;
	{noreply, State};

handle_cast(Msg, State) ->
    {stop, {error, {badmsg, Msg}}, State}.

handle_info(Info, State) ->
    {stop, {error, {badinfo, Info}}, State}.

terminate(_Reason, _State) ->
	ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

mapping({Name, Attrs}, Tokens) ->
	{Name, attr_map(Attrs, Tokens)}.

attr_map(Attrs, Tokens) ->
	attr_map(Attrs, Tokens, []).

attr_map([], _Tokens, Acc) ->
	Acc;

attr_map([{severity, Severity} | Attrs], Tokens, Acc) ->
	attr_map(Attrs, Tokens, [{severity, Severity}|Acc]);

attra_map([{summary, SumDef} | Attrs], Tokens, Acc) ->
	Summary = varstr:eval(SumDef, Tokens),
	attr_map(Attrs, Tokens, [{summary, Summary}|Acc]);

attra_map([{event_key, KeyDef} | Attrs], Tokens, Acc) ->
	EventKey = varstr:eval(KeyDef, Tokens),
	attr_map(Attrs, Tokens, [{event_key, EventKey}|Acc]);

