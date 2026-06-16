# fuzz.jl — converter fuzzing: to_sexpr → egg pipeline → from_sexpr
# not for rule correctness

# Testsets:
#   1.  basic_fuzz      — symbolic + small-int leaves, safe ops (+,-,*,/,sqrt,trig)
#   2.  rational_fuzz   — Rational{Int} leaves (pos+neg), regression for 1//9 bug
#   3.  negative_fuzz   — negative-int leaves, exercises neg/sign paths in converter
#   4.  constant_fuzz   — fully constant expressions (no free variables)
#   5.  div_node_fuzz   — symbolic/symbolic division → BSImpl.Div node path
#   6.  deep_fuzz       — max_depth=7, stresses _fold_to_binary recursion
#   7.  float_fuzz      — Float64 leaves, exercises _num_to_sexpr string() path
#   8.  mixed_fuzz      — mixed Int+Rational+negative leaves, all ops together
#   9.  neg_pow_fuzz    — coeff=-1 with exp!=1 in _mul_to_sexpr (e.g. -x²)
#   10. multi_rat_fuzz  — 3+ symbolic terms with non-unit rational coefficients,
#                         hits _add_to_sexpr fallback + _fold_to_binary with (/ p q)
#
# Run with:
#   julia --project=. test/fuzz.jl

using Test
using Random
using Symbolics
using SymbolicUtils
using SymbolicUtils: issym

include("../src/EggFFI.jl")
using .EggFFI

@syms ex::Real why::Real zee::Real

# ─────────────────────────────────────────────────────────────────────────────
# Specs
# ─────────────────────────────────────────────────────────────────────────────

const basic_spec = let
    leaf_funcs = [
        () -> rand(1:10),
        () -> rand([ex, why, zee]),
    ]
    fns = vcat(
        1 .=> [sqrt, sin, cos, exp, log, (-)],
        2 .=> [+, +, +, -, -, *, *, *, /, /],
        3 .=> [+, *],
    )
    (leaves = leaf_funcs, funcs = fns)
end

# Regression for the 1//9 → "(/ 1 9)" bug and BSImpl.Const(Rational) parens bug.
const rational_spec = let
    leaf_funcs = [
        () -> Rational(rand(filter(!iszero, -8:8)), rand(1:8)),
        () -> rand([ex, why, zee]),
    ]
    fns = vcat(
        1 .=> [(-),],
        2 .=> [+, +, -, -, *, *, /, /],
        3 .=> [+, *],
    )
    (leaves = leaf_funcs, funcs = fns)
end

const negative_spec = let
    leaf_funcs = [
        () -> rand(-10:-1),
        () -> rand([ex, why, zee]),
    ]
    fns = vcat(
        1 .=> [(-),],
        2 .=> [+, +, -, -, *, *, /],
        3 .=> [+, *],
    )
    (leaves = leaf_funcs, funcs = fns)
end

const constant_spec = let
    leaf_funcs = [() -> rand(1:12)]
    fns = vcat(2 .=> [+, -, *, /])
    (leaves = leaf_funcs, funcs = fns)
end

# Symbolics creates Div only when BOTH sides are symbolic.
const div_node_spec = let
    leaf_funcs = [
        () -> rand(1:10),
        () -> rand([ex, why, zee]),
        () -> rand([ex, why, zee]),
    ]
    fns = vcat(
        1 .=> [sqrt, sin, cos, (-)],
        2 .=> [+, -, *, /, /, /],
        3 .=> [+, *],
    )
    (leaves = leaf_funcs, funcs = fns)
end

const deep_spec = let
    leaf_funcs = [
        () -> rand(1:5),
        () -> rand([ex, why, zee]),
    ]
    fns = vcat(
        1 .=> [sqrt, sin, cos, (-)],
        2 .=> [+, +, -, *, /],
        3 .=> [+, *],
    )
    (leaves = leaf_funcs, funcs = fns)
end

