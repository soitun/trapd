%%%----------------------------------------------------------------------
%%% File    : trapd.hrl
%%% Author  : Ery Lee <ery.lee@gmail.com>
%%% Purpose : trapd header file.
%%% Created : 21 Feb 2008
%%% License : http://www.opengoss.com/license
%%%
%%% Copyright (C) 2010, www.opengoss.com 
%%%----------------------------------------------------------------------
-define(UPTIME, [1,3,6,1,2,1,1,3,0]).

-define(TRAPOID, [1,3,6,1,6,3,1,1,4,1,0]).

%%internal trap message
-record(raw_trap, {addr, trapoid, uptime, timestamp, varbinds}).

%%trap event sent to trap probe
-record(trap_event, {name, sender, source, type, alarm_key, summary, raised_time, trapoid, variables}).

