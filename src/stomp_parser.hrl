-record(framer_state,
	{
	  current = [] :: [char()],
	  messages = [] :: [any()]
	}).
-record(parser_state,
	{
	  current = [] :: [char()],
	  last_char :: char(),
	  key = [] :: [char()],
	  message = [] :: [any()],
	  got_type = false :: boolean(),
	  header = [] :: [any()]
	}).
