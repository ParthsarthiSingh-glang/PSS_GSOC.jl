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
    if isempty(points)
        error("sample_context: found no valid points for $expr (all points invalid or out of domain)")
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

"""
    remove_unnecessary_preprocessing(expr, vars, context::SampleContext,
                                      held::Vector{Tuple{Symbol,Any}}) -> Vector{Tuple{Symbol,Any}}

Tries dropping each held identity one at a time; if accuracy doesn't get worse
(preprocessing_leq), drops it and RE-CHECKS THE SAME INDEX (the
next item has comes into this place and hasn't been tested yet ). 
Repeats full passes until nothing more drops.

"""
function remove_unnecessary_preprocessing(expr, vars, context::SampleContext,
                                           held::Vector{Tuple{Symbol,Any}})
    changed = true
    while changed
        changed = false
        i = 1
        while i <= length(held)
            candidate = deleteat!(copy(held), i)
            if preprocessing_leq(expr, vars, context, candidate, held)
                held = candidate
                changed = true
            else
                i += 1
            end
        end
    end
    return held
end

"""
    rival_sample(expr; n_train=256, n_test=8000) -> (train=(points,values), test=(points,values))

Single-variable only. Samples n_train+n_test points via rival3 
Train (256) -> main search loop.
Test (8000) -> final accuracy reporting only.
"""
function rival_sample(expr; n_train::Int=256, n_test::Int=8000)
    expr_str = to_sexpr(expr)
    n_total = n_train + n_test
    ptr = ccall((:rival_sample_points, LIBPATH), Ptr{UInt8}, (Cstring, Csize_t), expr_str, n_total)
    result = unsafe_string(ptr)
    ccall((:egraph_free_string, LIBPATH), Cvoid, (Ptr{UInt8},), ptr)

    startswith(result, "ERROR:") && error("rival_sample: $result")

    lines = filter(!isempty, split(result, '\n'))
    points = Vector{Float64}(undef, length(lines))
    values = Vector{Float64}(undef, length(lines))
    for (i, line) in enumerate(lines)
        p, v = split(line)
        points[i] = parse(Float64, p)
        values[i] = parse(Float64, v)
    end

    train = (points=points[1:n_train], values=values[1:n_train])
    test  = (points=points[n_train+1:end], values=values[n_train+1:end])
    return (train=train, test=test)
end
