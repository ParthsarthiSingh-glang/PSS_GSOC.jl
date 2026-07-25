# core/mainloop.rkt.

const NUM_ITERATIONS = 4  # config.rkt *num-iterations*

"""
    rewrite_variations(expr::Num, vars::Dict{String,Num}; warn::Bool=true) -> Vector{Num}

run-rr of generate-candidates (patch.rkt) .

"""
function rewrite_variations(expr::Num, vars::Dict{String, Num}; warn::Bool = true)::Vector{Num}
    local sexpr_str
    try
        sexpr_str = to_sexpr(expr)
    catch e
        warn && @warn "to_sexpr failed on input expr, skipping" expr=expr exception=e
        return Num[]
    end

    ptr = egraph_create(sexpr_str)
    egraph_saturate!(ptr)
    if warn && egraph_unsound(ptr)
        @warn "unsoundness detected in the egraph" expr=expr
    end
    canonical_root = egraph_find(ptr, egraph_root_id(ptr))
    enode_strs = egraph_eclass_enodes(ptr, canonical_root)
    egraph_destroy(ptr)

    variations = Num[]
    for s in enode_strs
        try
            push!(variations, from_sexpr(s, vars))
        catch e
            e isa KeyError || @warn "rewrite_variations: unexpected conversion failure" enode=s exception=e
        end
    end
    return variations
end

"""
    rewrite_variations(expr::Num; warn::Bool=true) -> Vector{Num}

"""
function rewrite_variations(expr::Num; warn::Bool = true)::Vector{Num}
    vars = Dict{String, Num}(string(v) => Num(v) for v in Symbolics.get_variables(expr))
    return rewrite_variations(expr, vars; warn)
end

"""
    rewrite_variations_batch(exprs::Vector{Num}, vars::Dict{String,Num}; warn::Bool=true) -> Vector{Vector{Num}}

Inserts EVERY given expr as a separate root into ONE SHARED egraph
saturates ONCE, then extracts variations per-root afterward.

"""
function rewrite_variations_batch(exprs::Vector{Num}, vars::Dict{String, Num}; warn::Bool = true,
                                   keep_alive::Bool = false)
    isempty(exprs) && return keep_alive ? (Vector{Num}[], nothing) : Vector{Num}[]

    seed_idx = findfirst(exprs) do e
        try
            to_sexpr(e)
            true
        catch
            false
        end
    end
    if seed_idx === nothing
        warn && @warn "no expr could be converted via to_sexpr, skipping whole batch" exprs=exprs
        empty_result = [Num[] for _ in exprs]
        return keep_alive ? (empty_result, nothing) : empty_result
    end

    ptr = egraph_create(to_sexpr(exprs[seed_idx]))
    root_ids_by_idx = Dict{Int, UInt32}(seed_idx => egraph_root_id(ptr))
    for (i, expr) in enumerate(exprs)
        i == seed_idx && continue
        try
            s = to_sexpr(expr)
            id = insert_nodewise!(ptr, parse_sexpr(s))
            egraph_add_root(ptr, id)
            root_ids_by_idx[i] = id
        catch e
            warn && @warn "skipping expr, to_sexpr/insert failed" expr=expr exception=e
        end
    end

    egraph_saturate!(ptr)
    if warn && egraph_unsound(ptr)
        @warn "unsoundness detected in the egraph" exprs=exprs
    end

    results = Vector{Num}[]
    for i in 1:length(exprs)
        if !haskey(root_ids_by_idx, i)
            push!(results, Num[])
            continue
        end
        id = root_ids_by_idx[i]
        canonical = egraph_find(ptr, id)
        variations = Num[]
        for s in egraph_eclass_enodes(ptr, canonical)
            try
                push!(variations, from_sexpr(s, vars))
            # please look in this , this is temp ig , due to Rival ops and our ops diff 
            catch e
                e isa KeyError || @warn "unexpected conversion failure" enode=s exception=e
            end
        end
        push!(results, variations)
    end

    if keep_alive
        return results, ptr
    end
    egraph_destroy(ptr)
    return results
end

"""
    DerivationLog

"""
mutable struct DerivationLog
    parent::Dict{String, String}
    kind::Dict{String, Symbol}          # :rewrite or :taylor
    egraph_of::Dict{String, Ptr{Cvoid}} # only set for :rewrite
    live_egraphs::Vector{Ptr{Cvoid}}
    root::String  
end
DerivationLog(root::String) = DerivationLog(Dict{String, String}(), Dict{String, Symbol}(),
    Dict{String, Ptr{Cvoid}}(), Ptr{Cvoid}[], root)

