# Jerbie.jl

Jerbie.jl is a Julia/Rust tool for automatically improving the floating-point
accuracy of numerical expressions, using equality saturation (via
[egg](https://egraphs-good.github.io/)) to search for mathematically
equivalent rewrites and real point-sampling (via
[rival](https://github.com/herbie-fp/rival3)) to score each candidate's
accuracy. It follows the same search+score methodology as
[Herbie](https://herbie.uwplse.org/).

## Quick start

Expressions are written as ordinary Julia code over
[Symbolics.jl](https://symbolics.juliasymbolics.org/) variables:

```julia
using Symbolics, Jerbie

@variables x
result = optimize_expr(sqrt(x + 1) - sqrt(x))
```

This runs the full search (guided by equality saturation) and scores every
candidate against 8000 held-out sample points, printing a summary:

```
*********************************************************************
input: sqrt(1 + x) - sqrt(x)
alternatives:
  [1] 1 / (sqrt(1 + x) + sqrt(x))
  [2] 1 / (1 + sqrt(x))
  [3] sqrt(1 + x) - sqrt(x)
start_score (bits-of-error, original): 29.658448391155197
end_score   (bits-of-error, winner):    0.1634530078147536
```

The scores are bits-of-error (lower is better) — the winning alternative here
recovers about 29.5 bits of accuracy lost to catastrophic cancellation in the
original expression, near `x = 0`.

`result` itself is a `NamedTuple` with everything needed to inspect or reuse
the run:

```julia
julia> propertynames(result)
(:alternatives, :start_score, :end_score, :test_context)
```

- `alternatives` — the ranked `Vector{Num}` of rewrites shown above
  (`alternatives[1]` is the winner).
- `start_score` / `end_score` — the same bits-of-error numbers from the
  summary.
- `test_context` — the held-out sample points (a [`SampleContext`](@ref)) the
  scores were computed against, reusable for scoring your own candidate
  expressions on the same points via [`points_errors`](@ref).

Pass `verbose = false` to suppress the printed summary (used internally for
batch/programmatic runs):

```julia
optimize_expr(sqrt(x + 1) - sqrt(x); verbose = false)
```

## Under the hood

`optimize_expr` is a thin wrapper around [`run_improve_with_report`](@ref),
which does the actual search and returns an [`ImprovementReport`](@ref) with
more detail (including the full [`DerivationStep`](@ref) rewrite-proof chain
for the winner):

```julia
julia> report = run_improve_with_report(sqrt(x + 1) - sqrt(x), [x]);

julia> propertynames(report)
(:winner, :alternatives, :start_errors, :end_errors, :test_context, :derivations)

julia> start_score(report), end_score(report)
(29.41868879596992, 0.16806860937770432)
```

Calling `run_improve_with_report` directly is useful when you want the
per-point error vectors (`start_errors`/`end_errors`) rather than just their
mean, or want to walk the `derivations` proof chain explaining *why* the
winner is equivalent to the input. See the [API](@ref) page for the full
list of exported functions, including the lower-level e-graph
(`egraph_create`/`egraph_saturate!`/...) and scoring
(`sample_context`/`points_errors`/`errors_score`) primitives these are built
from.
