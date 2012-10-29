-module(stomp).

-export([connect/3,
	 disconnect/1]).

-type stomp_option() :: {on_message, function()}|
			{caller, pid()}.
-type stomp_error() :: ok.
-type stomp_version() :: '1.0'|'1.1'.
-export_type([stomp_option/0, stomp_error/0, stomp_version/0]).

-spec connect(Host::list(), Port::pos_integer(), Opts::[stomp:stomp_option()]) ->
		     {ok, Pid::pid()}|{error, stomp:stomp_error()}.
connect(Host, Port, Opts) ->
    stomp_client:start_link(Host, Port, Opts).

-spec disconnect(Pid::pid()) -> ok.
disconnect(Pid) ->
    stomp_client:stop(Pid).
