using Test
using Symbolics

include("../src/EggFFI.jl")
using .EggFFI

@variables x y z a b c

# ─────────────────────────────────────────────────────────────────────────────
# Basic structural tests — all AddMul categories from SymbolicUtils/src/types.jl
# ─────────────────────────────────────────────────────────────────────────────

@testset "to_sexpr — basic unchanged cases" begin
    @test EggFFI.to_sexpr(x + 1)            == "(+ 1 x)"
    @test EggFFI.to_sexpr(sin(x))           == "(sin x)"
    @test EggFFI.to_sexpr(sqrt(x))          == "(sqrt x)"
    @test EggFFI.to_sexpr(x ^ 2)            == "(^ x 2)"
    @test EggFFI.to_sexpr(x / 2)            == "(/ x 2)"
    @test EggFFI.to_sexpr(log(x))           == "(log x)"
    @test EggFFI.to_sexpr(cos(x))           == "(cos x)"
end

@testset "to_sexpr — negation (neg a)" begin
    @test EggFFI.to_sexpr(-sin(x))          == "(neg (sin x))"
    @test EggFFI.to_sexpr(-cos(x))          == "(neg (cos x))"
    @test EggFFI.to_sexpr(-log(x))          == "(neg (log x))"
    @test EggFFI.to_sexpr(-sqrt(x))         == "(neg (sqrt x))"
    @test EggFFI.to_sexpr(-x)               == "(neg x)"
    @test EggFFI.to_sexpr(-(x^2))           == "(neg (^ x 2))"
    @test EggFFI.to_sexpr(-2x)              == "(* -2 x)"
    @test EggFFI.to_sexpr(-(x + 1))         == "(+ -1 (neg x))"
end

@testset "to_sexpr — subtraction Case 1: coeff=0, one +1 and one -1 in dict" begin
    @test EggFFI.to_sexpr(x - y)                        == "(- x y)"
    @test EggFFI.to_sexpr(sin(x) - cos(x))              == "(- (sin x) (cos x))"
    @test EggFFI.to_sexpr(sqrt(x + 1) - sqrt(x))        == "(- (sqrt (+ 1 x)) (sqrt x))"
    @test EggFFI.to_sexpr(log(x + 1) - log(x))          == "(- (log (+ 1 x)) (log x))"
    @test EggFFI.to_sexpr(sin(x) - cos(y))              == "(- (sin x) (cos y))"
    @test EggFFI.to_sexpr(sqrt(x + 1) - sqrt(x + 2))   == "(- (sqrt (+ 1 x)) (sqrt (+ 2 x)))"
    @test EggFFI.to_sexpr(2x - 3y)                      == "(- (* 2 x) (* 3 y))"
    @test EggFFI.to_sexpr(sin(x)^2 - cos(x)^2)         == "(- (^ (sin x) 2) (^ (cos x) 2))"
end

@testset "to_sexpr — subtraction Case 2: coeff<0, one +1 term in dict" begin
    @test EggFFI.to_sexpr(x - 1)                        == "(- x 1)"
    @test EggFFI.to_sexpr(x^2 - 1)                      == "(- (^ x 2) 1)"
    @test EggFFI.to_sexpr(sin(x) - 1)                   == "(- (sin x) 1)"
    @test EggFFI.to_sexpr(sqrt(x) - 1)                  == "(- (sqrt x) 1)"
    @test EggFFI.to_sexpr(sqrt(x^2 - 1))                == "(sqrt (- (^ x 2) 1))"
end

@testset "to_sexpr — subtraction Case 3: coeff>0, one -1 term in dict" begin
    @test EggFFI.to_sexpr(1 - x)                        == "(- 1 x)"
    @test EggFFI.to_sexpr(1 - sin(x))                   == "(- 1 (sin x))"
end

@testset "to_sexpr — edge cases" begin
    @test EggFFI.to_sexpr(x - x)                        == "0"
    @test EggFFI.to_sexpr(sqrt(x + 100) - sqrt(x))      == "(- (sqrt (+ 100 x)) (sqrt x))"
    @test EggFFI.to_sexpr(-(-sin(x)))                    == "(sin x)"
end

# ─────────────────────────────────────────────────────────────────────────────
# Herbie benchmark expressions — real-world numerical accuracy problems
# Source: herbie/bench/ — expressions with known cancellation issues
# ─────────────────────────────────────────────────────────────────────────────

