%%%-------------------------------------------------------------------
%%% @author nisbus <nisbus@kodiak.is>
%%% @author Omar Yasin <omarkj@kodiak.is>
%%% @copyright (C) 2011, Kodi ehf (http://kodiak.is)
%%% @doc
%%% A stomp client gen_server for Erlang
%%% @end
%%% Created : 13 May 2011 by nisbus
%%%-------------------------------------------------------------------
-module(stomp_client).

-behaviour(gen_server).

%% API
-export([start/5,stop/1,subscribe_topic/3,subscribe_queue/3,
	 unsubscribe_topic/2,unsubscribe_queue/2,
	 ack/2, ack/3, send_topic/4, send_queue/4,test/0]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
	 terminate/2, code_change/3]).

-export([start/6, get_client_state/1]).
-define(SERVER, ?MODULE). 

-record(state, {framer, socket, subscriptions,onmessage, client_state}).
-record(framer_state,
	{
	  current = [],
	  messages = []
	}).
-record(parser_state,
	{
	  current = [],
	  last_char,
	  key = [],
	  message = [],
	  got_type = false,
	  header = []
	}).

%%%===================================================================
%%% API
%%%===================================================================

-spec start(string(), integer(), string(),string(),fun(),any()) -> {ok,pid}.
start(Host,Port,User,Pass,MessageFunc, ClientState) ->
    start_link(Host,Port,User,Pass,MessageFunc,ClientState).

%%% @doc Starts the client
-spec start(string(),integer(),string(),string(),fun()) -> {ok,pid}.
start(Host,Port,User,Pass,MessageFunc) ->
    start_link(Host,Port,User,Pass,MessageFunc).

%%% @doc Stops the client
-spec stop(pid) -> ok.
stop(Pid) ->
    gen_server:cast(Pid,{stop}).
    
%%% @doc Subscribe to a single topic
-spec subscribe_topic(string(),[tuple(string(),string())],pid) -> ok.
subscribe_topic(Topic,Options,Pid) ->
    gen_server:cast(Pid, {subscribe,topic,Topic,Options}).

%%% @doc Subscribe to a single queue
-spec subscribe_queue(string(),[tuple(string(),string())],pid) -> ok.
subscribe_queue(Queue,Options,Pid) ->
    gen_server:cast(Pid, {subscribe,queue,Queue,Options}).

%%% @doc unsubscribe from a single topic
-spec unsubscribe_topic(string(),pid) -> ok.
unsubscribe_topic(Topic,Pid) ->
    gen_server:cast(Pid, {unsubscribe,topic,Topic}).

%%% @doc unsubscribe from a single queue
-spec unsubscribe_queue(string(),pid) -> ok.
unsubscribe_queue(Queue,Pid) ->
    gen_server:cast(Pid, {unsubscribe,queue,Queue}).

%%% @doc ack a message using the message or the message id
-spec ack(string(),pid) -> ok.
ack(Message,Pid) ->
    gen_server:cast(Pid,{ack, Message}).

%%% @doc ack a message from a transaction using the message or the message id and the transaction id
-spec ack(string(),string(),pid) -> ok.
ack(Message, TransactionId,Pid) ->
    gen_server:cast(Pid, {ack, Message,TransactionId}).

%%% @doc send a message to a topic
-spec send_topic(string(),string(),[tuple(string(),string())],pid) -> ok.
send_topic(Topic, Message,Options,Pid) -> 
    gen_server:cast(Pid, {send, topic, {Topic,Message,Options}}).

%%% @doc send a message to a queue
-spec send_queue(string(),string(),[tuple(string(),string())],pid) -> ok.
send_queue(Queue, Message,Options,Pid) ->
    gen_server:cast(Pid, {send, queue, {Queue,Message,Options}}).

%%% @doc request the client state given to the process when starting.
-spec get_client_state(pid) -> any().
get_client_state(Pid) ->
    gen_server:call(Pid, get_client_state).

%%% @hidden
start_link(Host,Port,User,Pass,MessageFunc) ->
    gen_server:start_link(?MODULE, [{Host,Port,User,Pass,MessageFunc}], []).

%% @hidden
start_link(Host,Port,User,Pass,MessageFunc,ClientState) ->
    gen_server:start_link(?MODULE, [{Host,Port,User,Pass,MessageFunc,ClientState}], []).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================
