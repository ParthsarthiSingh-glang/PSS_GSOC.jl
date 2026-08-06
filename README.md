# Jerbie.jl

Jerbie.jl is a Julia/Rust tool for automatically improving the floating-point
accuracy of numerical expressions, using equality saturation (via
[egg](https://egraphs-good.github.io/)) to search for mathematically
equivalent rewrites and real point-sampling (via
[rival](https://github.com/herbie-fp/rival3)) to score each candidate's
accuracy. It follows the same search+score methodology as
[Herbie](https://herbie.uwplse.org/).

## Installation

Jerbie.jl is not yet a registered Julia package. Until then, install it
directly from source:

```julia
using Pkg
Pkg.develop(url = "https://github.com/JuliaSymbolics/Jerbie.jl.git", subdir = "Jerbie.jl")
```

Jerbie's e-graph search runs through a Rust backend (`egg-jerbie/`) that must
be built locally before use — a prebuilt binary distribution (via
BinaryBuilder/`Jerbie_jll`) is planned but not yet available:

```bash
cd egg-jerbie
cargo build --release
```

## Documentation

See the [dev documentation](https://juliasymbolics.github.io/Jerbie.jl/dev/)
for the full API reference and internals guide. It is rebuilt automatically
on every push to `main`.

## Relationship to Other Packages

- [`egg-jerbie`](egg-jerbie/) — this repo's own Rust crate, a thin FFI layer
  around the [`egg`](https://crates.io/crates/egg) equality-saturation
  library. Jerbie.jl calls into it via `ccall` to build, saturate, and
  extract from e-graphs; the rewrite rule set (`egg-jerbie/src/herbie_rules.rs`)
  is adapted from Herbie's own rules.
- [`rival3`](https://github.com/herbie-fp/rival3) — a Rust dependency of
  `egg-jerbie`, used to evaluate each rewrite candidate against real-valued
  sample points to score its floating-point accuracy.

  **Why not a Julia-native solution?** Scoring runs 256 train + 8000 test
  sample points per candidate, per benchmark — doing this in Rust alongside
  the e-graph avoids FFI round-trips for that whole workload. `rival3` is
  also a direct Rust port of Herbie's own `rival` library, so it's proven
  methodology rather than a from-scratch reimplementation of floating-point
  edge cases (which are notoriously easy to get subtly wrong). It also
  directly handles problems that don't currently have a solved Julia-side
  answer, e.g. [fast ULP distance between two floats](https://discourse.julialang.org/t/calculating-ulp-distance-between-two-floating-point-numbers-quickly/61581/3)
  and sound domain-finding for an expression's variables.
- [Herbie](https://herbie.uwplse.org/) — the Racket tool this project's
  search+score approach is directly modeled on. Herbie solves the same
  problem (find a more accurate equivalent of a floating-point expression);
  Jerbie.jl re-implements that methodology for the Julia/Symbolics.jl
  ecosystem, on top of `egg` rather than Herbie's own e-graph implementation.

## Example

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

See the [documentation](https://juliasymbolics.github.io/Jerbie.jl/dev/) for
the full walkthrough, including `run_improve_with_report` and the lower-level
e-graph/scoring primitives Jerbie.jl is built from.

## Citation

Jerbie.jl builds directly on the following prior work:

```bibtex
@article{2021-egg,
  author     = {Willsey, Max and Nandi, Chandrakana and Wang, Yisu Remy and Flatt, Oliver and Tatlock, Zachary and Panchekha, Pavel},
  title      = {egg: Fast and Extensible Equality Saturation},
  year       = {2021},
  journal    = {Proc. ACM Program. Lang.},
  volume     = {5},
  number     = {POPL},
  articleno  = {23},
  doi        = {10.1145/3434304},
  url        = {https://doi.org/10.1145/3434304}
}

@misc{flatt2021interval,
  author        = {Flatt, Oliver and Panchekha, Pavel},
  title         = {An Interval Arithmetic for Robust Error Estimation},
  year          = {2021},
  eprint        = {2107.05784},
  archivePrefix = {arXiv},
  primaryClass  = {math.NA},
  url           = {https://arxiv.org/abs/2107.05784}
}

@inproceedings{panchekha2015herbie,
  author    = {Panchekha, Pavel and Sanchez-Stern, Alex and Wilcox, James R. and Tatlock, Zachary},
  title     = {Automatically Improving Accuracy for Floating Point Expressions},
  booktitle = {Proceedings of the 36th ACM SIGPLAN Conference on Programming Language Design and Implementation},
  series    = {PLDI '15},
  year      = {2015},
  pages     = {1--11},
  doi       = {10.1145/2737924.2737959},
  url       = {https://dl.acm.org/doi/10.1145/2737924.2737959}
}
```

## Author

@ParthsarthiSingh-glang

## AI Assistance

Developed with assistance from Claude (Anthropic). Especially for test
generation, parsing, and documentation.
