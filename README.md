# EggFFI.jl

Julia bindings to [egg](https://egraphs-good.github.io/egg/) for numerical accuracy optimization of symbolic expressions — SciML Summer Fellowship 2026.

## Project Structure

```
EggFFI.jl/               ← Julia package (ccall wrappers)
  src/EggFFI.jl
  test/runtests.jl
  Project.toml

egg-julia-ffi/           ← Rust FFI crate
  src/lib.rs
  Cargo.toml
```

## Quick Start

```julia
# build the Rust crate first
# cd egg-julia-ffi && cargo build --release

include("EggFFI.jl/src/EggFFI.jl")
using .EggFFI

ptr    = egraph_create("(- (sqrt (+ x 1.0)) (sqrt x))")
egraph_saturate!(ptr)
result = egraph_extract(ptr)
egraph_destroy(ptr)
println(result)
```

## Current Work

**Week 3 — BinaryBuilder cross-compilation**