"""
    run_iteration!(table::AltTable, vars; dlog=nothing) -> AltTable

"""
function run_iteration!(table::AltTable, vars; dlog::Union{Nothing, DerivationLog} = nothing)::AltTable
    pending_keys = atab_not_done_alts(table)
    @info "run_iteration!" n_pending=length(pending_keys)
    atab_set_picked!(table, pending_keys)
    pending_exprs = [table.expr_of[k] for k in pending_keys]

    var_dict = Dict{String, Num}(string(v) => Num(v) for v in vars)
    candidates = Num[]

    if dlog === nothing
        variations_per_alt = rewrite_variations_batch(pending_exprs, var_dict)
        for vs in variations_per_alt
            append!(candidates, vs)
        end
    else
        variations_per_alt, ptr = rewrite_variations_batch(pending_exprs, var_dict; keep_alive = true)
        ptr !== nothing && push!(dlog.live_egraphs, ptr)
        for (parent_expr, vs) in zip(pending_exprs, variations_per_alt)
            parent_key = to_sexpr(parent_expr)
            for v in vs
                child_key = to_sexpr(v)
                if child_key != dlog.root && !haskey(dlog.parent, child_key)
                    dlog.parent[child_key] = parent_key
                    dlog.kind[child_key] = :rewrite
                    dlog.egraph_of[child_key] = ptr
                end
            end
            append!(candidates, vs)
        end
    end

    for expr in pending_exprs
        try
            taylor_candidates_expr = taylor_variations(expr, Num[Num(v) for v in vars])
            if dlog !== nothing
                parent_key = to_sexpr(expr)
                for c in taylor_candidates_expr
                    child_key = to_sexpr(c)
                    if child_key != dlog.root && !haskey(dlog.parent, child_key)
                        dlog.parent[child_key] = parent_key
                        dlog.kind[child_key] = :taylor
                    end
                end
            end
            append!(candidates, taylor_candidates_expr)
        catch e
            @warn "taylor_variations failed" expr=expr exception=e
        end
    end

    errss, costs = atab_eval_altns(table, candidates, vars)
    atab_add_altns!(table, candidates, errss, costs)

    @info "run_iteration! done" n_candidates=length(candidates) n_active=length(atab_active_alts(table))
    return table
end

"""
    extract_sorted!(table::AltTable, vars) -> Vector{Num}

"""
function extract_sorted!(table::AltTable, vars)::Vector{Num}
    all_keys = atab_all_alts(table)
    exprs = [table.expr_of[k] for k in all_keys]
    scores = [score_context(e, vars, table.pcontext) for e in exprs]
    costs = [Float64(ast_size_cost(e)) for e in exprs]
    order = sortperm(collect(zip(scores, costs)))
    return exprs[order]
end

"""
    extract_top!(table::AltTable, vars; k::Int=3) -> Vector{Num}

First k of extract_sorted! 
"""
function extract_top!(table::AltTable, vars; k::Int = 3)::Vector{Num}
    sorted = extract_sorted!(table, vars)
    return sorted[1:min(k, length(sorted))]
end

"""
    extract!(table::AltTable, vars) -> Num

Single best expression
"""
function extract!(table::AltTable, vars)::Num
    return first(extract_sorted!(table, vars))
end

"""
    run_loop!(table::AltTable, vars; dlog=nothing) -> AltTable
"""
function run_loop!(table::AltTable, vars; dlog::Union{Nothing, DerivationLog} = nothing)::AltTable
    for i in 1:NUM_ITERATIONS
        if atab_completed(table)
            @info "run_improve!: converged" iteration=i
            break
        end
        run_iteration!(table, vars; dlog)
    end
    return table
end

"""
    run_improve!(expr::Num, vars=Symbolics.get_variables(expr); n::Int=256) -> Num

"""
function run_improve!(expr::Num, vars = Symbolics.get_variables(expr); n::Int = 256)::Num
    ctx = sample_context(expr, vars; n = n)
    table = make_alt_table(ctx, expr, vars)
    run_loop!(table, vars)
    return extract!(table, vars)
end

"""
    DerivationStep

"""
struct DerivationStep
    kind::Symbol   # :rewrite or :taylor
    from::Num
    to::Num
    proof::Union{Nothing, Vector{String}}
end

