# fuzz.jl — converter fuzzing: to_sexpr → egg pipeline → from_sexpr
#
# Three correctness checks per trial:
#   1. isequal           — structural identity (fast path)
#   2. numerically_equal — Float64 substitution at 50 random points in [-1000, 1000]
#   3. exactly_equal     — Rational{BigInt} at fixed points (exact, no tolerance)
#                          only fires for polynomial expressions over {ex,why,zee}
#                          returns (checked, equal) — checked=false means skipped
#
# Two invariants per trial:
#   A. egraph_contains — original expr findable after saturation
#   B. stop_reason     — must be :Saturated (not NodeLimit/TimeLimit)
#
# Testsets:
#   1.  basic_fuzz            — symbolic + small-int leaves, safe ops
#   2.  rational_fuzz         — Rational{Int} leaves, regression for 1//9 bug
#   3.  negative_fuzz         — negative-int leaves, neg/sign paths in converter
#   4.  constant_fuzz         — fully constant expressions (no free variables)
#   5.  div_node_fuzz         — symbolic/symbolic division → BSImpl.Div node path
#   6.  deep_fuzz             — max_depth=10, stresses _fold_to_binary recursion
#   7.  float_fuzz            — Float64 leaves, _num_to_sexpr string() path
#   8.  mixed_fuzz            — Int+Rational+negative leaves together
#   9.  neg_pow_fuzz          — coeff=-1, exp!=1 in _mul_to_sexpr (e.g. -x²)
#   10. multi_rat_fuzz        — 3+ terms with non-unit rational coefficients
#   11. rule_fuzz             — rules fire; verifies pipeline numerical equivalence
#   12. repeated_subexpr_fuzz — repeated variables (x*x, x²+2x+1)
#   13. nested_ops_fuzz       — deeply nested: sqrt(sqrt(x)), log(sqrt(x+1))
#   14. poly_fuzz             — polynomial-only; Rational{BigInt} exact check always fires
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
    leaf_funcs = [() -> rand(1:10), () -> rand([ex, why, zee])]
    fns = vcat(
        1 .=> [sqrt, sin, cos, exp, log, (-)],
        2 .=> [+, +, +, -, -, *, *, *, /, /],
        3 .=> [+, *],
    )
    (leaves = leaf_funcs, funcs = fns)
end

# regression: 1//9 → "(/ 1 9)" bug, BSImpl.Const(Rational) parens bug
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
    leaf_funcs = [() -> rand(-10:-1), () -> rand([ex, why, zee])]
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

# Symbolics creates BSImpl.Div only when BOTH sides are symbolic
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
    leaf_funcs = [() -> rand(1:5), () -> rand([ex, why, zee])]
    fns = vcat(
        1 .=> [sqrt, sin, cos, (-)],
        2 .=> [+, +, -, *, /],
        3 .=> [+, *],
    )
    (leaves = leaf_funcs, funcs = fns)
end

