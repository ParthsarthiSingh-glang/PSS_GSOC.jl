# core/alt-table.rkt.

"""
    ast_size_cost(tree) -> Int

Node-count cost of a parse_sexpr(...) tree .
"""
function ast_size_cost(tree)::Int
    tree isa AbstractString && return 1
    op, args = tree
    return 1 + sum(ast_size_cost(a) for a in args; init = 0)
end

"""
    ast_size_cost(expr::Num) -> Int

    
costs of a  Num expression 
"""
ast_size_cost(expr::Num) = ast_size_cost(parse_sexpr(to_sexpr(expr)))

"""
    AltTable

Julia version of Herbie's alt-table struct .

- point_idx_to_alts : one Pareto curve per sample point 
- alt_to_point_idxs : alt key -> which points it wins at
- alt_to_done       : alt key -> generate-candidates already run on these
- alt_to_cost       : alt key -> cost
- pcontext          : ground-truth sample context
- all               : every alt key ever inserted
- expr_of           : alt key -> the actual Num expression
"""
mutable struct AltTable
    point_idx_to_alts::Vector{Vector{ParetoPoint{String}}}
    alt_to_point_idxs::Dict{String, Vector{Int}}
    alt_to_done::Dict{String, Bool}
    alt_to_cost::Dict{String, Float64}
    pcontext::SampleContext
    all::Vector{String}
    expr_of::Dict{String, Num}
end

"""
    make_alt_table(pcontext, initial_expr::Num, vars) -> AltTable

"""
function make_alt_table(pcontext::SampleContext, initial_expr::Num, vars)::AltTable
    key = to_sexpr(initial_expr)
    cost = Float64(ast_size_cost(initial_expr))
    errs = points_errors(initial_expr, vars, pcontext)
    n = length(pcontext.points)

    point_idx_to_alts = [[ParetoPoint(cost, errs[i], [key])] for i in 1:n]
    alt_to_point_idxs = Dict(key => collect(1:n))
    alt_to_done = Dict(key => false)
    alt_to_cost = Dict(key => cost)
    all_keys = [key]
    expr_of = Dict(key => initial_expr)

    return AltTable(point_idx_to_alts, alt_to_point_idxs, alt_to_done, alt_to_cost,
        pcontext, all_keys, expr_of)
end

"""
    make_alt_table(pcontext, initial_expr::Num) -> AltTable

"""
function make_alt_table(pcontext::SampleContext, initial_expr::Num)::AltTable
    return make_alt_table(pcontext, initial_expr, Symbolics.get_variables(initial_expr))
end

"""
    order_altns(keys) -> Vector{String}

"""
order_altns(ks) = sort(collect(ks))

"""
    atab_active_alts(table::AltTable) -> Vector{String}

Alt keys currently present in >=1 curve .
"""
atab_active_alts(table::AltTable) = order_altns(keys(table.alt_to_point_idxs))

"""
    atab_all_alts(table::AltTable) -> Vector{String}

Every alt key ever inserted.
"""
atab_all_alts(table::AltTable) = order_altns(table.all)

"""
    atab_not_done_alts(table::AltTable) -> Vector{String}

Active alts not yet marked done .
"""
function atab_not_done_alts(table::AltTable)::Vector{String}
    active = keys(table.alt_to_point_idxs)
    pending = Iterators.filter(k -> !table.alt_to_done[k], active)
    return order_altns(pending)
end

"""
    atab_completed(table::AltTable) -> Bool

True when every active alt is done.
"""
function atab_completed(table::AltTable)::Bool
    return all(table.alt_to_done[k] for k in keys(table.alt_to_point_idxs))
end

"""
    atab_set_picked!(table::AltTable, ks) -> AltTable

Marks the given alt keys done=true. Mutates and returns `table`.

"""
function atab_set_picked!(table::AltTable, ks)::AltTable
    for k in ks
        table.alt_to_done[k] = true
    end
    return table
end

"""
    atab_eval_altns(table::AltTable, candidates::Vector{Num}, vars) -> (errss, costs)

Scores a batch of NEW candidate expressions not yet in the table .
"""
function atab_eval_altns(table::AltTable, candidates::Vector{Num}, vars)
    errss = [points_errors(c, vars, table.pcontext) for c in candidates]
    costs = [Float64(ast_size_cost(c)) for c in candidates]
    return errss, costs
end
