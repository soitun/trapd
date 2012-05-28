%%%----------------------------------------------------------------------
%%% File    : trapd.hrl
%%% Author  : Ery Lee <ery.lee@gmail.com>
%%% Purpose : trapd header file.
%%% Created : 21 Feb 2008
%%% Updated : 28 May 2012
%%% License : http://www.opengoss.com
%%%
%%% Copyright (C) 2012, www.opengoss.com 
%%%----------------------------------------------------------------------

-define(UPTIME, [1,3,6,1,2,1,1,3,0]).

-define(TRAPOID, [1,3,6,1,6,3,1,1,4,1,0]).

%trap record has been defined by snmp
-record(trap2, {addr, %agent ipaddr
			  trapoid, %trapoid
			  uptime, %uptime
			  varbinds, %origin varbinds
			  vars}). %variables after parse

-record(event, {name, %event class name 
				sender, %ipaddr of device
				source, %event source
				evtkey, %deduplicate key
				severity, %severity
				summary, %event summary
				timestamp, %event timestamp
				manager, %manager that generate this event
				from, %syslog, trap or monitor
				vars}).

