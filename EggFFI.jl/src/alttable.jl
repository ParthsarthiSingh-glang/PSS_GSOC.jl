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

"""
    atab_add_altn!(table::AltTable, expr::Num, errs::Vector{Float64}, cost::Float64) -> AltTable

Merges new candidate into every point's curve. 
"""
function atab_add_altn!(table::AltTable, expr::Num, errs::Vector{Float64}, cost::Float64)::AltTable
    key = to_sexpr(expr)
    haskey(table.alt_to_point_idxs, key) && return table

    max_valid_bits = 64.0  # binary64
    for (i, pcurve) in enumerate(table.point_idx_to_alts)
        err = errs[i]
        if err <= max_valid_bits
            new_point = ParetoPoint(cost, err, [key])
            table.point_idx_to_alts[i] = pareto_union([new_point], pcurve; combine = vcat)
        end
    end

    table.alt_to_point_idxs[key] = Int[]  
    table.alt_to_done[key] = false
    table.alt_to_cost[key] = cost
    table.expr_of[key] = expr
    return table
end

"""
    invert_index(point_idx_to_alts::Vector{Vector{ParetoPoint{String}}}) -> Dict{String, Vector{Int}}

Rebuilds the alt .
"""
function invert_index(point_idx_to_alts::Vector{Vector{ParetoPoint{String}}})::Dict{String, Vector{Int}}
    alt_to_points = Dict{String, Vector{Int}}()
    for (idx, pcurve) in enumerate(point_idx_to_alts)
        for ppt in pcurve
            for alt in ppt.data
                push!(get!(alt_to_points, alt, Int[]), idx)
            end
        end
    end
    return alt_to_points
end

const CoverageGroup = Vector{Union{Nothing, String}}

"""
    SetCover

State for atab_prune greedy set-cover pass.
    
"""
mutable struct SetCover
    removable::Set{String}
    coverage::Vector{Union{Nothing, CoverageGroup}}
end

"""
    atab_set_cover(table::AltTable) -> SetCover

Builds the initial SetCover.
"""
function atab_set_cover(table::AltTable)::SetCover
    removable = Set{String}(keys(table.alt_to_point_idxs))
    coverage = Union{Nothing, CoverageGroup}[]
    for pcurve in table.point_idx_to_alts
        for ppt in pcurve
            if isempty(ppt.data)
                error("This point has no alts which are best at it! $ppt")
            elseif length(ppt.data) == 1
                delete!(removable, ppt.data[1])
            else
                push!(coverage, CoverageGroup(ppt.data))
            end
        end
    end
    return SetCover(removable, coverage)
end

"""
    set_cover_remove!(sc::SetCover, altn::String)

Removes altn from consideration.
"""
function set_cover_remove!(sc::SetCover, altn::String)
    delete!(sc.removable, altn)
    for (j, group) in enumerate(sc.coverage)
        group === nothing && continue
        count = 0
        last = nothing
        for (i, a) in enumerate(group)
            a === nothing && continue
            if a == altn
                group[i] = nothing
            else
                count += 1
                last = a
            end
        end
        if count == 1
            sc.coverage[j] = nothing
            delete!(sc.removable, last)
        end
    end
end

"""
    removability_lt(table::AltTable, alt1::String, alt2::String) -> Bool

"""
function removability_lt(table::AltTable, alt1::String, alt2::String)::Bool
    alt1_done = table.alt_to_done[alt1]
    alt2_done = table.alt_to_done[alt2]
    if !alt1_done && alt2_done
        return true
    elseif alt1_done && !alt2_done
        return false
    end

    alt1_num = length(table.alt_to_point_idxs[alt1])
    alt2_num = length(table.alt_to_point_idxs[alt2])
    if alt1_num < alt2_num
        return true
    elseif alt1_num > alt2_num
        return false
    end

    alt1_cost = table.alt_to_cost[alt1]
    alt2_cost = table.alt_to_cost[alt2]
    if alt1_cost < alt2_cost
        return false
    elseif alt2_cost < alt1_cost
        return true
    else
        return alt1 < alt2
    end
end

"""
    atab_remove!(table::AltTable, altns::Vector{String}) -> AltTable

"""
function atab_remove!(table::AltTable, altns::Vector{String})::AltTable
    isempty(altns) && return table
    removeset = Set(altns)
    for pcurve in table.point_idx_to_alts
        for ppt in pcurve
            filter!(a -> !(a in removeset), ppt.data)
        end
    end
    for k in altns
        delete!(table.alt_to_point_idxs, k)
        delete!(table.alt_to_done, k)
        delete!(table.alt_to_cost, k)
        delete!(table.expr_of, k)
    end
    return table
end

"""
    atab_prune!(table::AltTable) -> AltTable

"""
function atab_prune!(table::AltTable)::AltTable
    sc = atab_set_cover(table)
    removability = sort(collect(sc.removable); lt = (a, b) -> removability_lt(table, a, b))

    removed = String[]
    for worst_alt in removability
        if worst_alt in sc.removable
            set_cover_remove!(sc, worst_alt)
            push!(removed, worst_alt)
        end
    end
    atab_remove!(table, removed)
    return table
end

"""
    atab_add_altns!(table::AltTable, candidates::Vector{Num}, errss::Vector{Vector{Float64}}, costs::Vector{Float64}) -> AltTable

"""
function atab_add_altns!(table::AltTable, candidates::Vector{Num},
                          errss::Vector{Vector{Float64}}, costs::Vector{Float64})::AltTable
    original_all = copy(table.all)

    for (candidate, errs, cost) in zip(candidates, errss, costs)
        atab_add_altn!(table, candidate, errs, cost)
    end

    table.alt_to_point_idxs = invert_index(table.point_idx_to_alts)
    atab_prune!(table)
    table.alt_to_point_idxs = invert_index(table.point_idx_to_alts)
    table.all = collect(union(Set(original_all), Set(keys(table.alt_to_point_idxs))))

    return table
end

"""
    atab_min_errors(table::AltTable) -> Vector{Float64}

"""
function atab_min_errors(table::AltTable)::Vector{Float64}
    return [first(curve).error for curve in table.point_idx_to_alts]
end
