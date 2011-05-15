%% Copyright (c) 2011, Kodi ehf (http://kodiak.is)

-type header() :: {string(), string()}.

-type message() :: [{type | body, string()} |
		    {header, header()}].

-record(framer_state,
	{current = [] :: string(),
	 messages = [] :: [message()]
	}).
-record(parser_state,
	{current = [] :: string(),
	 last_char :: string(),
	 key = [] :: string(),
	 message = [] :: [message()],
	 got_type = false :: boolean(),
	 header = [] :: [header()]
	}).
