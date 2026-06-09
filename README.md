# EggFFI.jl

Julia bindings to [egg](https://egraphs-good.github.io/egg/) for numerical accuracy optimization of symbolic expressions — SciML Summer Fellowship 2026.

The end goal: a user writes `optimize_accuracy(expr)` on a Symbolics.jl expression and gets back a numerically better equivalent.

## Project Structure

```
EggFFI.jl/
  src/EggFFI.jl        ← ccall wrappers + optimize_expr pipeline
  src/converter.jl     ← to_sexpr: Symbolics expr → s-expression string
  test/runtests.jl     ← structural tests + Herbie benchmark expressions
  Project.toml

egg-julia-ffi/
  src/lib.rs           ← MathLang (150+ nodes), EGraphWithRoot, FFI functions
  Cargo.toml
```

## Pipeline

```
Symbolics expr
    ↓  to_sexpr          — reads AddMul coeff/dict (SymbolicUtils/src/types.jl)
s-expression string
    ↓  egraph_create     — Rust: string → RecExpr → EGraph
    ↓  egraph_saturate!  — Rust: rewrite rules until saturation
    ↓  egraph_extract    — Rust: cost function → best expression
    ↓  egraph_destroy    — Rust: free heap
    ↓  from_sexpr        — string → Symbolics expr [next]
Symbolics expr (optimized)
```

## Quick Start

```julia
# build Rust crate first: cd egg-julia-ffi && cargo build --release

using Pkg; Pkg.activate(".")
include("src/EggFFI.jl")
using Symbolics

@variables x
EggFFI.optimize_expr(sqrt(x + 1) - sqrt(x))
# → "(/ 1 (+ (sqrt (+ 1 x)) (sqrt x)))"
```

## Done

**Phase 1 — FFI layer**
- `MathLang` (150+ nodes) + 4 C-exported functions in `egg-julia-ffi/src/lib.rs`
- Julia `ccall` wrappers in `EggFFI.jl`
- Round-trip verified: s-expression → egg → saturate → extract → string

**Phase 2 — `to_sexpr` ([PR #4](https://github.com/ParthsarthiSingh-glang/PSS_GSOC.jl/pull/4))**
- Reads `coeff` and `dict` directly from `AddMul` nodes — `SymbolicUtils/src/types.jl`
- Emits `(- a b)` for subtraction and `(neg a)` for negation — matching Herbie rule patterns (`herbie/src/core/rules.rkt`)
- Added `"neg" = Neg(Id)` to `MathLang` — matching `herbie/egg-herbie/src/math.rs`
- Tests cover structural cases + Herbie benchmark expressions (`herbie/bench/`)

**Demo**

```julia
@variables x
EggFFI.optimize_expr(sqrt(x + 1) - sqrt(x))
# → "(/ 1 (+ (sqrt (+ 1 x)) (sqrt x)))"
```

## Next Steps

- **Port Herbie rules** — `to_sexpr` now emits `(- a b)` so rules from `herbie/src/core/rules.rkt` port directly (`flip--`, `diff-log`, `sum-log`, FMA transforms)
- **`from_sexpr`** — parse result string back to `Symbolics.Num` via `maketerm` (`SymbolicUtils/src/terminterface.jl`)
- **Constant folding** — `ConstantFolding` Analysis in egg (`egg/src/language.rs`) to simplify numerators
- **Sampling cost function** — replace `StabilityCost` with Float64 vs BigFloat accuracy sampling (Phase 4)

## References

- [egg crate](https://crates.io/crates/egg) (v0.11.0)
- [Herbie](https://herbie.uwplse.org/) — [rules.rkt](https://github.com/herbie-fp/herbie/blob/main/src/core/rules.rkt)
- [TermInterface.jl](https://github.com/JuliaSymbolics/TermInterface.jl)
- [SymbolicUtils.jl](https://github.com/JuliaSymbolics/SymbolicUtils.jl)
- [Julia ccall docs](https://docs.julialang.org/en/v1/manual/calling-c-and-fortran-code/)

## AI Assistance

Developed with assistance from [Claude Pro](https://claude.ai) (Anthropic) — used for reading source across SymbolicUtils.jl, egg, and Herbie repos, debugging FFI issues, and writing tests.
