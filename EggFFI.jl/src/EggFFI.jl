module EggFFI

using TermInterface
using Symbolics
using SymbolicUtils

# compile-preprocessing - fabs/copysign must be registered as a symbolic function so 
# to_sexpr's nameof(operation(expr)) produces "fabs"/"copysign" matching
# MathLang node names.
@register_symbolic fabs(x::Real)
@register_symbolic copysign(x::Real, y::Real)

# compile lib.rs and DIR where (.dll on Windows, .so on Linux, .dylib on Mac) lives
const LIBPATH = joinpath(
    @__DIR__, "..", "..", "egg-julia-ffi", "target", "release", "egg_julia_ffi")

include("converter.jl")
include("sampling.jl")
include("pareto.jl")
include("alttable.jl")
include("mainloop.jl")

export egraph_create, egraph_saturate!, egraph_stop_reason,
       egraph_extract, egraph_pretty_extract, egraph_destroy,
       optimize_expr, from_sexpr, to_sexpr, parse_sexpr,
       egraph_size, egraph_total_size, egraph_contains,
       egraph_eclass_size, egraph_find, egraph_root_id, egraph_id_to_expr,
       egraph_eclass_enodes, egraph_dump_dot, egraph_unsound,
       egraph_num_classes, egraph_get_eclasses, egraph_get_proof, egraph_rule_stats,
       generate_candidates, find_preprocessing, compile_preprocessing, apply_preprocessing,
       preprocess_expr,
       egraph_add_node, egraph_add_root, insert_nodewise!,
       SampleContext, sample_context, preprocess_pcontext, fast_eval,
       flonums_between, ulps_to_bits, errors_score, points_errors, score_context, preprocessing_leq,
       remove_unnecessary_preprocessing, rival_sample,
       ParetoPoint, pareto_compare, pareto_union,
       ast_size_cost, AltTable, make_alt_table, order_altns,
       atab_active_alts, atab_all_alts, atab_not_done_alts, atab_completed,
       atab_set_picked!, atab_eval_altns,
       atab_add_altn!, invert_index, CoverageGroup, SetCover, atab_set_cover,
       set_cover_remove!, removability_lt, atab_remove!, atab_prune!,
       atab_add_altns!, atab_min_errors,
       NUM_ITERATIONS, rewrite_variations, rewrite_variations_batch, run_iteration!, run_improve!, extract!,
       ImprovementReport, start_score, end_score, run_improve_with_report,
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

"""
    egraph_add_node(ptr, op::String, ids::Vector{UInt32}) -> UInt32

    Inserts a single enode into an EXISTING egraph from an operator name and
    already-resolved child ids. Children must be inserted first (bottom-up).
"""
function egraph_add_node(ptr::Ptr{Cvoid}, op::String, ids::Vector{UInt32})::UInt32
    ccall((:egraph_add_node, LIBPATH), UInt32,
        (Ptr{Cvoid}, Cstring, Ptr{UInt32}, UInt32), ptr, op, ids, length(ids))
end

"""
    egraph_add_root(ptr, id::Integer)

    Registers an already-existing id (from egraph_add_node) as a tracked root.
"""
function egraph_add_root(ptr::Ptr{Cvoid}, id::Integer)
    ccall((:egraph_add_root, LIBPATH), Cvoid, (Ptr{Cvoid}, UInt32), ptr, id)
end

"""
    insert_nodewise!(ptr, tree) -> UInt32

    Walks a parse_sexpr(...) tree bottom-up
"""
function insert_nodewise!(ptr::Ptr{Cvoid}, tree)::UInt32
    if tree isa AbstractString
        return egraph_add_node(ptr, String(tree), UInt32[])
    else
        op, args = tree
        ids = UInt32[insert_nodewise!(ptr, a) for a in args]
        return egraph_add_node(ptr, String(op), ids)
    end
end

"""
    egraph_unsound(ptr::Ptr{Cvoid}) -> Bool

True if ConstantFold::merge sees two unequal constant values for
the same eclass during the last egraph_saturate! .
"""
function egraph_unsound(ptr::Ptr{Cvoid})::Bool
    ccall((:egraph_unsound, LIBPATH), Bool, (Ptr{Cvoid},), ptr)
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

"""
    optimize_expr(expr, vars::Dict{String,Num}; warn=true, loop=false, n=256) -> Num

"""
function optimize_expr(expr, vars::Dict{String, Num}; warn::Bool = true, loop::Bool = false, n::Int = 256)::Num
    if loop
        return run_improve!(expr, collect(values(vars)); n = n)
    end
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

function optimize_expr(expr; warn::Bool = true, loop::Bool = false, n::Int = 256)::Num
    vars = Dict{String, Num}(string(v) => Num(v) for v in Symbolics.get_variables(expr))
    return optimize_expr(expr, vars; warn, loop, n)
end

