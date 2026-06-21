module EggFFI

using TermInterface
using Symbolics
using SymbolicUtils

# compile lib.rs and DIR where (.dll on Windows, .so on Linux, .dylib on Mac) lives
const LIBPATH = joinpath(
    @__DIR__, "..", "..", "egg-julia-ffi", "target", "release", "egg_julia_ffi")

include("converter.jl")

export egraph_create, egraph_saturate!, egraph_stop_reason,
       egraph_extract, egraph_pretty_extract, egraph_destroy,
       optimize_expr, from_sexpr, to_sexpr,
       egraph_size, egraph_total_size, egraph_contains,
       egraph_eclass_size, egraph_find, egraph_root_id, egraph_id_to_expr,
       egraph_eclass_enodes, egraph_dump_dot,
       ExactInfinityError

function egraph_id_to_expr(ptr::Ptr{Cvoid}, id::Integer)::String
    raw = ccall((:egraph_id_to_expr, LIBPATH), Ptr{UInt8}, (Ptr{Cvoid}, UInt32), ptr, id)
    result = unsafe_string(raw)
    ccall((:egraph_free_string, LIBPATH), Cvoid, (Ptr{UInt8},), raw)
    return result
end

function egraph_create(expr::String)::Ptr{Cvoid}
    ccall((:egraph_create, LIBPATH), Ptr{Cvoid}, (Cstring,), expr)
end

function egraph_saturate!(ptr::Ptr{Cvoid})
    ccall((:egraph_saturate, LIBPATH), Cvoid, (Ptr{Cvoid},), ptr)
end

function egraph_stop_reason(ptr::Ptr{Cvoid})::Symbol
    code = ccall((:egraph_stop_reason, LIBPATH), UInt8, (Ptr{Cvoid},), ptr)
    return [:Saturated, :IterationLimit, :NodeLimit, :TimeLimit, :Other][code + 1]
end

function egraph_extract(ptr::Ptr{Cvoid})::String
    raw = ccall((:egraph_extract, LIBPATH), Ptr{UInt8}, (Ptr{Cvoid},), ptr)
    result = unsafe_string(raw)
    ccall((:egraph_free_string, LIBPATH), Cvoid, (Ptr{UInt8},), raw)
    return result
end

function egraph_pretty_extract(ptr::Ptr{Cvoid}; width::Integer = 80)::String
    raw = ccall(
        (:egraph_pretty_extract, LIBPATH), Ptr{UInt8}, (Ptr{Cvoid}, UInt32), ptr, width)
    result = unsafe_string(raw)
    ccall((:egraph_free_string, LIBPATH), Cvoid, (Ptr{UInt8},), raw)
    return result
end

function egraph_destroy(ptr::Ptr{Cvoid})
    ccall((:egraph_destroy, LIBPATH), Cvoid, (Ptr{Cvoid},), ptr)
end

function optimize_expr(expr, vars::Dict{String, Num}; warn::Bool = true)::Num
    s = to_sexpr(expr)
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

function optimize_expr(expr; warn::Bool = true)::Num
    vars = Dict{String, Num}(string(v) => Num(v) for v in Symbolics.get_variables(expr))
    return optimize_expr(expr, vars; warn)
end

# ==================== UTILITY FUNCTIONS ====================

function egraph_size(ptr::Ptr{Cvoid})::UInt32
    ccall((:egraph_size, LIBPATH), UInt32, (Ptr{Cvoid},), ptr)
end

function egraph_eclass_size(ptr::Ptr{Cvoid}, id::Integer)::UInt32
    ccall((:egraph_eclass_size, LIBPATH), UInt32, (Ptr{Cvoid}, UInt32), ptr, id)
end

function egraph_find(ptr::Ptr{Cvoid}, id::Integer)::UInt32
    ccall((:egraph_find, LIBPATH), UInt32, (Ptr{Cvoid}, UInt32), ptr, id)
end

function egraph_root_id(ptr::Ptr{Cvoid})::UInt32
    ccall((:egraph_root_id, LIBPATH), UInt32, (Ptr{Cvoid},), ptr)
end

function egraph_total_size(ptr::Ptr{Cvoid})::UInt32
    ccall((:egraph_total_size, LIBPATH), UInt32, (Ptr{Cvoid},), ptr)
end

function egraph_contains(ptr::Ptr{Cvoid}, expr)::Union{UInt32, Nothing}
    s = to_sexpr(expr)
    raw = ccall((:egraph_contains, LIBPATH), UInt32, (Ptr{Cvoid}, Cstring), ptr, s)
    raw == typemax(UInt32) ? nothing : raw
end

"""
    egraph_eclass_enodes(ptr::Ptr{Cvoid}, id::Integer) -> Vector{String}

    Returns all enodes inside the eclass with the given id as a vector of s-expressions .
"""
function egraph_eclass_enodes(ptr::Ptr{Cvoid}, id::Integer)::Vector{String}
    raw = ccall((:egraph_eclass_enodes, LIBPATH), Ptr{UInt8}, (Ptr{Cvoid}, UInt32), ptr, id)
    result = unsafe_string(raw)
    ccall((:egraph_free_string, LIBPATH), Cvoid, (Ptr{UInt8},), raw)
    filter(!isempty, split(result, "\n"))
end

"""
    egraph_dump_dot(ptr::Ptr{Cvoid}, path::String)

    Dump the egraph to a .dot file for visualization.
    Open with GraphViz or paste into https://dreampuf.github.io/GraphvizOnline
"""
function egraph_dump_dot(ptr::Ptr{Cvoid}, path::String)
    ccall((:egraph_dump_dot, LIBPATH), Cvoid, (Ptr{Cvoid}, Cstring), ptr, path)
end

end
