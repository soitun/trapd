%%%----------------------------------------------------------------------
%%% File    : trap_filter.erl
%%% Author  : Ery Lee <ery.lee@gmail.com>
%%% Purpose : Trap filter
%%% Created : 27 May 2012
%%% License : http://www.opengoss.com
%%%
%%% Copyright (C) 2012, www.opengoss.com
%%%----------------------------------------------------------------------
-module(trap_filter).

-author('ery.lee@gmail.com').

-include("trapd.hrl").

-include_lib("elog/include/elog.hrl").

-export([start_link/1, filter/1]).

-record(state, {}).

-behavior(gen_server).

-export([init/1,
        handle_call/3,
        handle_cast/2,
        handle_info/2,
        terminate/2,
        code_change/3]).

start_link(Dir) ->
    gen_server2:start_link({local, ?MODULE}, ?MODULE, [Dir], []).

filter(Trap) ->
	gen_server2:cast(?MODULE, {filter, Trap}).

init([Dir]) ->
	put(filtered, 0),
    ets:new(trap_filter, [set, protected, named_table]),
	LoadFun = fun(File) -> 
		?INFO("load filter file: ~p", [File]),
		case file:consult(filename:join(Dir, File)) of 
		{ok, Filters} ->
			[ets:insert(trap_filter, {Filter}) || Filter <- Filters];
		{error, Reason} ->
			?ERROR("Can't load trap filter file ~p : ~p", [File, Reason])
		end
    end,
    lists:foreach(LoadFun, trapd_misc:list_file(Dir, ".filter")),
	?INFO("~p is starting...[ok]", [?MODULE]),
    {ok, #state{}}.

handle_call(Req, _From, State) ->
    {stop, {error, {badreq, Req}}, State}.

handle_cast({filter, Trap}, State) ->
	case do_filter(ets:first(trap_filter), tokens(Trap)) of
	false ->
		trap_mapper:mapping(Trap);
	true ->
		put(filtered, get(filtered)+1),
		trapd_log:log(filtered, Trap)
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

tokens(#trap2{addr=Addr, trapoid=TrapOid, vars=Vars}) ->
	[{sender, Addr}, {trapoid, TrapOid} | Vars].
	
do_filter('$end_of_table', _) ->
    false;

do_filter(Exp, Tokens) ->
    case prefix_exp:eval(Exp, Tokens) of
    false -> 
        do_filter(ets:next(trap_filter, Exp), Tokens);
    true -> 
        true
    end.

