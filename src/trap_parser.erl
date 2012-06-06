%%%----------------------------------------------------------------------
%%% File    : trap_parser.erl
%%% Author  : Ery Lee <ery.lee@gmail.com>
%%% Purpose : Trap Parser
%%% Created : 26 Jan 2010
%%% Created : 27 May 2012
%%% License : http://www.opengoss.com
%%%
%%% Copyright (C) 2012, www.opengoss.com
%%%----------------------------------------------------------------------
-module(trap_parser).

-author('ery.lee@gmail.com').

-include("trapd.hrl").

-include_lib("elog/include/elog.hrl").

-include_lib("snmp/include/snmp_types.hrl").

-export([start_link/1,
		stats/0,
		parse/1]).

-behavior(gen_server).

-export([init/1, 
        handle_call/3, 
		prioritise_call/3,
        handle_cast/2, 
        handle_info/2, 
        terminate/2,
        code_change/3]).

start_link(Dir) ->
    gen_server2:start_link({local, ?MODULE}, ?MODULE, [Dir], []).

stats() ->
	gen_server2:call(?MODULE, stats).

parse(Trap) ->
    gen_server2:cast(?MODULE, {parse, Trap}).

init([Dir]) ->
	put(parsed, 0),
    ets:new(trap_vardef, [set, named_table]),
    ets:new(trap_parser, [set, named_table]),
	LoadFun = fun(File) -> 
		?INFO("load parser file: ~p", [File]),
		case file:consult(filename:join(Dir, File)) of 
		{ok, Terms} -> 
			lists:foreach(fun store/1, Terms);
		{error, Reason} -> 
			?ERROR("Can't load parser file ~p : ~p", [File, Reason])
		end
    end,
    lists:foreach(LoadFun, trapd_misc:list_file(Dir, ".parser")),
    ?INFO("~p is starting...[ok]", [?MODULE]),
    {ok, state}.

store({vardef, VarOid, Name, Type}) -> 
	ets:insert(trap_vardef, {VarOid, Name, Type});

store({parser, TrapOid, VarDefs}) ->
	ets:insert(trap_parser, {TrapOid, VarDefs}).

handle_call(stats, _From, State) ->
	Rep = [{parsed, get(parsed)}],
	{reply, Rep, State};

handle_call(Req, _From, State) ->
    {stop, {error, {badreq, Req}}, State}.

prioritise_call(stats, _From, _State) ->
	10;
prioritise_call(_, _From, _State) ->
	0.

handle_cast({parse, #trap2{trapoid = TrapOid} = Trap}, State) ->
	put(parsed, get(parsed) + 1),
	VarDefs = 
    case ets:lookup(trap_parser, TrapOid) of
    [{_, Defs}] -> Defs;
    [] -> []
    end,
	NewTrap = do_parse(Trap, VarDefs),
	trap_filter:filter(NewTrap),
	{noreply, State};

handle_cast(Msg, State) ->
    {stop, {error, {badmsg, Msg}}, State}.

handle_info(Info, State) ->
    {stop, {error, {badinfo, Info}}, State}.

terminate(_Reason, _State) ->
	ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

do_parse(#trap2{addr = Addr, trapoid = TrapOid, 
	uptime = Uptime, varbinds = Varbinds} = Trap, VarDefs) ->
	{Vars, IdxVars, OidVars} = parse_vars(Varbinds, VarDefs),
	AllVars = lists:append([Vars, lists:reverse(IdxVars), lists:reverse(OidVars)]),
	Trap#trap2{vars = [{sender,Addr},{trapoid,TrapOid},{uptime,Uptime}|AllVars]}.

parse_vars(Varbinds, VarDefs) ->
	Len = length(Varbinds),
	lists:foldl(fun(Idx, {Vars, IdxVars, OidVars}) ->
		Vb = lists:nth(Idx, Varbinds),
        VarOid = mib_oid:to_str(Vb#varbind.oid),
		%VarType = Vb#varbind.variabletype,
        VarVal = Vb#varbind.value,
		{NewVars, NewIdxVars} = 
		case find_vardef(Idx, VarOid, VarDefs) of
		{Name, Type} ->
			Val = format(Type, VarVal),
			{[{Name, Val} | Vars],  [{idx_var(Idx), Val}|IdxVars]};
		false ->
			{Vars, [{idx_var(Idx), VarVal}|IdxVars]}
		end,
		{NewVars, NewIdxVars, [{oid_var(Idx), VarOid}|OidVars]}
	end, {[], [], []}, lists:seq(1, Len)).

find_vardef(Idx, VarOid, VarDefs) ->
	case lists:keysearch(Idx, 1, VarDefs) of
	{value, {_, Name, Type}} -> 
		{Name, Type};
	false ->
		case ets:lookup(trap_vardef, VarOid) of
		[{_, Name, Type}] -> 
			{Name, Type};
		[] ->
			false
		end
	end.

idx_var(Idx) ->
	list_to_atom(integer_to_list(Idx)).

oid_var(Idx) ->
	list_to_atom("@"++integer_to_list(Idx)).

format(integer, V) when is_list(V) ->
    try list_to_integer(V) catch _:_ -> -1 end;

format(integer, V) when is_integer(V)->
    V;
format(integer, _V) ->
    -1;

format(string, Val) when is_integer(Val) ->
    integer_to_list(Val);

format(string, Val) ->
    Val;

format(mac, Val) ->
    string:to_upper(trapd_misc:macaddr(Val));

format(ip, Val) ->
    trapd_misc:ipaddr(Val).

format(percent, V) when is_integer(V)->
    integer_to_list(V div 100) ;

