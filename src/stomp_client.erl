%%%-------------------------------------------------------------------
%%% @author nisbus
%%% @copyright (C) 2011, nisbus 
%%% @doc
%%%
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

-define(SERVER, ?MODULE). 

-record(state, {framer, socket, subscriptions,onmessage}).
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
start(Host,Port,User,Pass,MessageFunc) ->
    start_link(Host,Port,User,Pass,MessageFunc).

stop(Pid) ->
    gen_server:cast(Pid,{stop}).
    
subscribe_topic(Topic,Options,Pid) ->
    gen_server:cast(Pid, {subscribe,topic,Topic,Options}).

subscribe_queue(Queue,Options,Pid) ->
    gen_server:cast(Pid, {subscribe,queue,Queue,Options}).

unsubscribe_topic(Topic,Pid) ->
    gen_server:cast(Pid, {unsubscribe,topic,Topic}).

unsubscribe_queue(Queue,Pid) ->
    gen_server:cast(Pid, {unsubscribe,queue,Queue}).

ack(Message,Pid) ->
    gen_server:cast(Pid,{ack, Message}).

ack(Message, TransactionId,Pid) ->
    gen_server:cast(Pid, {ack, Message,TransactionId}).

send_topic(Topic, Message,Options,Pid) -> 
    io:format("Sending to topic~p~n",[Topic]),
    gen_server:cast(Pid, {send, topic, {Topic,Message,Options}}).

send_queue(Queue, Message,Options,Pid) ->
    gen_server:cast(Pid, {send, queue, {Queue,Message,Options}}).

start_link(Host,Port,User,Pass,MessageFunc) ->
    gen_server:start_link(?MODULE, [{Host,Port,User,Pass,MessageFunc}], []).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

init([{Host,Port,User,Pass,F}]) ->
    Message=lists:append(["CONNECT", "\nlogin: ", User, "\npasscode: ", Pass, "\n\n", [0]]),
    {ok,Sock}=gen_tcp:connect(Host,Port,[{active, false}]),
    gen_tcp:send(Sock,Message),    
    {ok, Response}=gen_tcp:recv(Sock, 0),
    State = frame(Response, #framer_state{}),
    inet:setopts(Sock,[{active,once}]),
    {ok, #state{framer = State, socket = Sock, onmessage = F}}.

handle_call(_Request, _From, State) ->
    Reply = ok,
    {reply, Reply, State}.

handle_cast({subscribe, topic ,Topic, Options}, #state{socket = Sock} = State) ->
    Message = lists:append(["SUBSCRIBE", "\ndestination: ", "/topic/"++Topic,format_options(Options) ,"\n\n", [0]]),
    gen_tcp:send(Sock,Message),   
    inet:setopts(Sock,[{active,once}]),
    {noreply, State#state{subscriptions = [State#state.subscriptions|Topic]}};

handle_cast({subscribe, queue ,Queue,Options}, #state{socket = Sock} = State) ->
    Message = lists:append(["SUBSCRIBE", "\ndestination: ", "/queue/"++Queue,format_options(Options) ,"\n\n", [0]]),
    gen_tcp:send(Sock,Message),   
    inet:setopts(Sock,[{active,once}]),
    {noreply, State#state{subscriptions = [State#state.subscriptions|Queue]}};

handle_cast({unsubscribe, topic ,Topic}, #state{socket = Sock} = State) ->
    Message=lists:append(["UNSUBSCRIBE", "\ndestination: ", "/topic/"++Topic, "\n\n", [0]]),
    gen_tcp:send(Sock,Message),   
    inet:setopts(Sock,[{active,once}]),
    {noreply, State#state{subscriptions = [State#state.subscriptions|Topic]}};

handle_cast({unsubscribe, queue ,Queue}, #state{socket = Sock} = State) ->
    Message=lists:append(["UNSUBSCRIBE", "\ndestination: ", "/queue/"++Queue, "\n\n", [0]]),
    gen_tcp:send(Sock,Message),   
    inet:setopts(Sock,[{active,once}]),
    {noreply, State#state{subscriptions = [State#state.subscriptions|Queue]}};

handle_cast(stop,#state{socket =Sock } = State) ->
    Message = lists:append(["DISCONNECT","\n\n",[0]]),
    gen_tcp:send(Sock,Message),
    inet:setopts(Sock,[{active,once}]),
    gen_tcp:close(Sock),
    {stop, normal,State};

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

handle_cast({send, topic, {Topic, Message,Options}}, #state{socket = Socket} = State) ->
    Msg = lists:append(["SEND","\ndestination:","/topic/"++Topic, format_options(Options),"\n\n",Message,[0]]),
    gen_tcp:send(Socket,Msg),
    inet:setopts(Socket,[{active,once}]),    
    {noreply,State};

handle_cast({send, queue, {Queue, Message,Options}},#state{socket = Socket} = State) ->
    Msg = lists:append(["SEND","\ndestination:","/queue/"++Queue, format_options(Options),"\n\n",Message,[0]]),
    gen_tcp:send(Socket,Msg),
    inet:setopts(Socket,[{active,once}]),    
    {noreply,State};

handle_cast(_Msg, State) ->    
    {noreply, State}.

handle_info(_Info, #state{socket = Sock, onmessage = Func} = State) ->
    {_,_,Data} = _Info,    
    NewState = case frame(Data,State#state.framer) of
		   #framer_state{messages = []} = N ->
		       N;
		   NewState1 ->
		       lists:foreach(fun(X) ->		
					     Msg = parse(X, #parser_state{}),
					     Func(Msg)
				     end,NewState1#framer_state.messages),		   
		       #framer_state{current = NewState1#framer_state.current}    
	       end,    
    inet:setopts(Sock,[{active,once}]),
    {noreply, State#state{framer = NewState}}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================
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
