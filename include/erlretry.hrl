%%%-------------------------------------------------------------------
%%% @author Alpha Umaru Shaw <shawalpha5@gmail.com>
%%%-------------------------------------------------------------------
-author("Alpha Umaru Shaw").

-define(SERVER, ?MODULE).

-define(DEFAULT_RETRIES, 3).
-define(DEFAULT_MULTIPLIER, 2.0).
-define(DEFAULT_JITTER_FACTOR, 0.2).

-define(DEFAULT_BASE_DELAY, 500).
-define(DEFAULT_MAX_DELAY, 32000).

-record(retry, {
  task :: string(),
  function :: function(),
  retries :: non_neg_integer(),
  base_delay :: non_neg_integer(),
  max_delay :: non_neg_integer(),
  jitter :: non_neg_integer(),
  multiplier :: non_neg_integer(),
  suppress_log :: non_neg_integer(),
  backoff :: atom(),
  retry_predicate :: function()
}).