"""
    generate_candidates(expr) -> Vector{Tuple{Symbol, Any, Any}}

    attached rather than just the candidate expression:
      (:abs, v, cand)    = expr with v => -v substituted
      (:negabs, v, cand) = -expr with v => -v substituted
"""
function generate_candidates(expr)
    vars = Symbolics.get_variables(expr)
    candidates = Tuple{Symbol, Any, Any}[]
    for v in vars
        push!(candidates, (:abs, v, substitute(expr, Dict(v => -v))))
        push!(candidates, (:negabs, v, substitute(-expr, Dict(v => -v))))
    end
    return candidates
end

"""
    find_preprocessing(expr) -> Vector{Tuple{Symbol, Any}}

    generates even/odd candidates, inserts the original + every candidate into ONE
    shared egraph as separate roots, saturates once .
"""
function find_preprocessing(expr)
    candidates = generate_candidates(expr)

    ptr = egraph_create(to_sexpr(expr))
    root0 = egraph_root_id(ptr)

    tagged_ids = Tuple{Symbol, Any, UInt32}[]
    for (label, v, cand_expr) in candidates
        tree = parse_sexpr(to_sexpr(cand_expr))
        id = insert_nodewise!(ptr, tree)
        egraph_add_root(ptr, id)
        push!(tagged_ids, (label, v, id))
    end

    egraph_saturate!(ptr)

    canon0 = egraph_find(ptr, root0)
    held = Tuple{Symbol, Any}[]
    for (label, v, id) in tagged_ids
        egraph_find(ptr, id) == canon0 && push!(held, (label, v))
    end

    egraph_destroy(ptr)
    return held
end

"""
    compile_preprocessing(expr, label::Symbol, v) -> new_expr

"""
function compile_preprocessing(expr, label::Symbol, v)
    if label == :abs
        return substitute(expr, Dict(v => fabs(v)))
    elseif label == :negabs
        substituted = substitute(expr, Dict(v => fabs(v)))
        return copysign(1.0, v) * substituted
    else
        error("compile_preprocessing: unknown label $label")
    end
end

"""
    apply_preprocessing(expr, held::Vector{Tuple{Symbol,Any}}) -> new_expr
    
"""
function apply_preprocessing(expr, held::Vector{Tuple{Symbol,Any}})
    for (label, v) in reverse(held)
        expr = compile_preprocessing(expr, label, v)
    end
    return expr
end

"""
    preprocess_expr(expr, vars=Symbolics.get_variables(expr); n=256) -> new_expr

Runs the full preprocessing: n defaults to 256 , (config.rkt *num-points*)

"""
function preprocess_expr(expr, vars=Symbolics.get_variables(expr); n::Int=256)
    held = find_preprocessing(expr)
    isempty(held) && return expr
    ctx = sample_context(expr, vars; n=n)
    filtered = remove_unnecessary_preprocessing(expr, vars, ctx, held)
    return apply_preprocessing(expr, filtered)
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

function egraph_num_classes(ptr::Ptr{Cvoid})::UInt32
    ccall((:egraph_num_classes, LIBPATH), UInt32, (Ptr{Cvoid},), ptr)
end

function egraph_get_eclasses(ptr::Ptr{Cvoid})::Vector{UInt32}
    n = egraph_num_classes(ptr)
    buf = Vector{UInt32}(undef, n)
    ccall((:egraph_get_eclasses, LIBPATH), Cvoid, (Ptr{Cvoid}, Ptr{UInt32}), ptr, buf)
    return buf
end

"""
    egraph_get_proof(ptr::Ptr{Cvoid}, expr::String, goal::String) -> String

    Returns the step-by-step rewrite proof (as a string) explaining why
    `expr` and `goal` (both s-expression strings) are equivalent in the egraph.
    Requires explanations to be enabled (see egraph_create).
"""
function egraph_get_proof(ptr::Ptr{Cvoid}, expr::String, goal::String)::String
    raw = ccall((:egraph_get_proof, LIBPATH), Ptr{UInt8},
        (Ptr{Cvoid}, Cstring, Cstring), ptr, expr, goal)
    result = unsafe_string(raw)
    ccall((:egraph_free_string, LIBPATH), Cvoid, (Ptr{UInt8},), raw)
    return result
end

"""
    egraph_rule_stats(ptr::Ptr{Cvoid}) -> Dict{String, Int}

    Returns a map from rule name to the total number of times that rule
    was applied across all iterations of the last egraph_saturate! call
    (see egg::Iteration.applied in egg/src/run.rs).
"""
function egraph_rule_stats(ptr::Ptr{Cvoid})::Dict{String, Int}
    raw = ccall((:egraph_rule_stats, LIBPATH), Ptr{UInt8}, (Ptr{Cvoid},), ptr)
    result = unsafe_string(raw)
    ccall((:egraph_free_string, LIBPATH), Cvoid, (Ptr{UInt8},), raw)
    stats = Dict{String, Int}()
    for line in filter(!isempty, split(result, "\n"))
        name, count = split(line, ": ")
        stats[name] = parse(Int, count)
    end
    return stats
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
