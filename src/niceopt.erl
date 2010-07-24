%% The MIT License

%% Copyright (c) 2010 Alisdair Sullivan <alisdairsullivan@yahoo.ca>

%% Permission is hereby granted, free of charge, to any person obtaining a copy
%% of this software and associated documentation files (the "Software"), to deal
%% in the Software without restriction, including without limitation the rights
%% to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
%% copies of the Software, and to permit persons to whom the Software is
%% furnished to do so, subject to the following conditions:

%% The above copyright notice and this permission notice shall be included in
%% all copies or substantial portions of the Software.

%% THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
%% IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
%% FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
%% AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
%% LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
%% OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
%% THE SOFTWARE.


-module(niceopt).
-author("alisdairsullivan@yahoo.ca").

-export([parse/2]).


-ifdef(test).
-include_lib("eunit/include/eunit.hrl").
-endif.

-record(options, {
    opts_with_vals = [],
    labels = string,
    mode = unix
}).


parse(Cmd, Options) ->
    parse(Cmd, [], [], parse_options(Options, #options{})).
    
parse_options([{opts_with_vals, Val}|Rest], OptsRec) when is_list(Val) ->
    parse_options(Rest, OptsRec#options{opts_with_vals = Val});
parse_options([{labels, atom}|Rest], OptsRec) ->
    parse_options(Rest, OptsRec#options{labels = atom});
parse_options([{labels, string}|Rest], OptsRec) ->
    parse_options(Rest, OptsRec#options{labels = string});
parse_options([{mode, win}|Rest], OptsRec) ->
    parse_options(Rest, OptsRec#options{mode = win});
parse_options([{mode, unix}|Rest], OptsRec) ->
    parse_options(Rest, OptsRec#options{mode = unix});
parse_options([], OptsRec) ->
    OptsRec.
    

parse([], OptsAcc, ArgsAcc, _OptsRec) ->
    {ok, {lists:reverse(OptsAcc), lists:reverse(ArgsAcc)}};
parse(Cmd, OptsAcc, ArgsAcc, OptsRec) when element(#options.mode, OptsRec) =:= win ->
    case Cmd of
        [[$/|Opt]|Rest] -> 
            parse_win(Opt, Rest, OptsAcc, ArgsAcc, OptsRec)
        ; [Arg|Rest] -> parse(Rest, OptsAcc, [Arg] ++ ArgsAcc, OptsRec)
    end;
parse(Cmd, OptsAcc, ArgsAcc, OptsRec) ->
    case Cmd of
        [[$-, $-]|Rest] ->                                              % terminate collection of opts, 
            parse([], OptsAcc, lists:reverse(Rest) ++ ArgsAcc, OptsRec) %    everything else is an arg
        ; [[$-, $-|Opt]|Rest] -> parse_long(Opt, Rest, OptsAcc, ArgsAcc, OptsRec)
        ; [[$-|Opt]|Rest] -> parse_short(Opt, Rest, OptsAcc, ArgsAcc, OptsRec)
        ; [Arg|Rest] -> parse(Rest, OptsAcc, [Arg] ++ ArgsAcc, OptsRec)
    end.  


parse_long(Opt, Rest, OptsAcc, ArgsAcc, OptsRec) ->
    case split(Opt, "=") of
        {Key, none} -> maybe_val(Key, Rest, OptsAcc, ArgsAcc, OptsRec)
        ; {Key, Val} -> parse(Rest, [{label(Key, OptsRec), Val}] ++ OptsAcc, ArgsAcc, OptsRec)
    end.


parse_short([], Rest, OptsAcc, ArgsAcc, OptsRec) ->
    parse(Rest, OptsAcc, ArgsAcc, OptsRec);
parse_short(Opt, Rest, OptsAcc, ArgsAcc, OptsRec) ->
    {S, Shorts} = get_short(Opt),
    case Shorts of
        [] -> maybe_val(S, Rest, OptsAcc, ArgsAcc, OptsRec)
        ; _ -> 
            case has_val(S, OptsRec) of
                true -> parse(Rest, [{label(S, OptsRec), Shorts}] ++ OptsAcc, ArgsAcc, OptsRec)
                ; false -> parse_short(Shorts, Rest, [label(S, OptsRec)] ++ OptsAcc, ArgsAcc, OptsRec)
            end
    end.
    

parse_win([], Rest, OptsAcc, ArgsAcc, OptsRec) ->
    parse(Rest, OptsAcc, ArgsAcc, OptsRec);
parse_win(Opt, Rest, OptsAcc, ArgsAcc, OptsRec) ->
    {Win, Others} = get_win_opt(Opt),
    case split(Win, ":") of
        {Key, none} -> parse_win(Others, Rest, [label(Key, OptsRec)] ++ OptsAcc, ArgsAcc, OptsRec)
        ; {Key, Value} -> parse_win(Others, Rest, [{label(Key, OptsRec), Value}] ++ OptsAcc, ArgsAcc, OptsRec)
    end.

    
maybe_val(Key, [], Opts, Args, OptsRec) ->
    parse([], [label(Key, OptsRec)] ++ Opts, Args, OptsRec);
maybe_val(Key, [[$-|_]|_] = Rest, Opts, Args, OptsRec) ->
    parse(Rest, [label(Key, OptsRec)] ++ Opts, Args, OptsRec);
maybe_val(Key, [Arg|Rest], Opts, Args, OptsRec) ->
    case has_val(Key, OptsRec) of
        true -> parse(Rest, [{label(Key, OptsRec), Arg}] ++ Opts, Args, OptsRec)
        ; false -> parse(Rest, [label(Key, OptsRec)] ++ Opts, [Arg] ++ Args, OptsRec)
    end.


has_val(Key, OptsRec) ->
    lists:member(Key, OptsRec#options.opts_with_vals).
    

label(X, OptsRec) when is_integer(X) ->
    label([X], OptsRec);
label(Key, OptsRec) ->
    case OptsRec#options.labels of
        string -> Key
        ; atom -> list_to_atom(Key)     % mixing this with utf8 options is supported, but weird
    end.

    
split(Opt, S) ->
    split(Opt, S, []).

split([], _S, Key) ->
    {lists:reverse(Key), none};
split([$\\, SChar|T], [SChar], Key) ->      % if the opt:val delimeter character is preceded by the escape
    split(T, [SChar], [SChar] ++ Key);      %    character (\) just add it to the key and continue
split([SChar|[]], [SChar], _Key) ->         % dunno if i like this, but throw an error if there's a opt:val
    erlang:error(badarg);                   %    delimiter that isn't followed by a val. maybe should be []?
split([SChar|T], [SChar], Key) ->
    {lists:reverse(Key), T};
split([H|T], S, Key) ->
    split(T, S, [H] ++ Key).
    

get_short([S|Rest]) when S =< 127 -> {[S], Rest};
get_short([S, T|Rest]) when S >= 192, S =< 223 -> {[S, T], Rest};
get_short([S, T, U|Rest]) when S >= 224, S =< 239 -> {[S, T, U], Rest};
get_short([S, T, U, V|Rest]) when S >= 240, S =< 247 -> {[S, T, U, V], Rest}.


get_win_opt(Opt) ->
    get_win_opt(Opt, []).
    
get_win_opt([], Opt) ->
    {lists:reverse(Opt), []};    
get_win_opt([$/|T], Opt) ->
    {lists:reverse(Opt), T};    
get_win_opt([H|T], Opt) ->
    get_win_opt(T, [H] ++ Opt).
    
    
%% eunit tests
-ifdef(EUNIT).

short_test() ->
    ?assert(?MODULE:parse(["-a", "-ab", "-abc"], []) =:= {ok, {["a", "a", "b", "a", "b", "c"], []}}).

short_with_args_test() ->
    ?assert(?MODULE:parse(["-aarg", "-a", "-baarg", "-a", "arg", "arg"], [{opts_with_vals, ["a"]}]) =:= {ok, {[{"a", "arg"}, "a", "b", {"a", "arg"}, {"a", "arg"}], ["arg"]}}).

long_test() ->
    ?assert(?MODULE:parse(["--hi", "--there"], []) =:= {ok, {["hi", "there"], []}}).
    
long_with_args_test() ->
    ?assert(?MODULE:parse(["--key=value", "--key", "--key", "value", "value"], [{opts_with_vals, ["key"]}]) =:= {ok, {[{"key", "value"}, "key", {"key", "value"}], ["value"]}}).

all_args_test() ->
    ?assert(?MODULE:parse(["some", "random", "words"], []) =:= {ok, {[], ["some", "random", "words"]}}).
    
mixed_test() ->
    ?assert(
        ?MODULE:parse(["-aarg", "--key=value", "arg", "-a", "--key", "value", "--novalue", "-a", "-bc", "another arg", "--path", "/usr/bin"], [{opts_with_vals, ["a", "key", "path"]}]) 
            =:= {ok, {[{"a", "arg"}, {"key", "value"}, "a", {"key", "value"}, "novalue", "a", "b", "c", {"path", "/usr/bin"}], ["arg", "another arg"]}}).
            
win_test() ->
    ?assert(?MODULE:parse(["/a/b/c", "/d", "/key:value", "arg"], [{mode, win}]) =:= {ok, {["a", "b", "c", "d", {"key", "value"}], ["arg"]}}).
    
early_termination_test() ->
    ?assert(?MODULE:parse(["-a", "--", "-a", "--a"], []) =:= {ok, {["a"], ["-a", "--a"]}}).
            
labels_as_atoms_test() ->
    ?assert(?MODULE:parse(["-a", "--long"], [{labels, atom}]) =:= {ok, {[a, long], []}}).
    
unicode_test() ->
    ?assert(?MODULE:parse([[45, 194, 162, 226, 130, 172, 240, 164, 173, 162]], []) =:= {ok, {[[194, 162], [226, 130, 172], [240, 164, 173, 162]], []}}).
            
-endif.