const float_spec = let
    leaf_funcs = [
        () -> rand() * 10.0 + 0.1,
        () -> rand([ex, why, zee]),
    ]
    fns = vcat(
        1 .=> [sin, cos, (-)],
        2 .=> [+, +, -, *, *, /],
        3 .=> [+, *],
    )
    (leaves = leaf_funcs, funcs = fns)
end

const mixed_spec = let
    leaf_funcs = [
        () -> rand(1:8),
        () -> rand(-8:-1),
        () -> Rational(rand(filter(!iszero, -6:6)), rand(1:6)),
        () -> rand([ex, why, zee]),
    ]
    fns = vcat(
        1 .=> [sqrt, sin, cos, exp, log, (-)],
        2 .=> [+, +, +, -, -, *, *, /, /],
        3 .=> [+, *],
    )
    (leaves = leaf_funcs, funcs = fns)
end

# coeff=-1, exp!=1 in _mul_to_sexpr e.g. -x²
const neg_pow_spec = let
    safe_pow = (base, _) -> base ^ rand(2:3)
    leaf_funcs = [
        () -> rand([ex, why, zee]),
        () -> rand(1:5),
    ]
    fns = vcat(
        1 .=> [(-), (-)],
        2 .=> [safe_pow, +, -, *],
    )
    (leaves = leaf_funcs, funcs = fns)
end

# 3+ terms with non-unit rational coefficients → _add_to_sexpr fallback
const multi_rat_spec = let
    leaf_funcs = [
        () -> Rational(rand(1:7), rand(2:7)),
        () -> rand([ex, why, zee]),
        () -> rand([ex, why, zee]),
    ]
    fns = vcat(
        2 .=> [+, +, -, *],
        3 .=> [+, +, +, *],
    )
    (leaves = leaf_funcs, funcs = fns)
end

# ─────────────────────────────────────────────────────────────────────────────
# Expression generator
# Rational(p,0) is treated like DomainError — retry, same as the official fuzzlib.jl
# ─────────────────────────────────────────────────────────────────────────────

function gen_rand_expr(inputs;
                       spec      = basic_spec,
                       leaf_prob = 0.5,
                       depth     = 0,
                       min_depth = 1,
                       max_depth = 4)
    if depth > max_depth || (min_depth <= depth && rand() < leaf_prob)
        leaf = rand(spec.leaves)()
        if issym(leaf)
            push!(inputs, leaf)
        end
        return leaf
    end
    arity, f = rand(spec.funcs)
    args = [gen_rand_expr(inputs; spec, leaf_prob,
                          depth = depth + 1, min_depth, max_depth)
            for _ in 1:arity]
    try
        result = f(args...)
        # reject Rational(p,0) — egg has no such concept, retry
        if result isa Rational && denominator(result) == 0
            return gen_rand_expr(inputs; spec, leaf_prob, depth, min_depth, max_depth)
        end
        return result
    catch err
        if err isa DomainError || err isa DivideError || err isa MethodError
            return gen_rand_expr(inputs; spec, leaf_prob, depth, min_depth, max_depth)
        else
            @show f arity args
            rethrow(err)
        end
    end
end

# ─────────────────────────────────────────────────────────────────────────────
# Numeric equality check via Symbolics.substitute
# ─────────────────────────────────────────────────────────────────────────────

function numerically_equal(expr, result, vars::Dict{String, Num}; n_samples::Int = 30)
    if isempty(vars)
        return isequal(
            Symbolics.unwrap(Symbolics.simplify(expr)),
            Symbolics.unwrap(Symbolics.simplify(result)),
        )
    end
    sym_vars = collect(values(vars))
    for _ in 1:n_samples
        point = Dict(v => rand() * 10.0 + 0.5 for v in sym_vars)
        va = try Float64(Symbolics.substitute(expr,   point)) catch; continue end
        vb = try Float64(Symbolics.substitute(result, point)) catch; return false end
        isnan(va) && isnan(vb) && continue
        (isnan(va) || isnan(vb)) && return false
        (isinf(va) && isinf(vb) && sign(va) == sign(vb)) && continue
        (isinf(va) || isinf(vb)) && return false
        isapprox(va, vb; rtol = 1e-8) || return false
    end
    return true
