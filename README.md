#A Stomp client written in Erlang  
  
##Usage sample:
  
>%Create a message handling function:  

Fun = fun(Msg) ->   
          io:format("Message ~p~n",[Msg])  
      end,  
  
>%Start the client and keep it's Pid:  
  
{ok,Pid} = stomp_client:start("localhost",61613,"","",Fun),  
  
>%subscribe to a topic or a queue:  

stomp_client:subscribe_topic("TestTopic",[],Pid).

>%send a message to the TestTopic:

stomp_client:send_topic("TestTopic","This is a test message",[],Pid).  
  
####You should now get a printout on the console every time a message arrives on the topic you've subscribed to.
  
#####Check the Wiki for more info on the API.