%%%----------------------------------------------------------------------
%%% File    : trapd_app.erl
%%% Author  : Ery Lee <ery.lee@gmail.com>
%%% Purpose : trapd startup module
%%% Created : 13 Nov. 2010
%%% License : http://www.opengoss.com
%%%
%%% Copyright (C) 2010, www.opengoss.com 
%%%----------------------------------------------------------------------
-module(trapd_app).

-author('ery.lee@gmail.com').

-include_lib("elog/include/elog.hrl").

-export([start/0, stop/0]).

-behavior(application).

-export([start/2, stop/1]).

start() ->
	[application:start(App) || App <- [sasl, crypto, elog, evmon]],
    [application:start(App) || App <- [amqp_client, trapd, sesnmp]],
    ?PRINT_MSG("finished.~n").

stop() ->
    [application:stop(App) || App <- [sesnmp, trapd, amqp_client]],
	[application:stop(App) || App <- [evmon, elog, crypto, sasl]].

start(normal, _Args) ->
	trapd_sup:start_link().

stop(_) ->
	ok.

