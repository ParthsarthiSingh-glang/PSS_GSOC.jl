using Symbolics
include("E:/PSS_GSOC.jl/Jerbie.jl/src/Jerbie.jl")
using .Jerbie
@variables x

function test_case(expr, rat_sexpr, label)
    ptr = egraph_create(to_sexpr(expr))
    egraph_saturate!(ptr)
    reason  = egraph_stop_reason(ptr)
    classes = egraph_size(ptr)
    result  = egraph_contains(ptr, rat_sexpr)

    println("[$label] stop=$reason | eclasses=$classes | $(result !== nothing ? "YES eclass=$result" : "NO")")

    if result !== nothing
        canon = egraph_find(ptr, result)
        for e in egraph_eclass_enodes(ptr, canon)
            println("  -> $e")
        end
    end

    egraph_destroy(ptr)
end

cases = [
    (1,   0),
    (2,   0),
    (0,   1),
    (0,   2),
    (3,   2),
    (3,   -2),
    (-2,  3),
    (-3,  -2),
]

for (a, b) in cases
    if b == 0
        expr = sqrt(x + a) - sqrt(x)
        sa   = to_sexpr(sqrt(x + a))
        sb   = to_sexpr(sqrt(x))
        num  = a
    elseif a == 0
        expr = sqrt(x) - sqrt(x + b)
        sa   = to_sexpr(sqrt(x))
        sb   = to_sexpr(sqrt(x + b))
        num  = -b
    else
        expr = sqrt(x + a) - sqrt(x + b)
        sa   = to_sexpr(sqrt(x + a))
        sb   = to_sexpr(sqrt(x + b))
        num  = a - b
    end

    rat_sexpr = "(/ $num (+ $sa $sb))"
    test_case(expr, rat_sexpr, "a=$a,b=$b")
    println()
end
