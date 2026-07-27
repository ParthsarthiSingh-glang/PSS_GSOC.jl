# compare_herbie.jl
#
# For each single-variable benchmark in fpcore_bench.jl: run real Herbie
# (batched, once, via `racket -l herbie improve`) and our own pipeline
# (isolated per-expression subprocess -- a crash on one expression can't
# take down the whole run), then print both outputs side by side.
# NOW includes 8000-point held-out scoring (run_improve_with_report),
# confirmed matching Herbie's real get-alternatives/get-sample mechanism --
# a deliberate shift from the original "no scoring" design.

include(joinpath(@__DIR__, "fpcore_bench.jl"))  # brings in Jerbie (transitively) + all bench_*

const RACKET = raw"E:\Racket\racket.exe"
const HERBIE_DIR = raw"E:\GSOC\herbie"
const CORPUS_PATH = joinpath(@__DIR__, "single_var_corpus.fpcore")
const HERBIE_OUT_PATH = joinpath(@__DIR__, "herbie_output.fpcore")
const RESULTS_PATH = joinpath(@__DIR__, "comparison_results.txt")
const WORKER = joinpath(@__DIR__, "isolated_worker.jl")

# -- 1. collect + filter to single-variable benchmarks, programmatically ---
bench_names = [n for n in names(Main, all = true) if startswith(string(n), "bench_")]
single_var_benches = Tuple{String, Num, String}[]  # (name, expr, varname)
for name in bench_names
    expr = getfield(Main, name)
    vars = Symbolics.get_variables(expr)
    if length(vars) == 1
        push!(single_var_benches, (string(name), expr, string(vars[1])))
    end
end
println("filtered: ", length(single_var_benches), " / ", length(bench_names),
    " benchmarks are single-variable")

# -- 2. write the FPCore corpus, one entry per line -------------------------
# to_sexpr() emits OUR OWN internal operator names ("neg", "^") which aren't
# valid FPCore surface syntax -- confirmed both by testing manually earlier
# (neg -> unary "-") and by real Herbie's own output using "pow" not "^".
# Translate on export only; to_sexpr() itself stays untouched since it's
# correct for our own internal round-tripping.

function _tree_to_string(tree)::String
    tree isa AbstractString && return tree
    op, args = tree
    return "($op " * join(_tree_to_string.(args), " ") * ")"
end

function _fpcore_safe(tree)
    tree isa AbstractString && return tree
    op, args = tree
    new_args = [_fpcore_safe(a) for a in args]
    op == "neg" && length(new_args) == 1 && return ("-", new_args)
    op == "^"   && return ("pow", new_args)
    op == "abs" && return ("fabs", new_args)
    op == "min" && return ("fmin", new_args)
    op == "max" && return ("fmax", new_args)
    op == "mod" && return ("fmod", new_args)
    return (op, new_args)
end

function to_fpcore_body(expr::Num)::String
    return _tree_to_string(_fpcore_safe(parse_sexpr(to_sexpr(expr))))
end

open(CORPUS_PATH, "w") do io
    for (name, expr, varname) in single_var_benches
        println(io, "(FPCore ($varname) :name \"$name\" $(to_fpcore_body(expr)))")
    end
end
println("wrote corpus: ", CORPUS_PATH)

# -- 3. run real Herbie, once, batched, on the whole corpus -----------------
println("running real Herbie...")
cd(HERBIE_DIR) do
    run(`$RACKET -l herbie improve $CORPUS_PATH $HERBIE_OUT_PATH`)
end
herbie_text = read(HERBIE_OUT_PATH, String)
println("herbie done")

# -- 4. parse herbie's output -- purely textual, no semantic reconstruction --
# (real Herbie can emit (if ...) branching -- regimes are on by default for
# it, off for us -- so we never try to rebuild it as one of our own Num
# expressions, just display the text it actually produced)

function split_fpcore_blocks(text::AbstractString)::Vector{String}
    blocks = String[]
    i = firstindex(text)
    n = lastindex(text)
    while true
        rng = findnext("(FPCore", text, i)
        rng === nothing && break
        j = first(rng)
        depth = 0
        in_string = false
        k = j
        while k <= n
            c = text[k]
            if in_string
                c == '"' && (in_string = false)
            elseif c == '"'
                in_string = true
            elseif c == '('
                depth += 1
            elseif c == ')'
                depth -= 1
                depth == 0 && break
            end
            k = nextind(text, k)
        end
        push!(blocks, text[j:k])
        i = nextind(text, k)
    end
    return blocks
end

