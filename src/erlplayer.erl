%%%-------------------------------------------------------------------
%%% @author Alpha Umaru Shaw <shawalpha5@gmail.com>
%%% @doc
%%%
%%% @end
%%% Company: Skulup Ltd
%%% Copyright: (C) 2020
%%%-------------------------------------------------------------------
-module(erlplayer).
-author("Alpha Umaru Shaw").

-include("erlplayer.hrl").

%% API
-export([play/1, play/2, play/3]).
-export([bg_play/1, bg_play/2, bg_play/3, bg_play/4]).
-export([play_or_bgretry/1, play_or_bgretry/2, play_or_bgretry/3, play_or_bgretry/4]).
-export([await/1, await/2]).

play(Fun) ->
  play(Fun, []).

play(Fun, Args) ->
  play(Fun, Args, []).

play(Fun, Args, Opts) when is_function(Fun), is_list(Args) ->
  Meta = create_meta(Fun, Args, Opts),
  try apply(Fun, Args) of
    error ->
      retry_play(Meta, error);
    {error, _} = Error ->
      retry_play(Meta, Error);
    Result ->
      Result
  catch
    _:Reason ->
      retry_play(Meta, {error, Reason})
  end.

play_or_bgretry(Fun) ->
  play_or_bgretry(Fun, []).

play_or_bgretry(Fun, Args) ->
  play_or_bgretry(Fun, Args, undefined).

play_or_bgretry(Fun, Args, Opts) when is_list(Opts) ->
  play_or_bgretry(Fun, Args, Opts, undefined);

play_or_bgretry(Fun, Args, Callback) ->
  play_or_bgretry(Fun, Args, [], Callback).

play_or_bgretry(Fun, Args, Opts, Callback)
  when is_function(Fun), is_list(Args) ->
  Replay =
    fun(InitialError) ->
      Meta = create_meta(Fun, Args, Opts),
      try_async_play(Meta, Callback, InitialError)
    end,
  %% First attempt playing in the calling process,
  %% then retry in the background on failure
  try apply(Fun, Args) of
    error ->
      Replay(error);
    {error, _} = Error ->
      Replay(Error);
    Result ->
      if is_function(Callback) ->
        handle_async_play_result(Result, Callback);
        true ->
          Ref = {self(), make_ref()},
          handle_async_play_result(Result, Ref)
      end
  catch
    _:Reason ->
      Replay({error, Reason})
  end.

bg_play(Fun) ->
  bg_play(Fun, []).

bg_play(Fun, Args) ->
  bg_play(Fun, Args, undefined).

bg_play(Fun, Args, Opts) when is_list(Opts) ->
  bg_play(Fun, Args, Opts, undefined);

bg_play(Fun, Args, Callback) ->
  bg_play(Fun, Args, [], Callback).

bg_play(Fun, Args, Opts, Callback)
  when is_function(Fun), is_list(Args) ->
  Meta = create_meta(Fun, Args, Opts),
  try_async_play(Meta, Callback, undefined).

await(Ref) ->
  await(Ref, 10000).

await(Ref, Timeout) ->
  receive
    {Ref, Reply} ->
      Reply
  after Timeout ->
    {error, timeout}
  end.


retry_play(#play_meta{retries = 0}, Error) ->
  Error;
retry_play(#play_meta{} = Meta, Error) ->
  do_retry_play(Meta, Error, 1).


do_retry_play(#play_meta{retries = Retries, ctx = Ctx}, Error, Attempts) when Attempts > Retries ->
  error_logger:warning_msg("Erlplay(~s) gave up after ~p retries. "
  "Last failure: ~p", [Ctx, Retries, Error]),
  Error;
do_retry_play(Meta, Error, Attempts) ->
  NextDelay = calculate_next_delay(Meta, Attempts),
  error_logger:warning_msg("Erlplay execution: (~s) failed: ~p. "
  "Remaining attempts: ~p. Will retry in: ~pms",
    [Meta#play_meta.ctx, Error, (Meta#play_meta.retries - Attempts) + 1, NextDelay]),
  timer:sleep(NextDelay),
  #play_meta{function = Fun, args = Args} = Meta,
  try apply(Fun, Args) of
    error ->
      do_retry_play(Meta, error, Attempts + 1);
    {error, _} = Error ->
      do_retry_play(Meta, Error, Attempts + 1);
    Result ->
      Result
  catch
    _:Reason ->
      do_retry_play(Meta, {error, Reason}, Attempts + 1)
  end.


try_async_play(Meta, Callback, InitialError) ->
  if is_function(Callback) ->
    erlang:spawn(fun() -> do_try_async_play(Meta, Callback, InitialError) end),
    ok;
    true ->
      ClientPid = self(),
      ClientTag = make_ref(),
      erlang:spawn(fun() -> do_try_async_play(Meta,
        {ClientPid, ClientTag}, InitialError) end),
      ClientTag
  end.


do_try_async_play(Meta, CallbackOrRef, InitialError) ->
  Result = retry_play(Meta, InitialError),
  handle_async_play_result(Result, CallbackOrRef).

handle_async_play_result(Result, CallbackOrRef) ->
  case CallbackOrRef of
    {ClientPid, ClientTag} ->
      catch ClientPid ! {ClientTag, Result},
      ClientTag;
    Fun when is_function(Fun) ->
      try
        apply(Fun, [Result])
      catch
        _:X:Stacktrace ->
          error_logger:error_msg("~p", [{X, Stacktrace}])
      end,
      ok
  end.

%% next_delay = min( [(base_delay * 2^n) +/- jitter], max_delay)
calculate_next_delay(#play_meta{
  base_delay = BaseDelay,
  max_delay = MaxDelay,
  jitter = MaxJitter}, Attempts) ->
  Delay =
    if BaseDelay == 0 ->
      100 * (1 bsl Attempts);
      true ->
        BaseDelay * (1 bsl Attempts)
    end,
  %% Jitter range = [0, MaxJitter]
  NewProbableDelay =
    case {rand:uniform(MaxJitter + 1) - 1, rand:uniform(2)} of
      {Jitter, 1} -> Delay + Jitter;
      {Jitter, _} -> erlang:abs(Delay - Jitter)
    end,
  erlang:min(NewProbableDelay, MaxDelay).

create_meta(Fun, Args, Opts) ->
  lists:foreach(
    fun({ctx, _}) ->
      ok;
      ({base_delay, _}) ->
        ok;
      ({max_delay, _}) ->
        ok;
      ({jitter, _}) ->
        ok;
      ({retries, _}) ->
        ok;
      (Other) ->
        error({unknown_option, Other})
    end, Opts),
  Ctx = proplists:get_value(ctx, Opts, ""),
  BaseDelay = proplists:get_value(base_delay, Opts, 0),
  MaxDelay = proplists:get_value(max_delay, Opts, ?MAX_DELAY),
  Jitter = proplists:get_value(jitter, Opts, ?DEFAULT_JITTER),
  Retries = proplists:get_value(retries, Opts, ?DEFAULT_RETRIES),
  #play_meta{
    function = Fun, args = Args,
    ctx = erlwater_assertions:is_string(Ctx),
    jitter = erlwater_assertions:is_non_negative_int(Jitter),
    retries = erlwater_assertions:is_non_negative_int(Retries),
    base_delay = erlwater_assertions:is_non_negative_int(BaseDelay),
    max_delay = erlwater_assertions:is_non_negative_int(MaxDelay)
  }.