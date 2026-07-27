#utils/pareto.rkt 

"""
    ParetoPoint{T}

Pareto curve: (cost, error) + data naming for the alts-candidates
"""
struct ParetoPoint{T}
    cost::Float64
    error::Float64
    data::Vector{T}
end


function Base.:(==)(p1::ParetoPoint, p2::ParetoPoint)
    return p1.cost == p2.cost && p1.error == p2.error && p1.data == p2.data
end

function Base.hash(p::ParetoPoint, h::UInt)
    h = hash(p.cost, h)
    h = hash(p.error, h)
    h = hash(p.data, h)
    return h
end

"""
    pareto_compare(p1::ParetoPoint, p2::ParetoPoint) -> Symbol

Compares two points on cost and error (lower is better for both).
"""
function pareto_compare(p1::ParetoPoint, p2::ParetoPoint)::Symbol
    if p1.cost == p2.cost && p1.error == p2.error
        return :eq
    elseif p1.cost <= p2.cost && p1.error <= p2.error
        return :lt
    elseif p1.cost >= p2.cost && p1.error >= p2.error
        return :gt
    else
        return :incomparable
    end
end

"""
    pareto_union(curve1, curve2; combine=vcat) -> Vector{ParetoPoint{T}}

Merges two Pareto-optimal curves into the
Pareto-optimal union .

Both input curves must already be sorted by increasing error .

Both curves must share the same concrete data type `T` .
"""
function pareto_union(curve1::Vector{ParetoPoint{T}}, curve2::Vector{ParetoPoint{T}};
                       combine = vcat) where T
    i, j = 1, 1
    result = ParetoPoint{T}[]
    while i <= length(curve1) && j <= length(curve2)
        p1, p2 = curve1[i], curve2[j]
        cmp = pareto_compare(p1, p2)
        if cmp == :lt
            # drop p2, keep comparing p1 against the rest of curve2
            j += 1
        elseif cmp == :gt
            # drop p1, keep comparing p2 against the rest of curve1
            i += 1
        elseif cmp == :eq
            push!(result, ParetoPoint(p1.cost, p1.error, combine(p1.data, p2.data)))
            i += 1
            j += 1
        else # :incomparable - both belong on the frontier; push the lower-error one first
            if p1.error < p2.error
                push!(result, p1)
                i += 1
            else
                push!(result, p2)
                j += 1
            end
        end
    end
    append!(result, curve1[i:end])
    append!(result, curve2[j:end])
    return result
end
