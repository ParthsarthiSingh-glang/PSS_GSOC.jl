include(joinpath(@__DIR__, "..", "src", "Jerbie.jl"))
using .Jerbie
using Symbolics
import Logging

# sqrt_D: (sqrt(x+1) - 1) / x -- fixed earlier this session via the
# flip-sqrt-lit-- rule ((- (sqrt a) c) => rep(...)), so we already know
# the real rule name that should show up in the derivation's proof text.
@variables x
expr = (sqrt(x + 1) - 1) / x

report = Logging.with_logger(Logging.NullLogger()) do
    run_improve_with_report(Num(expr), [x])
end

winner_key = to_sexpr(report.winner)
steps = report.derivations[winner_key]

println("winner: ", report.winner)
println("start_score: ", start_score(report), "  end_score: ", end_score(report))
println("derivation (", length(steps), " steps):")
print_derivation(steps)

has_flip_rule = any(steps) do s
    s.kind == :rewrite && s.proof !== nothing && any(line -> occursin("flip-sqrt-lit", line), s.proof)
end
println()
println("contains flip-sqrt-lit-- in proof chain: ", has_flip_rule)

println()
println("=== alternatives' derivation kinds ===")
for alt in report.alternatives
    key = to_sexpr(alt)
    alt_steps = report.derivations[key]
    kinds = [s.kind for s in alt_steps]
    println(alt, " -> ", isempty(kinds) ? "(no rewrite, is root)" : kinds)
end
