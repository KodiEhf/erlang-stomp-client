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
	 ack/2, ack/3, send_topic/4, send_queue/4]).
%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
	 terminate/2, code_change/3]).

-define(SERVER, ?MODULE). 
-include("stomp_parser.hrl").
-record(state, {framer, socket, subscriptions,onmessage}).


%%%===================================================================
%%% API
%%%===================================================================
%%% @doc Starts the client
-spec start(string(),integer(),string(),string(),fun()) -> {ok,pid()}.
start(Host,Port,User,Pass,MessageFunc) ->
    start_link(Host,Port,User,Pass,MessageFunc).

%%% @doc Stops the client
-spec stop(pid) -> ok.
stop(Pid) ->
    gen_server:cast(Pid,{stop}).
    
%%% @doc Subscribe to a single topic
-spec subscribe_topic(string(),[tuple(string(),string())],pid()) -> ok.
subscribe_topic(Topic,Options,Pid) ->
    gen_server:cast(Pid, {subscribe,topic,Topic,Options}).

%%% @doc Subscribe to a single queue
-spec subscribe_queue(string(),[tuple(string(),string())],pid()) -> ok.
subscribe_queue(Queue,Options,Pid) ->
    gen_server:cast(Pid, {subscribe,queue,Queue,Options}).

%%% @doc unsubscribe from a single topic
-spec unsubscribe_topic(string(),pid()) -> ok.
unsubscribe_topic(Topic,Pid) ->
    gen_server:cast(Pid, {unsubscribe,topic,Topic}).

%%% @doc unsubscribe from a single queue
-spec unsubscribe_queue(string(),pid()) -> ok.
unsubscribe_queue(Queue,Pid) ->
    gen_server:cast(Pid, {unsubscribe,queue,Queue}).

%%% @doc ack a message using the message or the message id
-spec ack(string(),pid()) -> ok.
ack(Message,Pid) ->
    gen_server:cast(Pid,{ack, Message}).

%%% @doc ack a message from a transaction using the message or the message id and the transaction id
-spec ack(string(),string(),pid()) -> ok.
ack(Message, TransactionId,Pid) ->
    gen_server:cast(Pid, {ack, Message,TransactionId}).

%%% @doc send a message to a topic
-spec send_topic(string(),string(),[tuple(string(),string())],pid()) -> ok.
send_topic(Topic, Message,Options,Pid) -> 
    io:format("Sending to topic~p~n",[Topic]),
    gen_server:cast(Pid, {send, topic, {Topic,Message,Options}}).

%%% @doc send a message to a queue
-spec send_queue(string(),string(),[tuple(string(),string())],pid()) -> ok.
send_queue(Queue, Message,Options,Pid) ->
    gen_server:cast(Pid, {send, queue, {Queue,Message,Options}}).

%%% @hidden
start_link(Host,Port,User,Pass,MessageFunc) ->
    gen_server:start_link(?MODULE, [{Host,Port,User,Pass,MessageFunc}], []).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================
%%% @hidden
init([{Host,Port,User,Pass,F}]) ->
    Message=lists:append(["CONNECT", "\nlogin: ", User, "\npasscode: ", Pass, "\n\n", [0]]),
    {ok,Sock}=gen_tcp:connect(Host,Port,[{active, false}]),
    gen_tcp:send(Sock,Message),    
    {ok, Response}=gen_tcp:recv(Sock, 0),
    State = stomp_parser:frame(Response),
    inet:setopts(Sock,[{active,once}]),
    {ok, #state{framer = State, socket = Sock, onmessage = F}}.

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
handle_info(_Info, #state{socket = Sock, onmessage = Func} = State) ->
    {_,_,Data} = _Info,    
    NewState = case stomp_parser:frame(Data,State#state.framer) of
		   #framer_state{messages = []} = N ->
		       N;
		   NewState1 ->
		       lists:foreach(fun(X) ->		
					     Msg = stomp_parser:parse(X, #parser_state{}),
					     Func(Msg)
				     end,NewState1#framer_state.messages),		   
		       #framer_state{current = NewState1#framer_state.current}    
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

