%%%-------------------------------------------------------------------
%% @doc erlplayer public API
%% @end
%%%-------------------------------------------------------------------

-module(erlplayer_app).

-behaviour(application).

-export([start/2, stop/1]).

start(_StartType, _StartArgs) ->
  erlplayer_sup:start_link().

stop(_State) ->
  ok.

%% internal functions
