%%%----------------------------------------------------------------------
%%% File    : trapd_sup.erl
%%% Author  : Ery Lee <ery.lee@gmail.com>
%%% Purpose : trapd supervisor
%%% Created : 19 Feb 2008
%%% Updated : 22 Nov 2009
%%% License : http://www.opengoss.com/
%%%
%%% Copyright (C) 2012, www.opengoss.com 
%%%----------------------------------------------------------------------
-module(trapd_sup).

-author("ery.lee@gmail.com").

-behavior(supervisor).

-export([start_link/0, init/1]).

start_link() ->
	supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
	Logger = {trapd_log, {trapd_log, start_link, []},
        permanent, 5000, worker, [trapd_log]},

	{ok, MapperDir} = application:get_env(mapper_dir),
	Mapper = {trap_mapper, {trap_mapper, start_link, [MapperDir]},
        permanent, 5000, worker, [trap_mapper]},

	{ok, FilterDir} = application:get_env(filter_dir),
	Filter= {trap_filter, {trap_filter, start_link, [FilterDir]},
        permanent, 5000, worker, [trap_filter]},

	{ok, ParserDir} = application:get_env(parser_dir),
	Parser = {trap_parser, {trap_parser, start_link, [ParserDir]},
        permanent, 5000, worker, [trap_parser]},

	Trapd = {trapd, {trapd, start_link, []},
        permanent, 5000, worker, [trapd]},

	{ok, {{one_for_one, 10, 3600}, [Logger, Mapper, Filter, Parser, Trapd]}}.


