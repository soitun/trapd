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

-import(lists, [reverse/1]).

-import(extbif, [to_list/1, to_atom/1]).

-export([start_link/1, lookup/1, update/1, parse/2]).

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

parse(TrapOid, RawTrap) ->
    gen_server2:cast(?MODULE, {parse, TrapOid, RawTrap}).

%%--------------------------------------------------------------------
%% Function: init(Args) -> {ok, State} |
%%                         {ok, State, Timeout} |
%%                         ignore               |
%%                         {stop, Reason}
%% Description: Initiates the server
%%--------------------------------------------------------------------
init([Dir]) ->
    {ok, ParserFiles} = file:list_dir(Dir),
    ets:new(trap_vardef, [set, named_table]),
    ets:new(trap_parser, [set, named_table]),
	LoadFun = fun(File) -> 
        case lists:suffix(".parser", File) of
        true -> 
            ?INFO("load parser file: ~p", [File]),
            case file:consult(filename:join(Dir, File)) of 
            {ok, Terms} ->
                lists:foreach(
                    fun({vardef, VarOid, Name, Type}) -> 
                        ets:insert(trap_vardef, {VarOid, Name, Type});
                       ({parser, TrapOid, VarDefs}) ->
                        ets:insert(trap_parser, {TrapOid, VarDefs})
                end, Terms);
            {error, Reason} ->
                ?ERROR("Can't load trap parser file ~p : ~p", [File, Reason])
            end;
        false ->
            ignore
        end
    end,
    lists:foreach(LoadFun, ParserFiles),
    {ok, state}.

handle_call(Req, _From, State) ->
    ?ERROR("unexpected request: ~p", [Req]),
    {reply, {error, unexpected_req}, State}.

handle_cast({parse, #raw_trap{trapoid = TrapOid} = RawTrap}, State) ->
	VarDefs = 
    case ets:lookup(trap_parser, TrapOid) of
    [{_, Defs}] -> Defs;
    [] -> []
    end,
	Tokens = do_parse(RawTrap, VarDefs),
	trap_filter:filter(TrapOid, Tokens),
	{noreply, State};

handle_cast(Msg, State) ->
    {stop, {error, {badmsg, Msg}}, State}.

handle_info(Info, State) ->
    {stop, {error, {badinfo, Info}}, State}.

terminate(_Reason, _State) ->
	ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

do_parse(#raw_trap{addr=Addr, trapoid=TrapOid, timestamp = Timestamp, uptime=UpTime, varbinds=Varbinds} = RawTrap, VarDefs) ->
	Tokens = [{'sender', Addr}, 
			  {'timestamp', Timestamp}, 
			  {'upTime', UpTime}, 
			  {'trapOid', TrapOid}], 
	VarTokens = parse_vars(Varbinds, VarDefs),
	lists:append([Tokens, VarTokens]).

parse_vars(Varbinds, VarDefs) ->
	Len = length(Varbinds),
	Vars = 
	lists:map(fun(Idx) -> 
		Vb = lists:nth(Idx, Varbinds),
        VarOid = oid2str(Vb#varbind.oid),
		%VarType = Vb#varbind.variabletype,
        VarVal = Vb#varbind.value,
		Var = 
		case find_vardef(Idx, VarOid, VarDefs) of
		{Name, Type} ->
			Val = format(Type, Val),
			[{Name, Val}, {idx_var(Idx), Val}];
		false ->
			[{idx_var(Idx), VarVal}]
		end,
		[{oid_var(Idx), VarOid}|Var]
	end, lists:seq(1, Len)),
	list:reverse(list:sort(lists:flatten(Vars))).

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
    string:to_upper(macaddr(Val));

format(ip, Val) ->
    ipaddr(Val).

oid2str(Oid) ->
    string:join([integer_to_list(I) || I <- Oid], ".").

macaddr(L) when is_list(L) and (length(L) == 6) ->
	L1 = io_lib:format("~.16B~.16B~.16B~.16B~.16B~.16B", L),
    L2 = lists:map(fun(C) -> 
        case length(C) of
            2 -> C;
            1 -> "0" ++ C
        end
    end, L1),
    string:join(L2, ":");

macaddr(L) when is_list(L) ->
    L;

macaddr(L) ->
    io:format("invalid mac: ~p", [L]),
	"".

ipaddr(I) when is_integer(I) ->
    A = (I bsr 24) band 16#FF,
    B = (I bsr 16) band 16#FF,
    C = (I bsr 8) band 16#FF,
    D = (I) band 16#FF,
    ipaddr([A,B,C,D]);

ipaddr(L) when is_list(L) and (length(L) == 4)->
	string:join(io_lib:format("~.10B~.10B~.10B~.10B", L), ".");

ipaddr(L) when is_list(L) ->
    L;

ipaddr(_) ->
    "".

