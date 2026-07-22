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
function rewrite_variations_batch(exprs::Vector{Num}, vars::Dict{String, Num}; warn::Bool = true)::Vector{Vector{Num}}
    isempty(exprs) && return Vector{Num}[]

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
        return [Num[] for _ in exprs]
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

    egraph_destroy(ptr)
    return results
end

"""
    run_iteration!(table::AltTable, vars) -> AltTable

"""
function run_iteration!(table::AltTable, vars)::AltTable
    pending_keys = atab_not_done_alts(table)
    @info "run_iteration!" n_pending=length(pending_keys)
    atab_set_picked!(table, pending_keys)
    pending_exprs = [table.expr_of[k] for k in pending_keys]

    var_dict = Dict{String, Num}(string(v) => Num(v) for v in vars)
    variations_per_alt = rewrite_variations_batch(pending_exprs, var_dict)
    candidates = Num[]
    for vs in variations_per_alt
        append!(candidates, vs)
    end

    for expr in pending_exprs
        try
            append!(candidates, taylor_variations(expr, Num[Num(v) for v in vars]))
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
    _run_loop!(table::AltTable, vars) -> AltTable
"""
function _run_loop!(table::AltTable, vars)::AltTable
    for i in 1:NUM_ITERATIONS
        if atab_completed(table)
            @info "run_improve!: converged" iteration=i
            break
        end
        run_iteration!(table, vars)
    end
    return table
end

"""
    run_improve!(expr::Num, vars=Symbolics.get_variables(expr); n::Int=256) -> Num

"""
function run_improve!(expr::Num, vars = Symbolics.get_variables(expr); n::Int = 256)::Num
    ctx = sample_context(expr, vars; n = n)
    table = make_alt_table(ctx, expr, vars)
    _run_loop!(table, vars)
    return extract!(table, vars)
end

"""
    ImprovementReport

alternatives is the top-k sorted candidate list 
"""
struct ImprovementReport
    winner::Num
    alternatives::Vector{Num}
    start_errors::Vector{Float64}
    end_errors::Vector{Float64}
    test_context::SampleContext
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
    _run_loop!(table, vars)
    alternatives = extract_top!(table, vars; k = n_alts)
    winner = first(alternatives)

    return ImprovementReport(winner, alternatives,
        points_errors(expr, vars, test_ctx),
        points_errors(winner, vars, test_ctx),
        test_ctx)
end
