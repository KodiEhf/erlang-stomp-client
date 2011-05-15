%%%-------------------------------------------------------------------
%%% @author nisbus <nisbus@kodiak.is>
%%% @author Omar Yasin <omarkj@kodiak.is>
%%% @copyright (C) 2011, Kodi ehf (http://kodiak.is)
%%% @doc
%%% A stomp client gen_server for Erlang
%%% @end
%%% Created : 13 May 2011 by nisbus
%%%-------------------------------------------------------------------
-module(stomp_parser).
-include("stomp_parser.hrl").
-export([frame/1, parse/1]).
-export([test/0]).

%% API
-spec frame(Buffer::string()) -> FramedMessage::#framer_state{}.
frame(Buffer) ->
    frame(Buffer, #framer_state{}).

-spec parse(Message::string()) -> message().
parse(Message) ->
    parse(Message, #parser_state{}).

%% Framer
-spec frame([] | string(), #framer_state{}) -> FramedMessage::#framer_state{}.
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

%% Parser
-spec parse(string(), #parser_state{}) -> message().
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

%% Test
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
