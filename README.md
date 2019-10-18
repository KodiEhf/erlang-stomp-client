#A Stomp client written in Erlang  
  
####Check the [Wiki](https://github.com/KodiEhf/erlang-stomp-client/wiki/erlang-stomp-client-wiki) for more info or go straight to the [API docs](http://kodiehf.github.com/erlang-stomp-client/).  
  
##Usage sample:
  
>%Create a message handling function:  

`Fun = fun(Msg) ->`   
`          io:format("Message ~p~n",[Msg])`  
`      end,`  
  
>%Start the client and keep it's Pid:  
  
`{ok,Pid} = stomp_client:start("localhost",61613,"","",Fun),`  
  
>%subscribe to a topic or a queue:  

`stomp_client:subscribe_topic("TestTopic",[],Pid).`  

>%send a message to the TestTopic:

`stomp_client:send_topic("TestTopic","This is a test message",[],Pid).`  
  
>You should now get a printout on the console every time a message arrives on the topic you've subscribed to.

##Update for issue #1
You could now start the client using start/6 which takes anything as an internal state.
If you do that you need to change your onmessage function to arity/2 since it will now need to handle the message and the state as input.
I also added a get_client_state function to query the internal state (note, that this is a blocking call).