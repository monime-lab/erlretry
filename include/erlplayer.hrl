%%%-------------------------------------------------------------------
%%% @author Alpha Umaru Shaw <shawalpha5@gmail.com>
%%%-------------------------------------------------------------------
-author("Alpha Umaru Shaw").

-define(SERVER, ?MODULE).

-define(MAX_RETRIES, 5).
-define(MAX_JITTER, 500).
-define(MAX_DELAY, 32000).

-define(STAGE_ERR_LOG, <<"Processing execution error. Giving up">>).

-record(play_info, {
  function :: function(),
  options :: list(),
  retries :: non_neg_integer(),
  base_delay :: non_neg_integer(),
  max_delay :: non_neg_integer(),
  max_jitter :: non_neg_integer()
}).


