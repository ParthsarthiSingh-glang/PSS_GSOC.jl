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
# → "(/ 1 (+ (sqrt (+ 1 x)) (sqrt x)))"
```

## Current Goal

A Symbolics expression goes in, rewrite rules run inside egg, and a better Symbolics expression comes out.

```julia
@variables x
optimize_accuracy(sqrt(x + 1) - sqrt(x))
# goal → 1 / (sqrt(x+1) + sqrt(x))   ← the numerically stable form
```

## Next Steps

**Fix `to_sexpr`**

Right now Symbolics represents `a - b` internally as `Add(a, Mul(-1, b))` — there is no explicit `Sub` node. So `to_sexpr` currently emits `(+ a (* -1 b))` instead of `(- a b)`.

Herbie's rules ([rules.rkt](https://github.com/herbie-fp/herbie/blob/main/src/core/rules.rkt)) are all written with explicit `(- a b)` and `(neg a)` forms. To port them directly without rewriting every pattern, `to_sexpr` needs to detect `Add(a, Mul(-1, b))` and emit `(- a b)`, and detect `Mul(-1, a)` and emit `(neg a)`.

Evidence: `SymbolicUtils.jl/src/terminterface.jl` — `arguments()` for `AddMul.ADD` wraps each term as `Mul(coeff, term)`. Detection via `ismul` and `get_mul_coefficient` from `SymbolicUtils.jl/src/types.jl`.

**Add `neg` to `MathLang`**

Herbie has an explicit `Neg` unary node (`herbie/egg-herbie/src/math.rs`: `"neg" = Neg([Id; 1])`). Our `MathLang` in `lib.rs` needs `"neg" = Neg(Id)` so egg can parse `(neg a)` from `to_sexpr`.

**Port rules from Herbie directly**

Once `to_sexpr` emits proper `(- a b)` and `(neg a)`, Herbie's rules port straight to Rust without adaptation.

## Known Limitations

- `to_sexpr` emits `(+ a (* -1 b))` for subtraction — blocks direct use of Herbie's rules. Fix in progress.
- `to_sexpr` breaks for expressions like `x + y + z` — egg expects `+` to take exactly 2 arguments. Fix deferred.
- `from_sexpr` not done yet — `optimize_expr` returns a string, not a Symbolics expression.

## References

- [egg crate](https://crates.io/crates/egg) (v0.11.0)
- [Herbie](https://herbie.uwplse.org/)
- [Herbie rules](https://github.com/herbie-fp/herbie/blob/main/src/core/rules.rkt)
- [TermInterface.jl](https://github.com/JuliaSymbolics/TermInterface.jl)
- [Julia ccall docs](https://docs.julialang.org/en/v1/manual/calling-c-and-fortran-code/)