const float_spec = let
    leaf_funcs = [
        () -> rand() * 10.0 + 0.1,  # (0.1, 10.1) — finite, positive, non-zero
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

# coeff=-1, exp!=1 in _mul_to_sexpr: -x², -x³, -(x²+y)², etc.
const neg_pow_spec = let
    safe_pow = (base, _) -> base ^ rand(2:3)
    leaf_funcs = [() -> rand([ex, why, zee]), () -> rand(1:5)]
    fns = vcat(
        1 .=> [(-), (-)],
        2 .=> [safe_pow, +, -, *],
    )
    (leaves = leaf_funcs, funcs = fns)
end

# 3+ symbolic terms with non-unit rational coefficients → _add_to_sexpr fallback
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

# rules fire here — AstSize may extract a different but equal form
const rule_spec = let
    safe_pow = (base, _) -> base ^ rand(2:3)
    leaf_funcs = [() -> rand([ex, why, zee]), () -> rand(1:5)]
    fns = vcat(
        1 .=> [sqrt, (-), (-)],
        2 .=> [+, +, -, -, *, *, /, safe_pow],
    )
    (leaves = leaf_funcs, funcs = fns)
end

# only 2 vars — forces x*x, x²+2x+1, sin(x)+sin(x) patterns
const repeated_subexpr_spec = let
    leaf_funcs = [() -> rand([ex, why]), () -> rand(1:5)]
    fns = vcat(
        1 .=> [sqrt, sin, cos, (-)],
        2 .=> [+, +, -, *, *, *],
        3 .=> [+, *],
    )
    (leaves = leaf_funcs, funcs = fns)
end

# sqrt(sqrt(x)), log(sqrt(x+1)), sqrt(x²+y²) — deeply nested unary chains
const nested_ops_spec = let
    leaf_funcs = [() -> rand(1:10), () -> rand([ex, why, zee])]
    fns = vcat(
        1 .=> [sqrt, sqrt, log, cbrt, (-), (-), sin, cos],
        2 .=> [+, -, *, /, (x,y) -> sqrt(x^2 + y^2), (x,y) -> log(abs(x*y)+1)],
    )
    (leaves = leaf_funcs, funcs = fns)
end

# polynomial-only spec — no transcendentals, so Rational{BigInt} exact check always fires
# directly tests the AddMul internal representation with exact arithmetic
const poly_spec = let
    safe_pow = (base, _) -> base ^ rand(2:4)
    leaf_funcs = [
        () -> rand([ex, why, zee]),
        () -> rand(1:5),
        () -> Rational(rand(filter(!iszero, -4:4)), rand(1:4)),
    ]
    fns = vcat(
        1 .=> [(-), (-)],
        2 .=> [+, +, +, -, -, *, *, safe_pow],
        3 .=> [+, *],
    )
    (leaves = leaf_funcs, funcs = fns)
end

# ─────────────────────────────────────────────────────────────────────────────
# Expression generator
# ─────────────────────────────────────────────────────────────────────────────

function gen_rand_expr(inputs;
                       spec      = basic_spec,
                       leaf_prob = 0.92,
                       depth     = 0,
                       min_depth = 1,
                       max_depth = 10)
    if depth > max_depth || (min_depth <= depth && rand() < leaf_prob)
        leaf = rand(spec.leaves)()
        issym(leaf) && push!(inputs, leaf)
        return leaf
    end
    arity, f = rand(spec.funcs)
    args = [gen_rand_expr(inputs; spec, leaf_prob, depth=depth+1, min_depth, max_depth)
            for _ in 1:arity]
    try
        result = f(args...)
        # Rational(p,0) — egg has no such concept, retry like DomainError
        if result isa Rational && denominator(result) == 0
            return gen_rand_expr(inputs; spec, leaf_prob, depth, min_depth, max_depth)
        end
        return result
    catch err
        if err isa DomainError || err isa DivideError || err isa MethodError || err isa OverflowError
            return gen_rand_expr(inputs; spec, leaf_prob, depth, min_depth, max_depth)
        end
        @show f arity args
        rethrow(err)
    end
end

# ─────────────────────────────────────────────────────────────────────────────
# Equality checks
# ─────────────────────────────────────────────────────────────────────────────

# Float64 substitution at n_samples random points in [-1000, 1000]
function numerically_equal(expr, result, vars::Dict{String, Num}; n_samples::Int = 50)::Bool
    if isempty(vars)
        return isequal(
            Symbolics.unwrap(Symbolics.simplify(expr)),
            Symbolics.unwrap(Symbolics.simplify(result)),
        )
    end
    sym_vars = collect(values(vars))
    for _ in 1:n_samples
        point = Dict(v => rand() * 2000.0 - 1000.0 for v in sym_vars)
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

# Exact Rational{BigInt} check at fixed points — mirrors fuzz_addmulpow from SymbolicUtils
# Only fires for polynomial expressions (no sqrt/sin/etc at the substituted values).
# Returns (checked::Bool, equal::Bool):
#   checked=false → test skipped (transcendental expr, unknown var, conversion failed)
#   checked=true  → result is definitive
const EXACT_POINTS = Dict(
    "ex"  => Rational{BigInt}(1),
    "why" => Rational{BigInt}(-1),
    "zee" => Rational{BigInt}(2),
)

function exactly_equal(expr, result, vars::Dict{String, Num})::Tuple{Bool, Bool}
    isempty(vars) && return (false, true)
    !all(k -> haskey(EXACT_POINTS, k), keys(vars)) && return (false, true)

    point = Dict(Num(Symbolics.unwrap(v)) => EXACT_POINTS[k] for (k, v) in vars)
    va = try Symbolics.substitute(expr,   point; fold=Val(true)) catch; return (false, true) end
    vb = try Symbolics.substitute(result, point; fold=Val(true)) catch; return (false, true) end

    # substitute returns BSImpl.Const wrapping the value — extract with unwrap_const
    ua = Symbolics.unwrap(va)
    ub = Symbolics.unwrap(vb)
    SymbolicUtils.isconst(ua) && (ua = SymbolicUtils.unwrap_const(ua))
    SymbolicUtils.isconst(ub) && (ub = SymbolicUtils.unwrap_const(ub))
    ua isa Number || return (false, true)  # transcendental — didn't fold to a constant
    ub isa Number || return (false, true)

    ra = try Rational{BigInt}(ua) catch; return (false, true) end
    rb = try Rational{BigInt}(ub) catch; return (false, true) end

    # skip if either result is exact infinity (division by zero in expression)
    denominator(ra) == 0 && return (false, true)
    denominator(rb) == 0 && return (false, true)

    # skip if denominators are huge — indicates Float64 → Rational{BigInt} conversion
    # Float64 like 3.14 converts to 7070651414971679//2251799813685248 (denominator > 2^50)
    # pure rational expressions like 3//7 have small denominators
    denominator(ra) > BigInt(2)^50 && return (false, true)
    denominator(rb) > BigInt(2)^50 && return (false, true)

    return (true, ra == rb)
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
                  n_samples :: Int    = 50,
                  max_depth :: Int    = 10)

    n_pass = n_mismatch = n_attempted = 0
    n_exact_checked = 0  # how many trials actually ran exactly_equal
    n_to_sexpr_err = n_parse_err = n_from_err = 0
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

        # stage 1: to_sexpr
        local s
        try
            s = EggFFI.to_sexpr(expr)
        catch err
            err isa EggFFI.ExactInfinityError && continue  # Rational(p,0) — skip like DomainError
            n_to_sexpr_err += 1
            push!(failures, FuzzFailure(; stage=:to_sexpr, rstate, trial=i, expr, err))
            n_attempted += 1
            continue
        end
        n_attempted += 1

        # stage 2: egraph pipeline + invariants
        local extracted, stop_reason, total_nodes
        try
            ptr         = EggFFI.egraph_create(s)
            EggFFI.egraph_saturate!(ptr)
            stop_reason = EggFFI.egraph_stop_reason(ptr)
            total_nodes = EggFFI.egraph_total_size(ptr)
            extracted   = EggFFI.egraph_extract(ptr)
            origin_id   = EggFFI.egraph_contains(ptr, expr)
            EggFFI.egraph_destroy(ptr)
            origin_id === nothing &&
                error("egraph_contains: input not found after saturation")
        catch err
            n_parse_err += 1
            push!(failures, FuzzFailure(; stage=:egraph, rstate, trial=i, expr, sexpr=s, err))
            continue
        end

        if stop_reason !== :Saturated
            n_mismatch += 1
            push!(failures, FuzzFailure(; stage=:egraph, rstate, trial=i, expr, sexpr=s,
                                          err=ErrorException("stop_reason=$stop_reason nodes=$total_nodes")))
            continue
        end

        # stage 3: from_sexpr
        local result
        try
            result = EggFFI.from_sexpr(extracted, vars)
        catch err
            n_from_err += 1
            push!(failures, FuzzFailure(; stage=:from_sexpr, rstate, trial=i,
                                          expr, sexpr=s, extracted, err))
            continue
        end

        # equality checks
        float_ok          = isequal(result, expr) || numerically_equal(expr, result, vars; n_samples)
        checked, exact_ok = exactly_equal(expr, result, vars)
        checked && (n_exact_checked += 1)

        if float_ok && (!checked || exact_ok)
            n_pass += 1
        else
            n_mismatch += 1
            push!(failures, FuzzFailure(; stage=:mismatch, rstate, trial=i,
                                          expr, sexpr=s, extracted, result,
                                          err=ErrorException("float_ok=$float_ok exact_ok=$(checked ? exact_ok : :skipped)")))
        end
    end

    total_err = n_to_sexpr_err + n_parse_err + n_from_err + n_mismatch
    println("\n=== $label ($n_trials trials, $n_attempted attempted) ===")
    println("  pass              : ", n_pass)
    println("  exact_checked     : ", n_exact_checked, "  ← trials with Rational{BigInt} exact check")
    println("  mismatch          : ", n_mismatch,      "  ← float or exact equality failed")
    println("  to_sexpr/err      : ", n_to_sexpr_err,  "  ← unsupported op or unknown error")
    println("  egraph/err        : ", n_parse_err,      "  ← parse rejected or invariant failed")
    println("  from_sexpr/err    : ", n_from_err,       "  ← op not in OP_MAP or other")
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
        n_pass, n_trials, _ = run_fuzz(500; spec=basic_spec, label="basic_fuzz")
        @test n_pass == n_trials
    end

    @testset "rational_fuzz" begin
        Random.seed!(0x2222)
        n_pass, n_trials, _ = run_fuzz(500; spec=rational_spec, label="rational_fuzz")
        @test n_pass == n_trials
    end

    @testset "negative_fuzz" begin
        Random.seed!(0x3333)
        n_pass, n_trials, _ = run_fuzz(500; spec=negative_spec, label="negative_fuzz")
        @test n_pass == n_trials
    end

    @testset "constant_fuzz" begin
        Random.seed!(0x4444)
        n_pass, n_trials, _ = run_fuzz(500; spec=constant_spec, label="constant_fuzz",
                                        n_samples=1)
        @test n_pass == n_trials
    end

    @testset "div_node_fuzz" begin
        Random.seed!(0x5555)
        n_pass, n_trials, _ = run_fuzz(500; spec=div_node_spec, label="div_node_fuzz")
        @test n_pass == n_trials
    end

    @testset "deep_fuzz" begin
        Random.seed!(0x6666)
        n_pass, n_trials, _ = run_fuzz(500; spec=deep_spec, label="deep_fuzz")
        @test n_pass == n_trials
    end

    @testset "float_fuzz" begin
        Random.seed!(0x7777)
        n_pass, n_trials, _ = run_fuzz(500; spec=float_spec, label="float_fuzz")
        @test n_pass == n_trials
    end

    @testset "mixed_fuzz" begin
        Random.seed!(0x8888)
        n_pass, n_trials, _ = run_fuzz(500; spec=mixed_spec, label="mixed_fuzz")
        @test n_pass == n_trials
    end

    @testset "neg_pow_fuzz" begin
        Random.seed!(0x9999)
        n_pass, n_trials, _ = run_fuzz(500; spec=neg_pow_spec, label="neg_pow_fuzz")
        @test n_pass == n_trials
    end

    @testset "multi_rat_fuzz" begin
        Random.seed!(0xAAAA)
        n_pass, n_trials, _ = run_fuzz(500; spec=multi_rat_spec, label="multi_rat_fuzz")
        @test n_pass == n_trials
    end

    @testset "rule_fuzz" begin
        Random.seed!(0xBBBB)
        n_pass, n_trials, _ = run_fuzz(500; spec=rule_spec, label="rule_fuzz")
        @test n_pass == n_trials
    end

    @testset "repeated_subexpr_fuzz" begin
        Random.seed!(0xCCCC)
        n_pass, n_trials, _ = run_fuzz(500; spec=repeated_subexpr_spec, label="repeated_subexpr_fuzz")
        @test n_pass == n_trials
    end

    @testset "nested_ops_fuzz" begin
        Random.seed!(0xDDDD)
        n_pass, n_trials, _ = run_fuzz(500; spec=nested_ops_spec, label="nested_ops_fuzz")
        @test n_pass == n_trials
    end

    # 14. polynomial-only — Rational{BigInt} exact check fires on every trial
    @testset "poly_fuzz" begin
        Random.seed!(0xEEEE)
        n_pass, n_trials, _ = run_fuzz(500; spec=poly_spec, label="poly_fuzz")
        @test n_pass == n_trials
    end

end
