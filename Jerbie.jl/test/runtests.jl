using Test
using Symbolics
using Distributed
import Logging

include("fpcore_bench.jl")  # brings in Jerbie (transitively) + all bench_* + x,y,a,b,c,...

const N_WORKERS = 4 # 4 workers was good enough for my laptop
if nprocs() == 1
    addprocs(N_WORKERS)
end
@everywhere workers() include(joinpath($(@__DIR__), "fpcore_bench.jl"))
@everywhere workers() import Logging

@testset "e2e tests" begin
    @variables x y

    # basic subtraction — only uses +, -, /, sqrt (current OP_MAP)
    @test isequal(Jerbie.from_sexpr(Jerbie.to_sexpr(sqrt(x+1) - sqrt(x)), Dict("x" => x)), sqrt(x+1) -
                                                                                           sqrt(x))

    # negation
    @test isequal(Jerbie.from_sexpr(Jerbie.to_sexpr(-sqrt(x)), Dict("x" => x)), -sqrt(x))

    # coeff < 0, coeff > 0
    @test isequal(Jerbie.from_sexpr(Jerbie.to_sexpr(x - 1), Dict("x" => x)), x - 1)
    @test isequal(Jerbie.from_sexpr(Jerbie.to_sexpr(1 - x), Dict("x" => x)), 1 - x)

    # two variables
    @test isequal(
        Jerbie.from_sexpr(Jerbie.to_sexpr(sqrt(x+y) - sqrt(x)), Dict("x" => x, "y" => y)),
        sqrt(x+y) - sqrt(x))
end

# ─────────────────────────────────────────────────────────────────────────────
# Herbie benchmark expressions — real-world numerical accuracy problems
# Source: herbie/bench/ — expressions with known cancellation issues
# ─────────────────────────────────────────────────────────────────────────────

@testset "to_sexpr — herbie/bench/tutorial.fpcore" begin
    # "Cancel like terms": (1 + x) - x → Symbolics simplifies to 1
    @test Jerbie.to_sexpr((1 + x) - x) == "1"

    # "Expanding a square": (x+1)^2 - 1
    @test Jerbie.to_sexpr((x + 1)^2 - 1) == "(- (^ (+ 1 x) 2) 1)"
end

@testset "to_sexpr — herbie/bench/numerics/every-cs.fpcore" begin
    # "Difference of squares": a^2 - b^2
    @test Jerbie.to_sexpr(a^2 - b^2) == "(- (^ a 2) (^ b 2))"

    # "ln(1 + x)": log(1 + x) — cancellation near x=0
    @test Jerbie.to_sexpr(log(1 + x)) == "(log (+ 1 x))"

    # "x / (x^2 + 1)"
    @test Jerbie.to_sexpr(x / (x^2 + 1)) == "(/ x (+ 1 (^ x 2)))"
end

@testset "to_sexpr — herbie/bench/numerics/hamming-misc.fpcore" begin
    # "Radioactive exchange between two surfaces": x^4 - y^4
    @test Jerbie.to_sexpr(x^4 - y^4) == "(- (^ x 4) (^ y 4))"
end

@testset "to_sexpr — herbie/bench/numerics/great-debate.fpcore" begin
    # difference of squares
    @test Jerbie.to_sexpr(x^2 - y^2) == "(- (^ x 2) (^ y 2))"
end

@testset "to_sexpr — herbie/bench/demo.fpcore" begin
    # "exp neg sub": exp(-(1 - x^2)) → Symbolics simplifies to exp(x^2 - 1)
    @test Jerbie.to_sexpr(exp(-(1 - x^2))) == "(exp (- (^ x 2) 1))"

    # "neg log": -(log(1/x - 1))
    @test Jerbie.to_sexpr(-log(1/x - 1)) == "(neg (log (- (/ 1 x) 1)))"

    # "Success Probability": 1 - (1-x)^a
    @test Jerbie.to_sexpr(1 - (1 - x)^a) == "(- 1 (^ (- 1 x) a))"
end

@testset "to_sexpr — herbie/bench/numerics/kahan.fpcore" begin
    # "Kahan's exp quotient": (exp(x) - 1) / x — cancellation near x=0
    @test Jerbie.to_sexpr((exp(x) - 1) / x) == "(/ (- (exp x) 1) x)"
end

@testset "to_sexpr — herbie/bench/numerics/libm.fpcore" begin
    # "find-atanh": log((1+x)/(1-x)) — equivalent to 2*atanh(x)
    @test Jerbie.to_sexpr(log((1 + x) / (1 - x))) == "(log (/ (+ 1 x) (- 1 x)))"
end

@testset "to_sexpr — herbie/bench/numerics/rosa.fpcore" begin
    # sin(x) - x — Taylor cancellation near x=0
    @test Jerbie.to_sexpr(sin(x) - x) == "(- (sin x) x)"

    # Doppler-style: subtraction in denominator
    @test Jerbie.to_sexpr(x / (x - y)) == "(/ x (- x y))"
end

@testset "to_sexpr — herbie/bench/mathematics/statistics.fpcore" begin
    # "2-ancestry mixing": sqrt(a^2 - b^2) — subtraction under sqrt
    @test Jerbie.to_sexpr(sqrt(a^2 - b^2)) == "(sqrt (- (^ a 2) (^ b 2)))"

    # cbrt of expression with subtraction
    @test Jerbie.to_sexpr(cbrt(a - b)) == "(cbrt (- a b))"
end

# ─────────────────────────────────────────────────────────────────────────────
# fpcore expr — every bench_* in fpcore_bench.jl  optimize_expr()
# ─────────────────────────────────────────────────────────────────────────────

@testset "fpcore expr" begin
    # single-variable only -- sample_context/rival_sample (sampling.jl) only supports one variable
    all_names = [n for n in names(Main, all = true) if startswith(string(n), "bench_")]
    bench_names = [n for n in all_names
                   if length(Symbolics.get_variables(getfield(Main, n))) == 1]
    jobs = [(name = string(name),
             sexpr_str = to_sexpr(getfield(Main, name)),
             varnames = string.(Symbolics.get_variables(getfield(Main, name))))
            for name in bench_names]

    pool = WorkerPool(workers())
    results = pmap(pool, jobs;
                    on_error = e -> (ok = false, err = sprint(showerror, e))) do job
        vars = Dict(v => Num(Symbolics.variable(Symbol(v))) for v in job.varnames)
        expr = from_sexpr(job.sexpr_str, vars)
        varlist = [vars[v] for v in job.varnames]
        Logging.with_logger(Logging.NullLogger()) do
            optimize_expr(expr, varlist; verbose = false)
        end
        (ok = true, err = nothing)
    end

    @testset "$(jobs[i].name)" for i in eachindex(jobs)
        results[i].ok || println(results[i].err)
        @test results[i].ok
    end
end
