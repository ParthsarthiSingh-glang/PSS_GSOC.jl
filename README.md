# EggFFI.jl

Julia bindings to [egg](https://egraphs-good.github.io/egg/) for numerical accuracy optimization of symbolic expressions — SciML Summer Fellowship 2026. The end goal: a user writes `optimize_accuracy(expr)` on a Symbolics.jl expression and gets back a numerically better equivalent.

## Project Structure

```text
EggFFI.jl/
  src/EggFFI.jl      
  src/converter.jl    
  test/runtests.jl     
  Project.toml

egg-julia-ffi/
  src/lib.rs         
  Cargo.toml
```

## Pipeline

```text
Symbolics expr
    ↓  to_sexpr          — reads AddMul coeff/dict (SymbolicUtils/src/types.jl)
s-expression string
    ↓  egraph_create     — Rust: string → RecExpr → EGraph
    ↓  egraph_saturate!  — Rust: rewrite rules until saturation
    ↓  egraph_extract    — Rust: cost function → best expression
    ↓  egraph_destroy    — Rust: free heap
    ↓  from_sexpr        — string → Symbolics.Num via maketerm (TermInterface.jl)
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
```

Variables are extracted automatically via `Symbolics.get_variables`. For explicit control, pass a `Dict{String, Num}` directly:

```julia
EggFFI.optimize_expr(sqrt(x + 1) - sqrt(x), Dict("x" => x))
```

## E-Graph Accessories

Introspection functions available after `egraph_saturate!`:

| Function | Returns | Description |
|---|---|---|
| `egraph_size(ptr)` | `UInt32` | Number of e-classes |
| `egraph_total_size(ptr)` | `UInt32` | Total unique e-nodes across all e-classes (`memo.len()`) |
| `egraph_eclass_size(ptr, id)` | `UInt32` | Number of equivalent e-nodes in a given e-class |
| `egraph_find(ptr, id)` | `UInt32` |  Id for a given id (union-find lookup) |
| `egraph_root_id(ptr)` | `UInt32` | Id of the root e-class |
| `egraph_stop_reason(ptr)` | `Symbol` | Why saturation stopped — `:Saturated`, `:IterationLimit`, `:NodeLimit`, `:TimeLimit`, `:Other` |
| `egraph_contains(ptr, expr)` | `Union{UInt32, Nothing}` | Eclass id if a Symbolics expression is present, `nothing` if not |
| `egraph_extract(ptr)` | `String` | Best expression by `AstSize` cost |
| `egraph_pretty_extract(ptr; width)` | `String` | Same as extract but pretty-printed with line breaks at `width` chars |

## References

- [egg crate](https://crates.io/crates/egg) (v0.11.0)
- [Herbie](https://herbie.uwplse.org/) — [rules.rkt](https://github.com/herbie-fp/herbie/blob/main/src/core/rules.rkt)
- [TermInterface.jl](https://github.com/JuliaSymbolics/TermInterface.jl)
- [SymbolicUtils.jl](https://github.com/JuliaSymbolics/SymbolicUtils.jl)
- [Symbolics.jl parsing](https://docs.sciml.ai/Symbolics/stable/manual/parsing/)
- [Metatheory.jl](https://github.com/JuliaSymbolics/Metatheory.jl)
- [SymbolicRegression.jl](https://github.com/MilesCranmer/SymbolicRegression.jl)
- [Reduce.jl](https://github.com/chakravala/Reduce.jl)
- [Julia ccall docs](https://docs.julialang.org/en/v1/manual/calling-c-and-fortran-code/)

## AI Assistance

Developed with assistance from [Claude Pro](https://claude.ai) (Anthropic). We tried writing a fuzz test suite for the converter with AI assistance, but the generated tests had issues and fuzzing is skipped for now.