function extract_fpcore_body_text(block::AbstractString)::String
    normalized = replace(block, r"\s+" => " ")
    sanitized = replace(normalized, r"\"[^\"]*\"" => "QSTR")
    try
        op, args = parse_sexpr(strip(sanitized))
        op == "FPCore" || return "PARSE_ERROR: not an FPCore block"
        return _tree_to_string(args[end])   # last top-level child = the body
    catch e
        return "PARSE_ERROR: $(sprint(showerror, e))"
    end
end

herbie_blocks = split_fpcore_blocks(herbie_text)
println("herbie produced ", length(herbie_blocks), " result blocks (expected ",
    length(single_var_benches), ")")

# -- 5. run our pipeline per expression, isolated in a subprocess -----------
# NOW uses the actual 256-train/8000-test methodology (run_improve_with_report),
# confirmed matching Herbie's real get-alternatives/get-sample mechanism.
# ALSO scores Herbie's own answer on the SAME test context, for a direct,
# apples-to-apples comparison (both sides run through our scoring, same
# 8000 held-out points) rather than just displaying Herbie's text.
const _CRASHED_RESULT = (winner="CRASHED", alt2="N/A", alt3="N/A", start=NaN, endsc=NaN,
                          alt2sc="N/A", alt3sc="N/A", herbie_score="N/A(subprocess crashed)")

function run_ours(sexpr_str::String, varname::String, herbie_str::String)
    try
        out = read(`julia $WORKER $sexpr_str $varname $herbie_str`, String)
        lines = filter(!isempty, split(strip(out), '\n'))
        isempty(lines) && return merge(_CRASHED_RESULT, (winner="CRASHED: no output", herbie_score="N/A(no output)"))

        err_idx = findfirst(l -> startswith(l, "JULIA_ERROR:"), lines)
        if err_idx !== nothing
            return merge(_CRASHED_RESULT, (winner="ERROR: " * lines[err_idx], herbie_score="N/A(ours crashed)"))
        end

        # each field lives on its own line with a unique "PREFIX: " marker --
        # find_field grabs the last matching line's remainder (findlast, not
        # findfirst, matches the original single-winner parsing's convention)
        function find_field(prefix::String)
            idx = findlast(l -> startswith(l, prefix), lines)
            idx === nothing ? nothing : strip(replace(lines[idx], prefix => ""))
        end

        winner_s = find_field("WINNER: ")
        start_s = find_field("START_SCORE: ")
        end_s = find_field("END_SCORE: ")
        (winner_s === nothing || start_s === nothing || end_s === nothing) &&
            return merge(_CRASHED_RESULT, (winner="CRASHED: malformed output", herbie_score="N/A(malformed)"))

        alt2_s = find_field("ALT2: ")
        alt3_s = find_field("ALT3: ")
        alt2sc_s = find_field("ALT2_SCORE: ")
        alt3sc_s = find_field("ALT3_SCORE: ")
        herbie_s = find_field("HERBIE_SCORE: ")

        return (
            winner = winner_s,
            alt2 = alt2_s === nothing ? "N/A(no alt2)" : alt2_s,
            alt3 = alt3_s === nothing ? "N/A(no alt3)" : alt3_s,
            start = parse(Float64, start_s),
            endsc = parse(Float64, end_s),
            alt2sc = alt2sc_s === nothing ? "N/A(no alt2)" : alt2sc_s,
            alt3sc = alt3sc_s === nothing ? "N/A(no alt3)" : alt3sc_s,
            herbie_score = herbie_s === nothing ? "N/A(no herbie score line)" : herbie_s,
        )
    catch e
        return _CRASHED_RESULT
    end
end

# -- 6. print + write results: input / herbie ans / our ans / both improvements --
open(RESULTS_PATH, "w") do io
    for (idx, (name, expr, varname)) in enumerate(single_var_benches)
        sexpr_str = to_sexpr(expr)
        herbie_str = idx <= length(herbie_blocks) ?
                     extract_fpcore_body_text(herbie_blocks[idx]) : "MISSING"
        result = run_ours(sexpr_str, varname, herbie_str)

        line = "[$name]\n" *
               "  input:  $sexpr_str\n" *
               "  herbie: $herbie_str\n" *
               "  our alt1: $(result.winner)\n" *
               "  our alt2: $(result.alt2)\n" *
               "  our alt3: $(result.alt3)\n" *
               "  input score -> herbie score: $(result.start) -> $(result.herbie_score)\n" *
               "  input score -> alt1 score:   $(result.start) -> $(result.endsc)\n" *
               "  input score -> alt2 score:   $(result.start) -> $(result.alt2sc)\n" *
               "  input score -> alt3 score:   $(result.start) -> $(result.alt3sc)\n"
        println(line)
        println(io, line)
    end
end
println("\nwrote results: ", RESULTS_PATH)