@testset "to_sexpr — herbie/bench/tutorial.fpcore" begin
    # "Cancel like terms": (1 + x) - x → Symbolics simplifies to 1
    @test EggFFI.to_sexpr((1 + x) - x)                  == "1"

    # "Expanding a square": (x+1)^2 - 1
    @test EggFFI.to_sexpr((x + 1)^2 - 1)                == "(- (^ (+ 1 x) 2) 1)"
end

@testset "to_sexpr — herbie/bench/numerics/every-cs.fpcore" begin
    # "Difference of squares": a^2 - b^2
    @test EggFFI.to_sexpr(a^2 - b^2)                    == "(- (^ a 2) (^ b 2))"

    # "The quadratic formula": sqrt(b^2 - 4ac) — subtraction under sqrt
    # Symbolics groups symbolic terms: 4*a*c → (* 4 (* a c))
    @test EggFFI.to_sexpr(sqrt(b^2 - 4*a*c))            == "(sqrt (- (^ b 2) (* 4 (* a c))))"

    # "ln(1 + x)": log(1 + x) — cancellation near x=0
    @test EggFFI.to_sexpr(log(1 + x))                   == "(log (+ 1 x))"

    # "x / (x^2 + 1)"
    @test EggFFI.to_sexpr(x / (x^2 + 1))                == "(/ x (+ 1 (^ x 2)))"
end

@testset "to_sexpr — herbie/bench/numerics/hamming-misc.fpcore" begin
    # "Radioactive exchange between two surfaces": x^4 - y^4
    @test EggFFI.to_sexpr(x^4 - y^4)                    == "(- (^ x 4) (^ y 4))"
end

@testset "to_sexpr — herbie/bench/numerics/great-debate.fpcore" begin
    # "Kahan p9": (x-y)(x+y) — factored form of x^2 - y^2
    @test EggFFI.to_sexpr((x - y) * (x + y))            == "(* (- x y) (+ x y))"

    # difference of squares
    @test EggFFI.to_sexpr(x^2 - y^2)                    == "(- (^ x 2) (^ y 2))"
end

@testset "to_sexpr — herbie/bench/demo.fpcore" begin
    # "exp neg sub": exp(-(1 - x^2)) → Symbolics simplifies to exp(x^2 - 1)
    @test EggFFI.to_sexpr(exp(-(1 - x^2)))              == "(exp (- (^ x 2) 1))"

    # "neg log": -(log(1/x - 1))
    @test EggFFI.to_sexpr(-log(1/x - 1))                == "(neg (log (- (/ 1 x) 1)))"

    # "Success Probability": 1 - (1-x)^a
    @test EggFFI.to_sexpr(1 - (1 - x)^a)                == "(- 1 (^ (- 1 x) a))"
end

@testset "to_sexpr — herbie/bench/numerics/kahan.fpcore" begin
    # "Kahan's exp quotient": (exp(x) - 1) / x — cancellation near x=0
    @test EggFFI.to_sexpr((exp(x) - 1) / x)             == "(/ (- (exp x) 1) x)"
end

@testset "to_sexpr — herbie/bench/numerics/libm.fpcore" begin
    # "find-atanh": log((1+x)/(1-x)) — equivalent to 2*atanh(x)
    @test EggFFI.to_sexpr(log((1 + x) / (1 - x)))       == "(log (/ (+ 1 x) (- 1 x)))"
end

@testset "to_sexpr — herbie/bench/numerics/rosa.fpcore" begin
    # sin(x) - x — Taylor cancellation near x=0
    @test EggFFI.to_sexpr(sin(x) - x)                   == "(- (sin x) x)"

    # Doppler-style: subtraction in denominator
    @test EggFFI.to_sexpr(x / (x - y))                  == "(/ x (- x y))"
end

@testset "to_sexpr — herbie/bench/mathematics/statistics.fpcore" begin
    # "2-ancestry mixing": sqrt(a^2 - b^2) — subtraction under sqrt
    @test EggFFI.to_sexpr(sqrt(a^2 - b^2))              == "(sqrt (- (^ a 2) (^ b 2)))"

    # cbrt of expression with subtraction
    @test EggFFI.to_sexpr(cbrt(a - b))                  == "(cbrt (- a b))"
end