"""
    contains_raw(ptr, sexpr) -> Union{UInt32,Nothing}

Same ccall as egraph_contains
"""
function contains_raw(ptr::Ptr{Cvoid}, sexpr::String)::Union{UInt32, Nothing}
    raw = ccall((:egraph_contains, LIBPATH), UInt32, (Ptr{Cvoid}, Cstring), ptr, sexpr)
    raw == typemax(UInt32) ? nothing : raw
end

"""
    is_equivalent(ptr, from_key, to_key) -> Bool

"""
function is_equivalent(ptr::Ptr{Cvoid}, from_key::String, to_key::String)::Bool
    from_id = contains_raw(ptr, from_key)
    to_id = contains_raw(ptr, to_key)
    (from_id === nothing || to_id === nothing) && return false
    return egraph_find(ptr, from_id) == egraph_find(ptr, to_id)
end

"""
    build_derivation(dlog::DerivationLog, vars, key::String) -> Vector{DerivationStep}
.
"""
function build_derivation(dlog::DerivationLog, vars, key::String)::Vector{DerivationStep}
    chain_keys = String[key]
    seen = Set{String}((key,))
    k = key
    while haskey(dlog.parent, k)
        k = dlog.parent[k]
        k in seen && error("build_derivation: parent cycle detected at $k ")
        push!(seen, k)
        push!(chain_keys, k)
    end
    reverse!(chain_keys)

    steps = DerivationStep[]
    for i in 1:length(chain_keys) - 1
        from_key, to_key = chain_keys[i], chain_keys[i + 1]
        step_kind = dlog.kind[to_key]
        proof = if step_kind != :rewrite
            nothing
        else
            ptr = dlog.egraph_of[to_key]
            if is_equivalent(ptr, from_key, to_key)
                egraph_get_proof_flat(ptr, from_key, to_key)
            else
                ["parent/child were not found equivalent in the " ]
            end
        end
        push!(steps, DerivationStep(step_kind, from_sexpr(from_key, vars), from_sexpr(to_key, vars), proof))
    end
    return steps
end

const _RULE_TAG_RE = r"Rewrite(?:=>|<=)\s+(\S+)"

"""
    print_derivation(steps::Vector{DerivationStep})

"""
function print_derivation(steps::Vector{DerivationStep})
    for (i, s) in enumerate(steps)
        println("[$i] ", s.kind, ": ", s.from, "  =>  ", s.to)
        if s.proof !== nothing
            for (j, line) in enumerate(s.proof)
                rules = [m.captures[1] for m in eachmatch(_RULE_TAG_RE, line)]
                tag = isempty(rules) ? "" : "   [" * join(rules, ", ") * "]"
                println("    ", j, ": ", line, tag)
            end
        else
            println("    (taylor series expansion, no rule-level proof)")
        end
        println()
    end
end

"""
    ImprovementReport
.
"""
struct ImprovementReport
    winner::Num
    alternatives::Vector{Num}
    start_errors::Vector{Float64}
    end_errors::Vector{Float64}
    test_context::SampleContext
    derivations::Dict{String, Vector{DerivationStep}}
end

"""
    start_score(r::ImprovementReport) -> Float64
    end_score(r::ImprovementReport) -> Float64

Mean bits-of-error.
"""
start_score(r::ImprovementReport) = errors_score(r.start_errors)
end_score(r::ImprovementReport) = errors_score(r.end_errors)

"""
    run_improve_with_report(expr::Num, vars=Symbolics.get_variables(expr);
                             n_train::Int=256, n_test::Int=8000, n_alts::Int=3) -> ImprovementReport

"""
function run_improve_with_report(expr::Num, vars = Symbolics.get_variables(expr);
                                  n_train::Int = 256, n_test::Int = 8000, n_alts::Int = 3)::ImprovementReport
    sampled = rival_sample(expr; n_train, n_test)
    train_ctx = SampleContext(sampled.train.points, sampled.train.values)
    test_ctx = SampleContext(sampled.test.points, sampled.test.values)

    table = make_alt_table(train_ctx, expr, vars)
    dlog = DerivationLog(to_sexpr(expr))
    run_loop!(table, vars; dlog)
    alternatives = extract_top!(table, vars; k = n_alts)
    winner = first(alternatives)

    var_dict = Dict{String, Num}(string(v) => Num(v) for v in vars)
    derivations = Dict{String, Vector{DerivationStep}}(
        to_sexpr(a) => build_derivation(dlog, var_dict, to_sexpr(a)) for a in alternatives)
    egraph_destroy.(dlog.live_egraphs)

    return ImprovementReport(winner, alternatives,
        points_errors(expr, vars, test_ctx),
        points_errors(winner, vars, test_ctx),
        test_ctx, derivations)
end
