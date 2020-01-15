%%%-------------------------------------------------------------------
%%% @author Alpha Umaru Shaw <shawalpha5@gmail.com>
%%%-------------------------------------------------------------------
-author("Alpha Umaru Shaw").

-define(SERVER, ?MODULE).

-define(DEFAULT_RETRIES, 5).
-define(DEFAULT_JITTER, 500).

-define(MAX_DELAY, 32000).

-record(play_meta, {
  ctx :: string(),
  function :: function(),
  args :: list(),
  retries :: non_neg_integer(),
  base_delay :: non_neg_integer(),
  max_delay :: non_neg_integer(),
  jitter :: non_neg_integer()
}).


