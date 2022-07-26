-module(erlretry_constant_backoff).
-author("kaja").

-include("erlretry.hrl").
%% API
-export([next_delay/2]).


next_delay(#retry{
  base_delay = BaseDelay,
  jitter = MaxJitter}, _RetryCount) ->
  erlretry_utils:add_random_jitter(BaseDelay, MaxJitter).