# Jerbie.jl

Julia bindings to [egg](https://egraphs-good.github.io/egg/) for numerical accuracy optimization of symbolic expressions — SciML Summer Fellowship 2026. The end goal: a user writes `optimize_accuracy(expr)` on a Symbolics.jl expression and gets back a numerically better equivalent.

---
## Project Structure
```text
Jerbie.jl/
├── src/
│   ├── Jerbie.jl
│   ├── converter.jl
│   ├── sampling.jl
│   ├── taylor.jl
│   ├── alttable.jl
│   ├── mainloop.jl
│   ├── pareto.jl
│   └── rules.jl
│
├── test/
│   ├── runtests.jl
│   ├── egraphtests.jl
│   ├── fpcore_tests.jl
│   ├── fpcore_bench.jl
│   └── compare_herbie.jl
│
egg-julia-ffi/
├── src/
│   ├── lib.rs
│   ├── herbie_rules.rs
│   ├── domain_search.rs
│   ├── discretization.rs
│   ├── to_rival.rs
│   └── my_rules.rs
└── Cargo.toml
```
---

## Pipeline
```text
run_improve_with_report(expr, [x])
    │
    ├─► Preprocessing & Sampling  (sampling.jl)
    │     • Generates SampleContext & preprocesses initial expression
    │     • Initializes AltTable with initial candidate
    │
    └─► Main Iterative Loop (mainloop.jl — up to NUM_ITERATIONS)
          │
          ├─► Candidate Generation:
          │     1. Shared E-Graph Saturation (rewrite_variations_batch):
          │        Inserts ALL pending alternatives into ONE SHARED E-Graph ,
          │        saturates once  and extracts variations per root.
          │     2. Symbolic Taylor Series (taylor.jl):
          │        Generates polynomial expansions around 0, ∞, -∞.
          │
          ├─► Scoring & Evaluation (sampling.jl):
          │        Evaluates ULP error for each candidate over SampleContext.
          │
          ├─► Candidate Selection & Pruning (alttable.jl / pareto.jl):
          │        Applies Greedy Set-Cover and Pareto pruning to select active alternatives.
          │
          └─► Winner Extraction (extract!):
                   Selects the best expression balancing ULP error score and AST size cost.
```
---

## Quick Start
### 1. Build the Rust Backend
Compile the `egg-julia-ffi` Rust library:
```bash
cd egg-julia-ffi
cargo build --release
cd ..
```
### 2. Run in Julia
```julia
using Pkg
Pkg.activate("Jerbie.jl")
include("Jerbie.jl/src/Jerbie.jl")
using .Jerbie
using Symbolics
@variables x
expr1 = sqrt(x + 1) - sqrt(x)
report1 = run_improve_with_report(expr1, [x])
println("Original:  ", expr1)
println("Winner:    ", report1.winner)
println("ULP Score: ", start_score(report1), " -> ", end_score(report1))

```
---

## References

- [egg crate](https://crates.io/crates/egg) (v0.11.0)
- [Herbie](https://herbie.uwplse.org/) — [rules.rkt](https://github.com/herbie-fp/herbie/blob/main/src/core/rules.rkt)
- [TermInterface.jl](https://github.com/JuliaSymbolics/TermInterface.jl)
- [SymbolicUtils.jl](https://github.com/JuliaSymbolics/SymbolicUtils.jl)
- [Symbolics.jl parsing](https://docs.sciml.ai/Symbolics/stable/manual/parsing/)
- [Metatheory.jl](https://github.com/JuliaSymbolics/Metatheory.jl)
- [Julia ccall docs](https://docs.julialang.org/en/v1/manual/calling-c-and-fortran-code/)

## Author :

@ParthsarthiSingh-glang

## AI Assistance

Developed with assistance from Claude (Anthropic). Especially for test generation , parsing , etc.
