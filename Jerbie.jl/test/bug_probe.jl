include(joinpath(@__DIR__, "..", "src", "Jerbie.jl"))
using .Jerbie
using Symbolics

# Does REAL egg rewriting (not a hand-built expression) ever actually produce
# the dangerous (^ base (/ num compound-denom)) shape from an innocent input
# that never wrote a "^" at all?
#
# "exp-to-pow" (herbie_rules.rs): (exp (* (log ?a) ?b)) => (^ ?a ?b) is an
# UNCONDITIONAL rewrite. If ?b is already a division with a multi-term
# denominator, this manufactures exactly the risky shape mid-rewrite.
#
# rewrite_variations does real saturation (no single-variable constraint --
# that's a sampling-layer restriction, unrelated to this), so this tests
# actual reachability through the real rule set, not a synthetic expression.

@variables a x y z
expr = Num(exp(log(a) * (x / (y + z))))
vars = Dict{String, Num}("a" => Num(a), "x" => Num(x), "y" => Num(y), "z" => Num(z))

println("input expr    = ", expr)
println("input to_sexpr = ", to_sexpr(expr))
println()

variations = rewrite_variations(expr, vars)
println("rewrite_variations found ", length(variations), " variations")
println()

found_risky_shape = false
for v in variations
    s = to_sexpr(v)
    println("variation: ", s)
    try
        cost = ast_size_cost(v)
        println("    cost = ", cost)
    catch e
        println("    CRASHED: ", sprint(showerror, e))
        println("    exception type: ", typeof(e))
        global found_risky_shape = true
    end
end

println()
println(found_risky_shape ?
    "CONFIRMED: real rewriting produced the risky shape and crashed ast_size_cost." :
    "Not reproduced this way -- rewriting didn't happen to produce that exact shape here.")