end

# ─────────────────────────────────────────────────────────────────────────────
# Failure struct
# ─────────────────────────────────────────────────────────────────────────────

struct FuzzFailure
    stage    :: Symbol
    rstate   :: Any
    trial    :: Int
    expr     :: Any
    sexpr    :: Union{String, Nothing}
    extracted:: Union{String, Nothing}
    result   :: Any
    err      :: Any
end

FuzzFailure(; stage, rstate, trial, expr,
              sexpr=nothing, extracted=nothing, result=nothing, err=nothing) =
    FuzzFailure(stage, rstate, trial, expr, sexpr, extracted, result, err)

function print_failures(failures::Vector{FuzzFailure}, limit::Int = 10)
    isempty(failures) && return
    println("\n── failures (first $(min(length(failures), limit))) ──")
    for (i, f) in enumerate(failures[1:min(end, limit)])
        println("  [$i] stage=$(f.stage)  trial=$(f.trial)")
        println("      expr:      ", f.expr)
        f.sexpr     !== nothing && println("      sexpr:     ", f.sexpr)
        f.extracted !== nothing && println("      extracted: ", f.extracted)
        f.result    !== nothing && println("      result:    ", f.result)
        f.err       !== nothing && println("      err:       ", f.err)
        println("      reproduce: Random.seed!(rng, $(f.rstate))")
    end
end

# ─────────────────────────────────────────────────────────────────────────────
# Core fuzz loop
# ─────────────────────────────────────────────────────────────────────────────

function run_fuzz(n_trials::Int;
                  spec      = basic_spec,
                  label     :: String = "fuzz",
                  n_samples :: Int    = 30,
                  max_depth :: Int    = 4)

    n_pass = n_mismatch = 0
    n_attempted = 0   # trials that reached the pipeline (ExactInfinityError excluded)
    n_to_sexpr_meth = n_to_sexpr_key = n_to_sexpr_other = 0
    n_parse_err = n_from_key = n_from_other = 0
    failures = FuzzFailure[]

    for i in 1:n_trials
        rstate = copy(Random.default_rng())
        inputs = Set()
        raw    = gen_rand_expr(inputs; spec, max_depth)
        expr   = Num(raw)
        vars   = Dict{String, Num}(
            string(Symbolics.unwrap(v)) => Num(Symbolics.unwrap(v))
            for v in inputs
        )

        local s
        try
            s = EggFFI.to_sexpr(expr)
        catch err
            if err isa EggFFI.ExactInfinityError
                continue   # Rational(p,0) inside Symbolics internals — skip, same as DomainError
            elseif err isa MethodError;  n_to_sexpr_meth  += 1
            elseif err isa KeyError;     n_to_sexpr_key   += 1
            else;                        n_to_sexpr_other += 1
                push!(failures, FuzzFailure(; stage=:to_sexpr, rstate, trial=i, expr, err))
            end
            n_attempted += 1
            continue
        end
        n_attempted += 1

        local extracted
        try
            ptr       = EggFFI.egraph_create(s)
            EggFFI.egraph_saturate!(ptr)
            extracted = EggFFI.egraph_extract(ptr)
            EggFFI.egraph_destroy(ptr)
        catch err
            n_parse_err += 1
            push!(failures, FuzzFailure(; stage=:egraph, rstate, trial=i, expr, sexpr=s, err))
            continue
        end

        local result
        try
            result = EggFFI.from_sexpr(extracted, vars)
        catch err
            if err isa KeyError; n_from_key   += 1
            else;                n_from_other += 1
            end
            push!(failures, FuzzFailure(; stage=:from_sexpr, rstate, trial=i,
                                          expr, sexpr=s, extracted, err))
            continue
        end

        if isequal(result, expr) || numerically_equal(expr, result, vars; n_samples)
            n_pass += 1
        else
            n_mismatch += 1
            push!(failures, FuzzFailure(; stage=:mismatch, rstate, trial=i,
                                          expr, sexpr=s, extracted, result))
        end
    end

    total_err = n_to_sexpr_meth + n_to_sexpr_key + n_to_sexpr_other +
                n_parse_err + n_from_key + n_from_other + n_mismatch
    println("\n=== $label ($n_trials trials) ===")
    println("  pass              : ", n_pass)
    println("  mismatch          : ", n_mismatch,      "  ← isequal+numerically_equal both false")
    println("  to_sexpr/method   : ", n_to_sexpr_meth, "  ← unsupported op in converter")
    println("  to_sexpr/keyerror : ", n_to_sexpr_key)
    println("  to_sexpr/other    : ", n_to_sexpr_other)
    println("  egraph/parse_err  : ", n_parse_err,     "  ← RecExpr<MathLang>::parse() rejected")
    println("  from_sexpr/key    : ", n_from_key,      "  ← op not in OP_MAP")
    println("  from_sexpr/other  : ", n_from_other)
    total_err > 0 && print_failures(failures)
    return n_pass, n_attempted, failures
