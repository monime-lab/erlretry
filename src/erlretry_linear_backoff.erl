-module(erlretry_linear_backoff).
-author("kaja").

-include("erlretry.hrl").
%% API
-export([next_delay/2]).


next_delay(#retry{
  base_delay = BaseDelay,
  max_delay = MaxDelay,
  jitter = MaxJitter}, RetryCount) ->
  case RetryCount of
    1 ->
      BaseDelay;
    _ ->
      Delay = min(RetryCount * BaseDelay, MaxDelay),
      erlretry_utils:add_random_jitter(Delay, MaxJitter)
  end.