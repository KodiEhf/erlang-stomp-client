#A Stomp client written in Erlang  
  
##Usage sample (connecting with Active MQ stomp):  
  
>%Create a message handling function:  

Fun = fun(Msg) ->   
          io:format("Message ~p~n",[Msg])  
      end,  
  
>%Start the client and keep it's Pid:  
  
Pid = stomp_client:start("localhost",61613,"","",Fun),  
  
>%subscribe to a topic or a queue:  

stomp_client:subscribe_topic("TestTopic",Pid).  
  
####You should now get a printout on the console every time a message arrives on the topic you've subscribed to.
