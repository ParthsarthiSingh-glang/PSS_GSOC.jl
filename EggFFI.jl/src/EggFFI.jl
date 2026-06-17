module EggFFI

using TermInterface
using Symbolics
using SymbolicUtils

# compile lib.rs and DIR where (.dll on Windows, .so on Linux, .dylib on Mac) lives
const LIBPATH = joinpath(@__DIR__, "..", "..", "egg-julia-ffi", "target", "release", "egg_julia_ffi")

include("converter.jl")

export egraph_create, egraph_saturate!, egraph_stop_reason,
       egraph_extract, egraph_pretty_extract, egraph_destroy,
       optimize_expr, from_sexpr, to_sexpr,
       egraph_size, egraph_total_size, egraph_contains,
       egraph_eclass_size, egraph_find, egraph_root_id,
       ExactInfinityError

"""
    egraph_create(expr::String) -> Ptr{Cvoid}

    Symbolic expression parsing -> Egraph creation -> returns a pointer.
"""
function egraph_create(expr::String)::Ptr{Cvoid}
    ccall((:egraph_create, LIBPATH), Ptr{Cvoid}, (Cstring,), expr)
end

"""
    egraph_saturate!(ptr::Ptr{Cvoid})

    Apply rewrite rules with default limits (iter=30, nodes=10_000, time=5s).
    Check egraph_stop_reason() after to see why saturation stopped.
"""
function egraph_saturate!(ptr::Ptr{Cvoid})
    ccall((:egraph_saturate, LIBPATH), Cvoid, (Ptr{Cvoid},), ptr)
end

"""
    egraph_stop_reason(ptr::Ptr{Cvoid}) -> Symbol

    Returns the reason saturation stopped:
    :Saturated | :IterationLimit | :NodeLimit | :TimeLimit | :Other
"""
function egraph_stop_reason(ptr::Ptr{Cvoid})::Symbol
    code = ccall((:egraph_stop_reason, LIBPATH), UInt8, (Ptr{Cvoid},), ptr)
    return [:Saturated, :IterationLimit, :NodeLimit, :TimeLimit, :Other][code + 1]
end

"""
    egraph_extract(ptr::Ptr{Cvoid}) -> String

    Extract the best expression for that Root from the e-graph and return it as a string.
    Cost Function (Phase - 4) is used to determine the best expression.
    The Rust-owned CString is freed immediately after copying into a Julia String.
"""
function egraph_extract(ptr::Ptr{Cvoid})::String
    raw    = ccall((:egraph_extract, LIBPATH), Ptr{UInt8}, (Ptr{Cvoid},), ptr)
    result = unsafe_string(raw)
    ccall((:egraph_free_string, LIBPATH), Cvoid, (Ptr{UInt8},), raw)
    return result
end

"""
    egraph_pretty_extract(ptr::Ptr{Cvoid}; width::Integer=80) -> String

    Same as egraph_extract but returns a pretty-printed s-expression
    with indentation when lines exceed width characters.
    Useful for debugging complex extracted expressions.
"""
function egraph_pretty_extract(ptr::Ptr{Cvoid}; width::Integer=80)::String
    raw    = ccall((:egraph_pretty_extract, LIBPATH), Ptr{UInt8}, (Ptr{Cvoid}, UInt32), ptr, width)
    result = unsafe_string(raw)
    ccall((:egraph_free_string, LIBPATH), Cvoid, (Ptr{UInt8},), raw)
    return result
end

"""
    egraph_destroy(ptr::Ptr{Cvoid})

    Free the EGraphWithRoot struct on the Rust heap.
    Call exactly once when done with ptr do not use ptr after this.
"""
function egraph_destroy(ptr::Ptr{Cvoid})
    ccall((:egraph_destroy, LIBPATH), Cvoid, (Ptr{Cvoid},), ptr)
end

"""
    optimize_expr(expr, vars::Dict{String, Num}; warn=true) -> Num

    Full pipeline: Symbolics expr to s-expression to egraph to saturate to extract to Symbolics.Num.
    Cost function (Phase 4) determines the best extracted expression.
    Warns if saturation did not complete cleanly (NodeLimit, TimeLimit, etc).
"""
function optimize_expr(expr, vars::Dict{String, Num}; warn::Bool=true)::Num
    s   = to_sexpr(expr)
    ptr = egraph_create(s)
    egraph_saturate!(ptr)
    reason = egraph_stop_reason(ptr)
    if warn && reason !== :Saturated
        @warn "egraph did not fully saturate" stop_reason=reason expr=expr
    end
    res = egraph_extract(ptr)
    egraph_destroy(ptr)
    return from_sexpr(res, vars)
end

"""
    optimize_expr(expr; warn=true) -> Num

    Same as optimize_expr(expr, vars) but automatically builds the variable
    dictionary from expr via Symbolics.get_variables no manual Dict needed.
"""
function optimize_expr(expr; warn::Bool=true)::Num
    vars = Dict{String, Num}(string(v) => Num(v) for v in Symbolics.get_variables(expr))
    return optimize_expr(expr, vars; warn)
end

# ==================== UTILITY FUNCTIONS ====================
# e-graph introspection from herbie/egg-herbie/src/lib.rs

"""
    egraph_size(ptr::Ptr{Cvoid}) -> UInt32

    Total number of e-classes in the e-graph.
"""
function egraph_size(ptr::Ptr{Cvoid})::UInt32
    ccall((:egraph_size, LIBPATH), UInt32, (Ptr{Cvoid},), ptr)
end

"""
    egraph_eclass_size(ptr::Ptr{Cvoid}, id::Integer) -> UInt32

    Number of equivalent e-nodes in the e-class with the given id.
"""
function egraph_eclass_size(ptr::Ptr{Cvoid}, id::Integer)::UInt32
    ccall((:egraph_eclass_size, LIBPATH), UInt32, (Ptr{Cvoid}, UInt32), ptr, id)
end

"""
    egraph_find(ptr::Ptr{Cvoid}, id::Integer) -> UInt32

    Canonical id for the given id (union-find lookup).
"""
function egraph_find(ptr::Ptr{Cvoid}, id::Integer)::UInt32
    ccall((:egraph_find, LIBPATH), UInt32, (Ptr{Cvoid}, UInt32), ptr, id)
end

"""
    egraph_root_id(ptr::Ptr{Cvoid}) -> UInt32

    Id of the root e-class.
"""
function egraph_root_id(ptr::Ptr{Cvoid})::UInt32
    ccall((:egraph_root_id, LIBPATH), UInt32, (Ptr{Cvoid},), ptr)
end

"""
    egraph_total_size(ptr::Ptr{Cvoid}) -> UInt32

    Total unique enodes across all eclasses (memo.len()).
    Distinct from egraph_size() which returns number of eclasses.
"""
function egraph_total_size(ptr::Ptr{Cvoid})::UInt32
    ccall((:egraph_total_size, LIBPATH), UInt32, (Ptr{Cvoid},), ptr)
end

"""
    egraph_contains(ptr::Ptr{Cvoid}, expr) -> Union{UInt32, Nothing}

    Check if a Symbolics expression is present in the egraph after saturation.
    Returns the canonical eclass id if found, nothing if not found.
"""
function egraph_contains(ptr::Ptr{Cvoid}, expr)::Union{UInt32, Nothing}
    s   = to_sexpr(expr)
    raw = ccall((:egraph_contains, LIBPATH), UInt32, (Ptr{Cvoid}, Cstring), ptr, s)
    raw == typemax(UInt32) ? nothing : raw
end

end
