module EggFFI

using TermInterface
using Symbolics

# compile lib.rs and DIR where (.dll on Windows, .so on Linux, .dylib on Mac) lives
const LIBPATH = joinpath(@__DIR__, "..", "..", "egg-julia-ffi", "target", "release", "egg_julia_ffi")

include("converter.jl")

export egraph_create, egraph_saturate!, egraph_extract, egraph_destroy, optimize_expr

"""
    egraph_create(expr::String) -> Ptr{Cvoid}

    Symbolic expression parsing -> Egraph creation -> returns a pointer.
"""
function egraph_create(expr::String)::Ptr{Cvoid}
    ccall((:egraph_create, LIBPATH), Ptr{Cvoid}, (Cstring,), expr)
end

"""
    egraph_saturate!(ptr::Ptr{Cvoid})

    Apply rewrite rules to the e-graph until saturation.
    Rules will we done in Phase-3 . 
"""
function egraph_saturate!(ptr::Ptr{Cvoid})
    ccall((:egraph_saturate, LIBPATH), Cvoid, (Ptr{Cvoid},), ptr)
end

"""
    egraph_extract(ptr::Ptr{Cvoid}) -> String

    Extract the best expression for that 'Root' from the e-graph and return it as a string.
    Cost Function (Phase - 4) is used to determine the best expression.
"""
function egraph_extract(ptr::Ptr{Cvoid})::String
    raw = ccall((:egraph_extract, LIBPATH), Cstring, (Ptr{Cvoid},), ptr)
    unsafe_string(raw)
end

"""
    egraph_destroy(ptr::Ptr{Cvoid})

    Free the EGraphWithRoot struct on the Rust heap.
    Call exactly once when done with ptr — do not use ptr after this.
"""
function egraph_destroy(ptr::Ptr{Cvoid})
    ccall((:egraph_destroy, LIBPATH), Cvoid, (Ptr{Cvoid},), ptr)
end

"""
    optimize_expr(expr) -> String

    Full pipeline: Symbolics expr -> s-expression -> egraph -> saturate -> extract -> string.
    Returns optimized s-expression string (from_sexpr comes in next commit).
    No rules yet (Phase 3) — returns same expression back for now.
"""
function optimize_expr(expr)::String
    s   = to_sexpr(expr)
    ptr = egraph_create(s)
    egraph_saturate!(ptr)
    res = egraph_extract(ptr)
    egraph_destroy(ptr)
    return res
end

end
