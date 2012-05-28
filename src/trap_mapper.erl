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

-export([start_link/1,
		lookup/1,
		mapping/1]).

-behavior(gen_server).

-export([init/1, 
        handle_call/3, 
        handle_cast/2, 
        handle_info/2, 
        terminate/2,
        code_change/3]).

-record(mapper, {trapoid, rule, name, attrs}).

start_link(Dir) ->
    gen_server2:start_link({local, ?MODULE}, ?MODULE, [Dir], []).

lookup(Oid) ->
	ets:lookup(trap_mapper, Oid).

mapping(Trap) ->
    gen_server2:cast(?MODULE, {mapping, Trap}).

init([Dir]) ->
	put(mapped, 0),
    ets:new(trap_mapper, [bag, protected, named_table, {keypos, 2}]),
    LoadFun = fun(File) -> 
		?INFO("load mapper file: ~p", [File]),
		case file:consult(filename:join(Dir, File)) of 
		{ok, Terms} ->
			lists:foreach(fun store/1, Terms);
		{error, Reason} ->
			?ERROR("Can't load trap mapper file ~p : ~p", [File, Reason])
		end
    end,
	lists:foreach(LoadFun, trapd_misc:list_file(Dir, ".mapper")),
	?INFO("~p is starting...[ok]", [?MODULE]),
    {ok, state}.

store({mapper, Oid, Name, Attrs}) -> 
	ets:insert(trap_mapper, #mapper{trapoid=Oid, name=Name, attrs=Attrs});

store({mapper, Oid, Rule, Name, Attrs}) ->
	RuleExp = prefix_exp:parse(Rule),
	ets:insert(trap_mapper, #mapper{trapoid=Oid, rule=RuleExp, name=Name, attrs=Attrs}).

handle_call(Req, _From, State) ->
    {stop, {error, {badreq, Req}}, State}.

handle_cast({mapping, #trap2{trapoid = TrapOid} = Trap}, State) ->
    Mappers = ets:lookup(trap_mapper, TrapOid),
	case find_mapper(Trap, Mappers) of
	false ->
		trapd_log:log(dropped, {no_mapper, Trap});
	{ok, Mapper} ->
		trapd:emit(mapping(Mapper, Trap))
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

find_mapper(_, []) ->
	false;
find_mapper(#trap2{trapoid = TrapOid, vars = Vars}, Mappers) ->
	Matched = 
	lists:filter(fun(#mapper{rule=Rule}) -> 
		(Rule == undefined) or prefix_exp:eval(Rule, Vars)
	end, Mappers),
	case Matched of
	[] -> 
		false;
	[Mapper] -> 
		{ok, Mapper};
	[Mapper|_] -> 
		?WARNING("more than one mapper for ~p", [TrapOid]),
		{ok, Mapper}
	end.

mapping(#mapper{name=Name, attrs=Attrs}, #trap2{addr = Addr, vars = Vars}) ->
	Event = #event{name = Name, sender = Addr, vars = Vars},
	attr_map(Attrs, Vars, Event).

attr_map([], _Vars, Event) ->
	Event;

attr_map([{severity, Severity}|Attrs], Vars, Event) ->
	attr_map(Attrs, Vars, Event#event{severity = Severity});

attr_map([{source, Def}|Attrs], Vars, Event) ->
	Source = varstr:eval(Def, Vars),
	attr_map(Attrs, Vars, Event#event{source = Source});

attr_map([{evtkey, Def} | Attrs], Vars, Event) ->
	EvtKey = varstr:eval(Def, Vars),
	attr_map(Attrs, Vars, Event#event{evtkey = EvtKey});

attr_map([{summary, Def} | Attrs], Vars, Event) ->
	Summary = varstr:eval(Def, Vars),
	attr_map(Attrs, Vars, Event#event{summary = Summary});

attr_map([Attr | Attrs], Vars, Event) ->
	?WARNING("ignore ~p", [Attr]),
	attr_map(Attrs, Vars, Event).

