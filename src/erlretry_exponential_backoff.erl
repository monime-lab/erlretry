-module(erlretry_exponential_backoff).
-author("kaja").

-include("erlretry.hrl").
%% API
-export([next_delay/2]).


next_delay(#retry{
  base_delay = BaseDelay,
  max_delay = MaxDelay,
  multiplier = Multiplier,
  jitter = MaxJitter}, RetryCount) ->
  io:format("RetryCount: ~p~n", [RetryCount]),
  case RetryCount of
    1 ->
      BaseDelay;
    _ ->
      Delay = min(calculate(BaseDelay, Multiplier, RetryCount), MaxDelay),
      erlretry_utils:add_random_jitter(Delay, MaxJitter)
  end.

calculate(Delay, _, 0) ->
  Delay;

calculate(Delay, Multiplier, RetryCount) ->
  calculate(Delay * Multiplier, Multiplier, RetryCount - 1).