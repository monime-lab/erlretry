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
-export([play/2, play/3, play/4, play/5]).
-export([await/1, await/2, async_play/3, async_play/4, async_play/5, async_play/6, async_play/7]).


play(Fun, Opts) ->
  play(Fun, Opts, ?MAX_RETRIES).

play(Fun, Opts, Retries) ->
  play(Fun, Opts, Retries, 0).

play(Fun, Opts, Retries, Delay) ->
  play(Fun, Opts, Retries, Delay, ?MAX_DELAY, ?MAX_JITTER).

play(Fun, Opts, Retries, Delay, MaxDelay) ->
  play(Fun, Opts, Retries, Delay, MaxDelay, ?MAX_JITTER).


play(Fun, Opts, Retries, Delay, MaxDelay, MaxJitter)
  when is_function(Fun), is_list(Opts), is_integer(Retries),
  Retries >= 0, is_integer(MaxDelay), is_integer(MaxJitter) ->
  PlayInfo = #play_info{function = Fun, options = Opts,
    retries = Retries, base_delay = Delay, max_delay = MaxDelay,
    max_jitter = MaxJitter},
  try apply(Fun, Opts) of
    error ->
      retry_play(PlayInfo, error);
    {error, _} = Error ->
      retry_play(PlayInfo, Error);
    Result ->
      Result
  catch
    _:Reason ->
      retry_play(PlayInfo, {error, Reason})
  end.

async_play(Fun, Opts, Callback) ->
  async_play(Fun, Opts, ?MAX_RETRIES, Callback).

async_play(Fun, Opts, Retries, Callback) ->
  async_play(Fun, Opts, Retries, 0, Callback).

async_play(Fun, Opts, Retries, Delay, Callback) ->
  async_play(Fun, Opts, Retries, Delay, ?MAX_DELAY, ?MAX_JITTER, Callback).

async_play(Fun, Opts, Retries, Delay, MaxDelay, Callback) ->
  async_play(Fun, Opts, Retries, Delay, MaxDelay, ?MAX_JITTER, Callback).


async_play(Fun, Opts, Retries, Delay, MaxDelay, MaxJitter, Callback)
  when is_function(Fun), is_list(Opts), is_integer(Retries),
  Retries >= 0, is_integer(MaxDelay), is_integer(MaxJitter) ->
  Replay =
    fun(InitialError) ->
      PlayInfo = #play_info{function = Fun, options = Opts,
        retries = Retries, base_delay = Delay, max_delay = MaxDelay,
        max_jitter = MaxJitter},
      try_async_play(PlayInfo, Callback, InitialError)
    end,
  %% First attempt playing in the calling process,
  %% then retry in the background on failure
  try apply(Fun, Opts) of
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

await(Ref) ->
  await(Ref, 10000).

await(Ref, Timeout) ->
  receive
    {Ref, Reply} ->
      Reply
  after Timeout ->
    {error, timeout}
  end.


retry_play(#play_info{retries = 0}, Error) ->
  Error;
retry_play(#play_info{} = PLayInfo, Error) ->
  do_retry_play(PLayInfo, Error, 1).


do_retry_play(#play_info{retries = Retries}, Error, Attempts) when Attempts > Retries ->
  Error;
do_retry_play(PlayInfo, Error, Attempts) ->
  NextDelay = calculate_next_delay(PlayInfo, Attempts),
  timer:sleep(NextDelay),
  #play_info{function = Fun, options = Opts} = PlayInfo,
  try apply(Fun, Opts) of
    error ->
      do_retry_play(PlayInfo, error, Attempts + 1);
    {error, _} = Error ->
      do_retry_play(PlayInfo, Error, Attempts + 1);
    Result ->
      Result
  catch
    _:Reason ->
      do_retry_play(PlayInfo, {error, Reason}, Attempts + 1)
  end.


try_async_play(PlayInfo, Callback, InitialError) ->
  if is_function(Callback) ->
    erlang:spawn(fun() -> do_try_async_play(PlayInfo, Callback, InitialError) end),
    ok;
    true ->
      ClientPid = self(),
      ClientTag = make_ref(),
      erlang:spawn(fun() -> do_try_async_play(PlayInfo,
        {ClientPid, ClientTag}, InitialError) end),
      ClientTag
  end.


do_try_async_play(PlayInfo, CallbackOrRef, InitialError) ->
  Result = retry_play(PlayInfo, InitialError),
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
        _:X ->
          error_logger:error_msg("~p", [{X, erlang:get_stacktrace()}])
      end,
      ok
  end.

%% next_delay = min( [(base_delay * 2^n) +/- jitter], max_delay)
calculate_next_delay(#play_info{
  base_delay = BaseDelay,
  max_delay = MaxDelay,
  max_jitter = MaxJitter}, Attempts) ->
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