end

# ─────────────────────────────────────────────────────────────────────────────
# Testsets
# ─────────────────────────────────────────────────────────────────────────────

Random.seed!(0xECC_FEED)

@testset "fuzz converter" begin

    @testset "basic_fuzz" begin
        Random.seed!(0x1111)
        n_pass, n_trials, _ = run_fuzz(400; spec=basic_spec, label="basic_fuzz")
        @test n_pass == n_trials
    end

    @testset "rational_fuzz" begin
        Random.seed!(0x2222)
        n_pass, n_trials, _ = run_fuzz(300; spec=rational_spec, label="rational_fuzz")
        @test n_pass == n_trials
    end

    @testset "negative_fuzz" begin
        Random.seed!(0x3333)
        n_pass, n_trials, _ = run_fuzz(300; spec=negative_spec, label="negative_fuzz")
        @test n_pass == n_trials
    end

    @testset "constant_fuzz" begin
        Random.seed!(0x4444)
        n_pass, n_trials, _ = run_fuzz(300; spec=constant_spec, label="constant_fuzz",
                                        n_samples=1)
        @test n_pass == n_trials
    end

    @testset "div_node_fuzz" begin
        Random.seed!(0x5555)
        n_pass, n_trials, _ = run_fuzz(300; spec=div_node_spec, label="div_node_fuzz")
        @test n_pass == n_trials
    end

    @testset "deep_fuzz" begin
        Random.seed!(0x6666)
        n_pass, n_trials, _ = run_fuzz(200; spec=deep_spec, label="deep_fuzz",
                                        max_depth=7)
        @test n_pass == n_trials
    end

    @testset "float_fuzz" begin
        Random.seed!(0x7777)
        n_pass, n_trials, _ = run_fuzz(300; spec=float_spec, label="float_fuzz")
        @test n_pass == n_trials
    end

    @testset "mixed_fuzz" begin
        Random.seed!(0x8888)
        n_pass, n_trials, _ = run_fuzz(300; spec=mixed_spec, label="mixed_fuzz")
        @test n_pass == n_trials
    end

    @testset "neg_pow_fuzz" begin
        Random.seed!(0x9999)
        n_pass, n_trials, _ = run_fuzz(300; spec=neg_pow_spec, label="neg_pow_fuzz")
        @test n_pass == n_trials
    end

    @testset "multi_rat_fuzz" begin
        Random.seed!(0xAAAA)
        n_pass, n_trials, _ = run_fuzz(300; spec=multi_rat_spec, label="multi_rat_fuzz")
        @test n_pass == n_trials
    end

end
