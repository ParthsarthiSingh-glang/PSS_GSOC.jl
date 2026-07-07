using IntervalArithmetic

"""
    SampleContext

Holds sample points and the original expression's value at each point .
SampleContext can be used by future calls .
"""
struct SampleContext
    points::Vector{Dict{Num, Interval{BigFloat}}}
    original_values::Vector{Interval{BigFloat}}
end

"""
    sample_context(expr, vars; range=..., n=10) -> SampleContext

"""
function sample_context(expr, vars;
                         range=interval(BigFloat(-10), BigFloat(10)),
                         n::Int=10)
    subintervals = mince(range, n)
    f = Symbolics.build_function(expr, vars...; expression=Val{false}, nanmath=false)
    points = Dict{Num, Interval{BigFloat}}[]
    values = Interval{BigFloat}[]
    for sub in subintervals
        m = mid(sub)
        pt_vals = [interval(BigFloat(m)) for _ in vars]
        val = f(pt_vals...)
        isempty_interval(val) && continue
        point = Dict(v => pt_vals[i] for (i, v) in enumerate(vars))
        push!(points, point)
        push!(values, val)
    end
    return SampleContext(points, values)
end

"""
    preprocess_pcontext(context::SampleContext, held::Vector{Tuple{Symbol,Any}}) -> SampleContext

    Applies each held identity to the sample points :
        :abs    -> replace value with abs(value)
        :negabs -> copysign(1, v) == sign(v)
"""
function preprocess_pcontext(context::SampleContext, held::Vector{Tuple{Symbol,Any}})
    new_points = Dict{Num, Interval{BigFloat}}[]
    new_values = Interval{BigFloat}[]

    for (point, exact_value) in zip(context.points, context.original_values)
        new_point = copy(point)
        new_value = exact_value
        for (label, v) in reverse(held)
            original = new_point[v]
            if label == :abs
                new_point[v] = abs(original)
            elseif label == :negabs
                new_point[v] = abs(original)
                new_value = sign(original) * new_value
            end
        end
        push!(new_points, new_point)
        push!(new_values, new_value)
    end

    return SampleContext(new_points, new_values)
end
