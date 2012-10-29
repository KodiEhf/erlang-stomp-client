-module(stomp_client).
-behaviour(gen_server).

% API
-export([start_link/3]).

% Callbacks
-export([init/1, handle_cast/2, handle_call/3, handle_info/2,
	 code_change/3, terminate/2]).

-record(state, {host :: list(),
		port :: pos_integer(),
		opts :: [stomp_sup:stomp_option()],
		version :: stomp:stomp_version()
	       }).

% API
start_link(Host, Port, Options) ->
    gen_server:start_link(?MODULE, [Host, Port, Options], []).

% Callbacks
init([Host, Port, Options]) ->
    {ok, #state{host=Host,
		port=Port,
		opts=Options}}.

handle_call(_Msg, _From, State) ->
    {noreply, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(Reason, _State) ->
    Reason.

code_change(_, State, _) ->
    {ok, State}.
