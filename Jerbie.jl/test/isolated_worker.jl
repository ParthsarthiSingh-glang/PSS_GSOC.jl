# isolated_worker.jl
#
# Usage: julia isolated_worker.jl <sexpr_string> <varname> [<herbie_fpcore_answer>]
#
# Runs run_improve_with_report(...) on ONE expression in its own fresh
# process -- the actual 256-train/8000-test methodology, confirmed matching
# Herbie's real get-alternatives/get-sample (partition-pcontext splits one
# combined 8256-point sample by position; search only ever sees the first
# 256; start/end scores are computed on the held-out 8000).
#
# If a third argument (Herbie's own FPCore answer text) is given, also
# attempts to parse and score it on the SAME test context as our winner --
# a direct, apples-to-apples comparison. FPCore-specific syntax (cast/!
# precision wrappers) is stripped since they're identity for scoring
# purposes; answers containing "if" (regime/branching output -- Herbie's
# regimes are enabled by default, ours aren't) can't be scored the same
# way and are marked N/A rather than guessed at.
#
# Prints on success:
#   WINNER: <sexpr>              (alternatives[1])
#   ALT2: <sexpr>                (alternatives[2], only if it exists)
#   ALT3: <sexpr>                (alternatives[3], only if it exists)
#   START_SCORE: <float>
#   END_SCORE: <float>           (WINNER's score)
#   ALT2_SCORE: <float>          (only if ALT2 exists)
#   ALT3_SCORE: <float>          (only if ALT3 exists)
#   HERBIE_SCORE: <float or N/A(reason)>   (only if 3rd arg given)
#
# ALT2/ALT3 come from run_improve_with_report's `alternatives` field --
# Herbie itself never collapses search to a single winner internally (its
# own report lists every pareto-surviving alt, see mainloop.rkt's extract!
# and reports/make-graph.rkt); these are that same list's runners-up,
# scored on the identical held-out test context as WINNER/END_SCORE.
# On a catchable Julia error, prints "JULIA_ERROR: <message>" and exits 1.
# On a Rust panic, this whole process dies -- that's the point: isolating
# it here means the parent (compare_herbie.jl) only sees a failed
# subprocess, instead of the crash taking down the entire comparison run.

include(joinpath(@__DIR__, "..", "src", "Jerbie.jl"))
using .Jerbie
using Symbolics
import Logging

# strips FPCore's (cast X) and (! :precision binary32 X) wrappers -- both
# are identity for scoring purposes, just precision annotations. Returns
# (stripped_tree, contains_if::Bool) -- contains_if flags regime/branching
# answers, which can't be scored the same way as a single formula.
function _strip_cast_and_check(tree)
    tree isa AbstractString && return (tree, false)
    op, args = tree
    if op == "if"
        return (tree, true)
    end
    if op == "cast" && length(args) == 1
        return _strip_cast_and_check(args[1])
    end
    if op == "!"
        # (! :precision binary32 EXPR) or (! :precision binary64 EXPR) --
        # keyword-style metadata args, actual expr is always last
        return _strip_cast_and_check(args[end])
    end
    any_if = false
    new_args = []
    for a in args
        stripped, had_if = _strip_cast_and_check(a)
        any_if = any_if || had_if
        push!(new_args, stripped)
    end
    return ((op, new_args), any_if)
end

function _tree_to_sexpr_str(tree)::String
    tree isa AbstractString && return tree
    op, args = tree
    return "($op " * join(_tree_to_sexpr_str.(args), " ") * ")"
end

function main()
    if length(ARGS) < 2
        println("JULIA_ERROR: expected <sexpr> <varname> [<herbie_answer>]")
        exit(1)
    end
    sexpr_str = ARGS[1]
    varname = ARGS[2]
    herbie_str = length(ARGS) >= 3 ? ARGS[3] : nothing

    try
        var = Num(Symbolics.variable(Symbol(varname)))
        vars = Dict{String, Num}(varname => var)
        expr = from_sexpr(sexpr_str, vars)

        # suppress run_iteration!'s per-iteration @info/@warn noise --
        # only the final result lines matter for this batch run
        report = Logging.with_logger(Logging.NullLogger()) do
            run_improve_with_report(expr, [var])
        end

        println("WINNER: ", to_sexpr(report.winner))
        for (i, alt) in enumerate(report.alternatives[2:end])
            println("ALT", i + 1, ": ", to_sexpr(alt))
        end
        println("START_SCORE: ", start_score(report))
        println("END_SCORE: ", end_score(report))
        for (i, alt) in enumerate(report.alternatives[2:end])
            alt_score = errors_score(points_errors(alt, [var], report.test_context))
            println("ALT", i + 1, "_SCORE: ", alt_score)
        end

        if herbie_str !== nothing
            herbie_score_str = try
                tree = parse_sexpr(herbie_str)
                stripped, had_if = _strip_cast_and_check(tree)
                if had_if
                    "N/A(regime)"
                else
                    herbie_expr = from_sexpr(_tree_to_sexpr_str(stripped), vars)
                    string(errors_score(points_errors(herbie_expr, [var], report.test_context)))
                end
            catch e
                "N/A(unparseable: $(sprint(showerror, e)))"
            end
            println("HERBIE_SCORE: ", herbie_score_str)
        end
    catch e
        println("JULIA_ERROR: ", sprint(showerror, e))
        exit(1)
    end
end

main()
