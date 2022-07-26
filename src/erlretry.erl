-module(erlretry).

-include("erlretry.hrl").

%% API
-export([run/1, run/2]).
-export([await/1, await/2]).

run(Fun) ->
  run(Fun, []).

run(Fun, Opts) when is_function(Fun) ->
  case proplists:get_value(mode, Opts, "") of
    async ->
      async_run(Fun, Opts);
    full_async ->
      full_async_run(Fun, Opts);
    _ ->
      sync_run(Fun, Opts)
  end.

sync_run(Fun, Opts) when is_function(Fun) ->
  Retry = create_retry(Fun, Opts),
  try apply(Fun, []) of
    error ->
      retry(Retry, error);
    {error, _} = Error ->
      retry(Retry, Error);
    Result ->
      Result
  catch
    _:Reason ->
      retry(Retry, {error, Reason})
  end.

async_run(Fun, Opts) when is_function(Fun) ->
  RetryFun =
    fun(InitialError) ->
      do_async_run(Fun, Opts, InitialError)
    end,
  %% First attempt playing in the calling process,
  %% then retry in the background on failure
  try apply(Fun, []) of
    error ->
      RetryFun(error);
    {error, _} = Error ->
      RetryFun(Error);
    Result ->
      Callback = proplists:get_value(callback, Opts),
      if is_function(Callback) ->
        handle_async_run_result(Result, Callback);
        true ->
          handle_async_run_result(Result, {self(), make_ref()})
      end
  catch
    _:Reason ->
      RetryFun({error, Reason})
  end.


full_async_run(Fun, Opts) when is_function(Fun) ->
  Retries = proplists:get_value(retries, Opts, ?DEFAULT_RETRIES),
  Opts2 = [{retries, Retries + 1} | proplists:delete(retries, Opts)],
  do_async_run(Fun, Opts2, undefined).

await(Ref) ->
  await(Ref, 10000).

await(Ref, Timeout) ->
  receive
    {Ref, Reply} ->
      Reply
  after Timeout ->
    {error, timeout}
  end.


do_async_run(Fun, Opts, InitialError) ->
  Retry = create_retry(Fun, Opts),
  Callback = proplists:get_value(callback, Opts),
  if is_function(Callback) ->
    erlang:spawn(fun() -> do_async_run2(Retry, Callback, InitialError) end),
    ok;
    true ->
      ClientPid = self(),
      ClientTag = make_ref(),
      erlang:spawn(fun() -> do_async_run2(Retry, {ClientPid, ClientTag}, InitialError) end),
      ClientTag
  end.


do_async_run2(Retry, CallbackOrRef, InitialError) ->
  handle_async_run_result(retry(Retry, InitialError), CallbackOrRef).

handle_async_run_result(Result, CallbackOrRef) ->
  case CallbackOrRef of
    {ClientPid, ClientTag} ->
      catch ClientPid ! {ClientTag, Result},
      ClientTag;
    Callback when is_function(Callback) ->
      try
        apply(Callback, [Result])
      catch
        _:X:Stacktrace ->
          logger:error("Callback call error: ~p", [{X, Stacktrace}])
      end,
      ok
  end.

retry(#retry{retries = 0}, Error) ->
  Error;
retry(#retry{retry_predicate = RetryPredicate} = Retry, Error) ->
  do_retry(Retry, Error, apply(RetryPredicate, [Error]), 1).

do_retry(_, Error, false, _) -> Error;

do_retry(#retry{retries = Retries, task = Task,
  suppress_log = HideLog}, Error, _, RetryCount) when RetryCount > Retries ->
  case HideLog of
    true ->
      ok;
    _ ->
      logger:warning("erlretry task '~s' gave up after ~p retries. Last error: ~p", [Task, RetryCount - 1, Error])
  end,
  Error;
do_retry(Retry, Error, _, RetryCount) ->
  NextDelay = max(round(apply(Retry#retry.backoff, next_delay, [Retry, RetryCount])), 0),
  case Retry#retry.suppress_log of
    true ->
      ok;
    _ when Error == undefined ->
      ok;
    _ ->
      logger:warning("erlretry task: '~s' failed: ~p. "
      "Remaining attempts: ~p. Will retry in: ~pms",
        [Retry#retry.task, Error, (Retry#retry.retries - RetryCount + 1), NextDelay])
  end,
  timer:sleep(NextDelay),
  RetryPredicate = Retry#retry.retry_predicate,
  try apply(Retry#retry.function, []) of
    error ->
      do_retry(Retry, error, apply(RetryPredicate, [error]), RetryCount + 1);
    {error, _} = NewError ->
      do_retry(Retry, NewError, apply(RetryPredicate, [NewError]), RetryCount + 1);
    Result ->
      Result
  catch
    _:Reason ->
      NewError = {error, Reason},
      do_retry(Retry, NewError, apply(RetryPredicate, [NewError]), RetryCount + 1)
  end.

retry_all_error(_) -> true.

create_retry(Fun, Opts) ->
  #retry{
    function = Fun,
    task = proplists:get_value(task, Opts, "default"),
    jitter = proplists:get_value(jitter, Opts, ?DEFAULT_JITTER_FACTOR),
    retries = proplists:get_value(retries, Opts, ?DEFAULT_RETRIES),
    base_delay = proplists:get_value(base_delay, Opts, ?DEFAULT_BASE_DELAY),
    max_delay = proplists:get_value(max_delay, Opts, ?DEFAULT_MAX_DELAY),
    suppress_log = proplists:get_value(suppress_log, Opts, false),
    multiplier = proplists:get_value(multiplier, Opts, ?DEFAULT_MULTIPLIER),
    retry_predicate = proplists:get_value(retry_predicate, Opts, fun retry_all_error/1),
    backoff =
    case proplists:get_value(backoff, Opts, false) of
      exponential -> erlretry_exponential_backoff;
      linear -> erlretry_linear_backoff;
      _ -> erlretry_constant_backoff
    end
  }.