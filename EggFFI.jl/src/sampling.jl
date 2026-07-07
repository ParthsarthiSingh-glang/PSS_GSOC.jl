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

"""
    fast_eval(expr, vars) -> Function

Compiles expr into Float64 function - Herbie's fast evaluator
but via build_function . nanmath defaults to true.
"""
function fast_eval(expr, vars)
    return Symbolics.build_function(expr, vars...; expression=Val{false})
end

"""
    flonums_between(a::Float64, b::Float64) -> Int

Counts representable Float64 values between a and b (ULP distance).

Built from https://discourse.julialang.org/t/calculating-ulp-distance-between-two-floating-point-numbers-quickly/61581/3
This implementation still need to be confirmed fully wrt Racket in Herbie.
"""
function flonums_between(a::Float64, b::Float64)
    a == b && return 0
    (isnan(a) || isnan(b) || isinf(a) || isinf(b)) && return typemax(Int64)

    a_int = reinterpret(Int64, a)
    b_int = reinterpret(Int64, b)
    a_int = a_int < 0 ? (typemin(Int64) - a_int) : a_int
    b_int = b_int < 0 ? (typemin(Int64) - b_int) : b_int

    return abs(b_int - a_int)
end

"""
    ulps_to_bits(x) -> Float64

Converts a ULP distance into bits of precision lost .
"""
ulps_to_bits(x) = log(2, x)

"""
    errors_score(e) -> Float64

Average of a list of per-point error values .
"""
errors_score(e) = sum(e) / length(e)

"""
    score_context(expr, vars, context::SampleContext; invalid_bits=64.0) -> Float64

Scores expr Float64 accuracy against context ground truth.
Invalid_bits defaults to 64.0 (Float64's width).

"""
function score_context(expr, vars, context::SampleContext; invalid_bits::Float64=64.0)
    f = fast_eval(expr, vars)
    bits = Float64[]
    for (point, exact_interval) in zip(context.points, context.original_values)
        pt_vals = [Float64(mid(point[v])) for v in vars]
        fast_val = f(pt_vals...)
        ground_truth = Float64(mid(exact_interval))
        err = flonums_between(fast_val, ground_truth)
        push!(bits, err == typemax(Int64) ? invalid_bits : ulps_to_bits(err))
    end
    return errors_score(bits)
end

"""
    preprocessing_leq(expr, vars, context::SampleContext,
                      held1::Vector{Tuple{Symbol,Any}}, held2::Vector{Tuple{Symbol,Any}}) -> Bool

Is held1's accuracy at least as good as held2's, on the same expression and sample points ?
"""
function preprocessing_leq(expr, vars, context::SampleContext,
                            held1::Vector{Tuple{Symbol,Any}}, held2::Vector{Tuple{Symbol,Any}})
    context1 = preprocess_pcontext(context, held1)
    context2 = preprocess_pcontext(context, held2)
    return score_context(expr, vars, context1) <= score_context(expr, vars, context2)
end