%%% @hidden
init([{Host,Port,User,Pass,F}]) ->
    ClientId = "erlang_stomp_"++binary_to_list(ossp_uuid:make(v4, text)),
    Message=lists:append(["CONNECT", "\nlogin: ", User, "\npasscode: ", Pass,"\nclient-id:",ClientId, "\n\n", [0]]),
    {ok,Sock}=gen_tcp:connect(Host,Port,[{active, false}]),
    gen_tcp:send(Sock,Message),    
    {ok, Response}=gen_tcp:recv(Sock, 0),
    State = frame(Response, #framer_state{}),
    inet:setopts(Sock,[{active,once}]),
    {ok, #state{framer = State, socket = Sock, onmessage = F}};

init([{Host,Port,User,Pass,F,Cl}]) ->
    {ok, State} = init([{Host,Port,User,Pass,F}]),
    {ok, State#state{client_state = Cl}}.

%%% @hidden
handle_call(get_client_state, _From, #state{client_state = Reply} = State) ->
    {reply, Reply, State};

%%% @hidden
handle_call(_Request, _From, State) ->
    Reply = ok,
    {reply, Reply, State}.

%%% @hidden
handle_cast({subscribe, topic ,Topic, Options}, #state{socket = Sock} = State) ->
    Message = lists:append(["SUBSCRIBE", "\ndestination: ", "/topic/"++Topic,format_options(Options) ,"\n\n", [0]]),
    gen_tcp:send(Sock,Message),   
    inet:setopts(Sock,[{active,once}]),
    {noreply, State#state{subscriptions = [State#state.subscriptions|Topic]}};

%%% @hidden
handle_cast({subscribe, queue ,Queue,Options}, #state{socket = Sock} = State) ->
    Message = lists:append(["SUBSCRIBE", "\ndestination: ", "/queue/"++Queue,format_options(Options) ,"\n\n", [0]]),
    gen_tcp:send(Sock,Message),   
    inet:setopts(Sock,[{active,once}]),
    {noreply, State#state{subscriptions = [State#state.subscriptions|Queue]}};

%%% @hidden
handle_cast({unsubscribe, topic ,Topic}, #state{socket = Sock} = State) ->
    Message=lists:append(["UNSUBSCRIBE", "\ndestination: ", "/topic/"++Topic, "\n\n", [0]]),
    gen_tcp:send(Sock,Message),   
    inet:setopts(Sock,[{active,once}]),
    {noreply, State#state{subscriptions = [State#state.subscriptions|Topic]}};

%%% @hidden
handle_cast({unsubscribe, queue ,Queue}, #state{socket = Sock} = State) ->
    Message=lists:append(["UNSUBSCRIBE", "\ndestination: ", "/queue/"++Queue, "\n\n", [0]]),
    gen_tcp:send(Sock,Message),   
    inet:setopts(Sock,[{active,once}]),
    {noreply, State#state{subscriptions = [State#state.subscriptions|Queue]}};

%%% @hidden
handle_cast(stop,#state{socket =Sock } = State) ->
    Message = lists:append(["DISCONNECT","\n\n",[0]]),
    gen_tcp:send(Sock,Message),
    inet:setopts(Sock,[{active,once}]),
    gen_tcp:close(Sock),
    {stop, normal,State};

%%% @hidden
handle_cast({ack, Message},#state{socket = Socket} = State) ->
    MessageId = case Message of
		    [_Type, {header,Headers}, _Body] ->
			proplists:get_value("message-id",Headers);
		    _ ->
			Message
		end,
    Msg = lists:append(["ACK", "\nmessage-id:",MessageId,"\n\n",[0]]),
    gen_tcp:send(Socket,Msg),
    inet:setopts(Socket,[{active,once}]),
    {noreply,State};

%%% @hidden
handle_cast({ack, Message,TransactionId},#state{socket = Socket} = State) ->
    MessageId = case Message of
		    [_Type, {header,Headers}, _Body] ->
			proplists:get_value("message-id",Headers);
		    _ ->
			Message
		end,
    Msg = lists:append(["ACK", "\nmessage-id:",MessageId,"\ntransaction:",TransactionId,"\n\n",[0]]),
    gen_tcp:send(Socket,Msg),
    inet:setopts(Socket,[{active,once}]),
    {noreply,State};

%%% @hidden
handle_cast({send, topic, {Topic, Message,Options}}, #state{socket = Socket} = State) ->
    Msg = lists:append(["SEND","\ndestination:","/topic/"++Topic, format_options(Options),"\n\n",Message,[0]]),
    gen_tcp:send(Socket,Msg),
    inet:setopts(Socket,[{active,once}]),    
    {noreply,State};

%%% @hidden
handle_cast({send, queue, {Queue, Message,Options}},#state{socket = Socket} = State) ->
    Msg = lists:append(["SEND","\ndestination:","/queue/"++Queue, format_options(Options),"\n\n",Message,[0]]),
    gen_tcp:send(Socket,Msg),
    inet:setopts(Socket,[{active,once}]),    
    {noreply,State};

%%% @hidden
handle_cast(_Msg, State) ->    
    {noreply, State}.

%%% @hidden
handle_info(_Info, #state{socket = Sock, onmessage = Func, framer = Framer, client_state = Cl} = State) ->
    {_,_,Data} = _Info,
    NewState = case Data of
		   {error, Error} ->
		       error_logger:error_msg("Cannot connect to STOMP ~p~n", [Error]),
		       Framer;
		   _ ->
		       do_framing(Data, Framer, Func, Cl)
	       end,
    inet:setopts(Sock,[{active,once}]),
    {noreply, State#state{framer = NewState}}.

%%% @hidden
terminate(_Reason, _State) ->
    ok.

%%% @hidden
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================
do_framing(Data, Framer, Func, Cl) ->
    case frame(Data,Framer) of
	#framer_state{messages = []} = N ->
	    N;
	NewState1 ->
	    lists:foreach(fun(X) ->		
				  Msg = parse(X, #parser_state{}),
				  case Cl of
				      undefined ->  Func(Msg);
				      _ -> Func(Msg,Cl)
				  end
			  end,NewState1#framer_state.messages),		   
	    #framer_state{current = NewState1#framer_state.current}    
    end.    

frame([],State) ->
    State;
frame([First|Rest],#framer_state{current = [], messages = []}) ->
    frame(Rest,#framer_state{current = [First]});
frame([0], State) ->
    Message = State#framer_state.current++[0],
    State#framer_state{messages = State#framer_state.messages++[Message], current = []};
frame([0|Rest], State) ->
    Message = State#framer_state.current++[0],
    frame(Rest,State#framer_state{messages = State#framer_state.messages++[Message], current = []});
frame([Match|Rest], #framer_state{current = Current} = State) ->
    frame(Rest,State#framer_state{current = Current++[Match]});
frame([Match|[]], #framer_state{current = Current} = State) ->
    State#framer_state{current = Current++[Match]}.

%First character
parse([First|Rest], #parser_state{last_char = undefined} = State) ->
    parse(Rest, State#parser_state{last_char = First, current = [First]});
%Command
parse([10|[]], #parser_state{last_char = Last, header = Header, message = Message}) when Last =:= 10 ->
    Message++[{header,Header}];
%%Start of Body (end of parse)
parse([10|Rest], #parser_state{last_char = Last, header = Header, message = Message}) when Last =:= 10 ->
    Body = lists:reverse(tl(lists:reverse(Rest))),
    Message++[{header,Header},{body,Body}];  
%%Get message type
parse([10|Rest], #parser_state{got_type = false, message = Message, current = Current} = State) ->
    Type = case Current of
	       [10|T] ->
		   T;
	       _ ->
		   Current
	   end,
    parse(Rest,State#parser_state{message = Message++[{type,Type}], current = [], got_type = true, last_char = 10});
%%Key Value Header
parse([10|Rest], #parser_state{key = Key, current = Value, header = Header} = State) when length(Key) =/= 0 ->
    parse(Rest,State#parser_state{last_char = 10, current =[], header = Header ++ [{Key,Value}], key = [] });  
%%%HEADER 
parse([10|Rest], #parser_state{got_type = true} = State) ->
    parse(Rest,State#parser_state{last_char = 10});
%%Starting value
parse([$:|Rest], #parser_state{key = [], current = Current} = State) ->
    parse(Rest,State#parser_state{current = [], key = Current, last_char = $:});
%First key char
parse([First|Rest], #parser_state{got_type = true, key = [], current = Current} = State) ->
    parse(Rest,State#parser_state{last_char = First, current = Current ++ [First]});
parse([First|Rest], #parser_state{got_type = true, key = Key, current = Current} = State) when length(Key) =/= 0 ->
    parse(Rest,State#parser_state{last_char = First, current = Current ++[First]});
parse([First|Rest], #parser_state{last_char = Last, current = Current} = State) when Last =/= undefined ->
    parse(Rest, State#parser_state{last_char = First, current = Current++[First]}).

format_options(Options) ->
    lists:foldl(fun(X,Acc) -> 
			case X of
			    [] ->
				Acc;
			    {Name, Value} ->
				Acc++["\n"++Name++":"++Value];
			    E ->
				throw("Error: invalid options format: "++E) 
			end
		end,[],Options).
%%%@hidden
test() ->
    Msg = "CONNECTED\n"++
"session:ID:id:ID"++
"\n\n"++[0]++
"MESSAGE\n"++
"message-id:ID:staging-53630-634408209863540308-1:1:1:1:2970112"++[10]++
"destination:/topic/MARKET.DATA\n"++
"timestamp:1305323578525"++[10]++
"expires:0\n"++
"content-length:814\n"++
"priority:4\n\n"++
"TEST"++[0]++"MESSAGE\n"++
"message-id:ID:staging-53630-634408209863540308-1:1:1:1:2970112"++[10]++
"destination:/topic/MARKET.DATA\n"++
"timestamp:1305323578525"++[10]++
"expires:0\n"++
"content-length:814\n"++
"priority:4\n\n"++
"TEST"++[0],
    F = frame(Msg,#framer_state{}),
    lists:foreach(fun(X) ->
			  io:format("~p~n",[parse(X,#parser_state{})])
		  end,F#framer_state.messages).
