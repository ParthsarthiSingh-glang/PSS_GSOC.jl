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
