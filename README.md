# EggFFI.jl

Julia bindings to [egg](https://egraphs-good.github.io/egg/) for numerical accuracy optimization of symbolic expressions — SciML Summer Fellowship 2026.

The end goal: a user writes `optimize_accuracy(expr)` on a Symbolics.jl expression and gets back a numerically better equivalent.

## Project Structure

```
EggFFI.jl/               ← Julia package (ccall wrappers + expression converter)
  src/EggFFI.jl          ← module, ccall wrappers, optimize_expr pipeline
  src/converter.jl       ← to_sexpr: Symbolics expr → s-expression string
  test/runtests.jl
  Project.toml

egg-julia-ffi/           ← Rust FFI crate
  src/lib.rs             ← MathLang (150+ nodes), EGraphWithRoot, 4 C-exported functions
  Cargo.toml
```

## Pipeline

```
Symbolics expr (EX)
       ↓  to_sexpr(EX)          — TermInterface: iscall, operation, sorted_arguments
  s-expression string
       ↓  egraph_create(s)      — Rust: parse string → RecExpr → EGraph
  Ptr{Cvoid}
       ↓  egraph_saturate!(ptr) — Rust: apply rewrite rules until saturation
  Ptr{Cvoid} (modified in place)
       ↓  egraph_extract(ptr)   — Rust: cost function → best RecExpr → string
  s-expression string
       ↓  egraph_destroy(ptr)   — Rust: free heap memory
       ↓  from_sexpr(ans)       — string → Symbolics expr [next]
  Symbolics expr (optimized)
```

## Quick Start

```julia
# 1. build the Rust crate first
# cd egg-julia-ffi && cargo build --release

# 2. in Julia REPL from EggFFI.jl/
using Pkg; Pkg.activate(".")
include("src/EggFFI.jl")
using Symbolics

@variables x
EggFFI.optimize_expr(sqrt(x + 1) - sqrt(x))
# → "(+ (sqrt (+ 1 x)) (* -1 (sqrt x)))"

EggFFI.optimize_expr(log(1 + x) - log(x))
# → "(+ (log (+ 1 x)) (* -1 (log x)))"

EggFFI.optimize_expr(sin(x))
# → "(sin x)"
```

## Current Goal

A Symbolics expression goes in, rewrite rules run inside egg, and a better Symbolics expression comes out.

```julia
@variables x
optimize_accuracy(sqrt(x + 1) - sqrt(x))
# goal → 1 / (sqrt(x+1) + sqrt(x))   ← the numerically stable form
```

## Known Limitations

- `to_sexpr` breaks for expressions like `x + y + z` because egg expects `+` to take exactly 2 arguments. Current is only for args.length<=2
- `from_sexpr` not done yet — `optimize_expr` returns a string, not a Symbolics expression.

## References

- [egg crate](https://crates.io/crates/egg) (v0.11.0)
- [Herbie](https://herbie.uwplse.org/)
- [TermInterface.jl](https://github.com/JuliaSymbolics/TermInterface.jl)
- [Julia ccall docs](https://docs.julialang.org/en/v1/manual/calling-c-and-fortran-code/)
