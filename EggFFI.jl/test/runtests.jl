using Test
using Symbolics

include("../src/EggFFI.jl")
using .EggFFI

@variables x y z

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
    # MUL: coeff=-1, single term → (neg term)
    @test EggFFI.to_sexpr(-sin(x))          == "(neg (sin x))"
    @test EggFFI.to_sexpr(-cos(x))          == "(neg (cos x))"
    @test EggFFI.to_sexpr(-log(x))          == "(neg (log x))"
    @test EggFFI.to_sexpr(-sqrt(x))         == "(neg (sqrt x))"
    @test EggFFI.to_sexpr(-x)               == "(neg x)"
    @test EggFFI.to_sexpr(-(x^2))           == "(neg (^ x 2))"
    # -2x → coeff=-2, NOT negation → (* -2 x)
    @test EggFFI.to_sexpr(-2x)              == "(* -2 x)"
    # -(x+1) → ADD: coeff=-1, dict={x=>-1} → both negative → fallback
    @test EggFFI.to_sexpr(-(x + 1))         == "(+ -1 (neg x))"
end

@testset "to_sexpr — subtraction Case 1: coeff=0, one +1 and one -1 in dict" begin
    @test EggFFI.to_sexpr(x - y)                        == "(- x y)"
    @test EggFFI.to_sexpr(sin(x) - cos(x))              == "(- (sin x) (cos x))"
    @test EggFFI.to_sexpr(sqrt(x + 1) - sqrt(x))        == "(- (sqrt (+ 1 x)) (sqrt x))"
    @test EggFFI.to_sexpr(log(x + 1) - log(x))          == "(- (log (+ 1 x)) (log x))"
    @test EggFFI.to_sexpr(sin(x)^2 - cos(x)^2)         == "(- (^ (sin x) 2) (^ (cos x) 2))"
    @test EggFFI.to_sexpr(sqrt(x + 1) - sqrt(x + 2))   == "(- (sqrt (+ 1 x)) (sqrt (+ 2 x)))"
    @test EggFFI.to_sexpr(x^2 - x)                      == "(- (^ x 2) x)"
    # with non-unit coefficients
    @test EggFFI.to_sexpr(2x - 3y)                      == "(- (* 2 x) (* 3 y))"
end

@testset "to_sexpr — subtraction Case 2: coeff<0, one +1 term in dict" begin
    # x - 1 → coeff=-1, {x=>1} → (- x 1)
    @test EggFFI.to_sexpr(x - 1)                        == "(- x 1)"
    @test EggFFI.to_sexpr(x^2 - 1)                      == "(- (^ x 2) 1)"
    @test EggFFI.to_sexpr(sin(x) - 1)                   == "(- (sin x) 1)"
    @test EggFFI.to_sexpr(sqrt(x) - 1)                  == "(- (sqrt x) 1)"
    @test EggFFI.to_sexpr(sqrt(x^2 - 1))                == "(sqrt (- (^ x 2) 1))"
end

@testset "to_sexpr — subtraction Case 3: coeff>0, one -1 term in dict" begin
    # 1 - x → coeff=1, {x=>-1} → (- 1 x)
    @test EggFFI.to_sexpr(1 - x)                        == "(- 1 x)"
    @test EggFFI.to_sexpr(1 - sin(x))                   == "(- 1 (sin x))"
end

@testset "to_sexpr — complex nested expressions" begin
    @test EggFFI.to_sexpr(log(x^2) - log(x))             == "(- (log (^ x 2)) (log x))"
    @test EggFFI.to_sexpr(sqrt(x + y) - sqrt(x - y))    == "(- (sqrt (+ x y)) (sqrt (- x y)))"
    @test EggFFI.to_sexpr(sin(x + y) - cos(y + z))      == "(- (sin (+ x y)) (cos (+ y z)))"
    @test EggFFI.to_sexpr(log(sqrt(x+1)) - log(sqrt(x))) == "(- (log (sqrt (+ 1 x))) (log (sqrt x)))"
end

@testset "to_sexpr — edge cases" begin
    @test EggFFI.to_sexpr(x - x)                        == "0"
    @test EggFFI.to_sexpr(sqrt(x + 100) - sqrt(x))      == "(- (sqrt (+ 100 x)) (sqrt x))"
    @test EggFFI.to_sexpr(-(-sin(x)))                    == "(sin x)"
end
