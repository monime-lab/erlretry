-module(erlretry_utils).
-author("kaja").

%% API
-export([add_random_jitter/2]).

add_random_jitter(Delay, JitterFactor) ->
  Delay + (Delay * JitterFactor * rand:uniform()).