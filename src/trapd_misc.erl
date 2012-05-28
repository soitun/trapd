%%%----------------------------------------------------------------------
%%% File    : trapd_misc.erl
%%% Author  : Ery Lee <ery.lee@gmail.com>
%%% Purpose : Trapd misc functions
%%% Created : 27 May 2012
%%% License : http://www.opengoss.com
%%%
%%% Copyright (C) 2012, www.opengoss.com
%%%----------------------------------------------------------------------
-module(trapd_misc).

-export([ipaddr/1,
		macaddr/1,
		list_file/2]).

list_file(Dir, Suffix) ->
  {ok, Files} = file:list_dir(Dir),
  [F || F <- Files, lists:suffix(Suffix, F)].

ipaddr(I) when is_integer(I) ->
    A = (I bsr 24) band 16#FF,
    B = (I bsr 16) band 16#FF,
    C = (I bsr 8) band 16#FF,
    D = (I) band 16#FF,
    ipaddr([A,B,C,D]);

ipaddr({A,B,C,D}) ->
    ipaddr([A,B,C,D]);

ipaddr(L) when is_list(L) and (length(L) == 4)->
	string:join(io_lib:format("~.10B~.10B~.10B~.10B", L), ".");

ipaddr(L) when is_list(L) ->
    L;

ipaddr(_) ->
    "".

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

