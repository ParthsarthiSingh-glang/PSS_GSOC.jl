"""
    SampleContext

Holds sample points and the original expression's value at each point .
SampleContext can be used by future calls .
"""
struct SampleContext
    points::Vector{Float64}
    original_values::Vector{Float64}
end

"""
    sample_context(expr, vars; n=10) -> SampleContext

Single-variable only. Rival .
"""
function sample_context(expr, vars; n::Int=10)
    result = rival_sample(expr; n_train=n, n_test=0)
    return SampleContext(result.train.points, result.train.values)
end

"""
    preprocess_pcontext(context::SampleContext, held::Vector{Tuple{Symbol,Any}}) -> SampleContext

    Applies each held identity to the sample points :
        :abs    -> replace value with abs(value)
        :negabs -> copysign(1, v) == sign(v)

"""
function preprocess_pcontext(context::SampleContext, held::Vector{Tuple{Symbol,Any}})
    n = length(context.points)
    new_points = Vector{Float64}(undef, n)
    new_values = Vector{Float64}(undef, n)
    for i in 1:n
        new_point = context.points[i]
        new_value = context.original_values[i]
        for (label, v) in held
            original = new_point
            if label == :abs
                new_point = abs(original)
            elseif label == :negabs
                new_point = abs(original)
                new_value = sign(original) * new_value
            end
        end
        new_points[i] = new_point
        new_values[i] = new_value
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
    points_errors(expr, vars, context::SampleContext; invalid_bits=64.0) -> Vector{Float64}

Per-point bits-of-error for expr against context ground truth (the vector
score_context made into their mean). 
Invalid_bits defaults to 64.0 (Float64's width).
"""
function points_errors(expr, vars, context::SampleContext; invalid_bits::Float64=64.0)::Vector{Float64}
    f = fast_eval(expr, vars)
    bits = Float64[]
    for (point, ground_truth) in zip(context.points, context.original_values)
        fast_val = f(point)
        err = flonums_between(fast_val, ground_truth)
        # Herbie finite-ulps (syntax/float.rkt) is 1 + abs(flonums-between(x,y)),
        # never the raw distance directly -- fixes the ans to 0.0 case .
        push!(bits, err == typemax(Int64) ? invalid_bits : ulps_to_bits(1 + err))
    end
    return bits
end

"""
    score_context(expr, vars, context::SampleContext; invalid_bits=64.0) -> Float64

Scores expr Float64 accuracy against context ground truth.
Invalid_bits defaults to 64.0 (Float64's width).

"""
function score_context(expr, vars, context::SampleContext; invalid_bits::Float64=64.0)
    return errors_score(points_errors(expr, vars, context; invalid_bits=invalid_bits))
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
