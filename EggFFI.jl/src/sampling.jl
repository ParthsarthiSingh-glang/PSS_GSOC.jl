using IntervalArithmetic

"""
    SampleContext

Holds sample points and the original expression's value at each point .
SampleContext can be used by future calls .
"""
struct SampleContext
    points::Vector{Dict}
    original_values::Vector
end

"""
    sample_context(expr, vars; range=..., n=10) -> SampleContext

"""
function sample_context(expr, vars;
                         range=interval(BigFloat(-10), BigFloat(10)),
                         n::Int=10)
    subintervals = mince(range, n)
    points = Dict[]
    values = []
    for sub in subintervals
        m = mid(sub)
        point = Dict(v => interval(BigFloat(m)) for v in vars)
        val = substitute(expr, point)
        isempty_interval(val) && continue
        push!(points, point)
        push!(values, val)
    end
    return SampleContext(points, values)
end
