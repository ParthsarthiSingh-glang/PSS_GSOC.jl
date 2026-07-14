# core/mainloop.rkt.

const NUM_ITERATIONS = 4  # config.rkt *num-iterations*

"""
    rewrite_variations(expr::Num, vars::Dict{String,Num}; warn::Bool=true) -> Vector{Num}

run-rr of generate-candidates (patch.rkt) .
"""
function rewrite_variations(expr::Num, vars::Dict{String, Num}; warn::Bool = true)::Vector{Num}
    ptr = egraph_create(to_sexpr(expr))
    egraph_saturate!(ptr)
    reason = egraph_stop_reason(ptr)
    if warn && reason !== :Saturated
        @warn "egraph did not fully saturate" stop_reason=reason expr=expr
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
    run_iteration!(table::AltTable, vars) -> AltTable

"""
function run_iteration!(table::AltTable, vars)::AltTable
    pending_keys = atab_not_done_alts(table)
    @info "run_iteration!" n_pending=length(pending_keys)
    atab_set_picked!(table, pending_keys)
    pending_exprs = [table.expr_of[k] for k in pending_keys]

    var_dict = Dict{String, Num}(string(v) => Num(v) for v in vars)
    candidates = Num[]
    for expr in pending_exprs
        append!(candidates, rewrite_variations(expr, var_dict))
    end

    errss, costs = atab_eval_altns(table, candidates, vars)
    atab_add_altns!(table, candidates, errss, costs)

    @info "run_iteration! done" n_candidates=length(candidates) n_active=length(atab_active_alts(table))
    return table
end

"""
    run_improve!(expr::Num, vars=Symbolics.get_variables(expr); n::Int=256) -> AltTable

# still to add things in here#
"""
function run_improve!(expr::Num, vars = Symbolics.get_variables(expr); n::Int = 256)::AltTable
    ctx = sample_context(expr, vars; n = n)
    table = make_alt_table(ctx, expr, vars)

    for i in 1:NUM_ITERATIONS
        if atab_completed(table)
            @info "run_improve!: converged" iteration=i
            break
        end
        run_iteration!(table, vars)
    end

    return table
end
