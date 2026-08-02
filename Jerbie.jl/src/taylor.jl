mutable struct TSeries
    offset::Int
    builder::Function  
    cache::Dict{Int,Num}
end

make_series(offset::Int, builder::Function) = TSeries(offset, builder, Dict{Int,Num}())

"""
    to_bigInt(u) -> Any
"""
function to_bigInt(u)
    if SymbolicUtils.isconst(u)
        v = SymbolicUtils.unwrap_const(u)
        (v isa Integer && !(v isa BigInt)) && return BigInt(v)
        (v isa Rational && !(v isa Rational{BigInt})) && return Rational{BigInt}(v)
        return u
    end
    if SymbolicUtils.iscall(u)
        op = SymbolicUtils.operation(u)
        args = SymbolicUtils.arguments(u)
        new_args = Any[to_bigInt(a) for a in args]
        return TermInterface.maketerm(typeof(u), op, new_args, nothing)
    end
    return u
end

"""
    iroot(x, n) -> Union{Integer,Nothing}

Exact integer n-th root 
"""
function iroot(x::Integer, n::Int)::Union{Integer,Nothing}
    x < 0 && return nothing
    x == 0 && return 0
    if n == 2
        r = isqrt(x)
        return r^2 == x ? r : nothing
    end
    lo, hi = big(0), big(x) + 1
    while lo < hi
        mid = (lo + hi + 1) ÷ 2
        mid^n <= x ? (lo = mid) : (hi = mid - 1)
    end
    return lo^n == x ? lo : nothing
end

"""
    exact_root(val, n) -> Union{Rational,Nothing}


"""
function exact_root(val::Union{Integer,Rational}, n::Int)::Union{Rational,Nothing}
    (val < 0 && iseven(n)) && return nothing
    num = val isa Rational ? numerator(val) : val
    den = val isa Rational ? denominator(val) : 1
    rn = iroot(abs(num), n)
    rd = iroot(den, n)
    (rn === nothing || rd === nothing) && return nothing
    result = rn // rd
    return num < 0 ? -result : result
end

"""
    fold_roots(expr::Num) -> Num
"""
function fold_roots(expr::Num)::Num
    subs = Dict{Any, Any}()
    function collect!(u)
        SymbolicUtils.iscall(u) || return
        op = SymbolicUtils.operation(u)
        args = SymbolicUtils.arguments(u)
        foreach(a -> collect!(Symbolics.unwrap(a)), args)

        if (op === sqrt || op === cbrt) && length(args) == 1
            arg_u = Symbolics.unwrap(args[1])
            val = SymbolicUtils.isconst(arg_u) ? SymbolicUtils.unwrap_const(arg_u) :
                  (arg_u isa Number ? arg_u : nothing)
            if val isa Union{Integer,Rational}
                r = exact_root(val, op === sqrt ? 2 : 3)
                r !== nothing && (subs[u] = r)
            end
        end
    end
    collect!(Symbolics.unwrap(expr))
    isempty(subs) && return expr
    return Num(Symbolics.substitute(expr, subs))
end

function _jerbie_pi_multiple(t)
    t == "PI" && return 1
    t isa AbstractString && return nothing
    op, args = t
    if op == "*" && length(args) == 2
        a, b = args
        an = a isa AbstractString ? _leaf_to_number(a) : nothing
        an !== nothing && b == "PI" && return an
        bn = b isa AbstractString ? _leaf_to_number(b) : nothing
        bn !== nothing && a == "PI" && return bn
    elseif op == "/" && length(args) == 2
        a, b = args
        if a == "PI"
            bn = b isa AbstractString ? _leaf_to_number(b) : nothing
            bn !== nothing && return 1 // bn
        end
    end
    return nothing
end

function _jerbie_reduce_tree(tree)
    tree isa AbstractString && return tree
    op, raw_args = tree
    args = Any[_jerbie_reduce_tree(a) for a in raw_args]
    argn(i) = args[i] isa AbstractString ? _leaf_to_number(args[i]) : nothing

    if length(args) == 1
        a1n = argn(1)
        if a1n !== nothing
            op == "exp" && a1n == 0 && return "1"
            op == "log" && a1n == 1 && return "0"
            op == "sin" && a1n == 0 && return "0"
            op == "cos" && a1n == 0 && return "1"
            op == "tan" && a1n == 0 && return "0"
            op == "sinh" && a1n == 0 && return "0"
            op == "cosh" && a1n == 0 && return "1"
            op == "exp" && a1n == 1 && return "E"
        end
        args[1] == "E" && op == "log" && return "1"

        pm = _jerbie_pi_multiple(args[1])
        if pm !== nothing
            op == "sin" && pm == 1 && return "0"
            op == "cos" && pm == 1 && return "-1"
            op == "tan" && pm == 1 && return "0"
            op == "cos" && pm == 1 // 6 && return ("/", [("sqrt", ["3"]), "2"])
            op == "tan" && pm == 1 // 3 && return ("sqrt", ["3"])
            op == "tan" && pm == 1 // 4 && return "1"
            op == "cos" && pm == 1 // 2 && return "0"
            op == "tan" && pm == 1 // 6 && return ("/", ["1", ("sqrt", ["3"])])
            op == "sin" && pm == 1 // 3 && return ("/", [("sqrt", ["3"]), "2"])
            op == "sin" && pm == 1 // 6 && return ("/", ["1", "2"])
            op == "sin" && pm == 1 // 4 && return ("/", [("sqrt", ["2"]), "2"])
            op == "sin" && pm == 1 // 2 && return "1"
            op == "cos" && pm == 1 // 3 && return ("/", ["1", "2"])
            op == "cos" && pm == 1 // 4 && return ("/", [("sqrt", ["2"]), "2"])
        end

        if !(args[1] isa AbstractString)
            inner_op, inner_args = args[1]
            if length(inner_args) == 1
                x = inner_args[1]
                (op, inner_op) in (("tanh", "atanh"), ("cosh", "acosh"), ("sinh", "asinh"),
                                   ("acos", "cos"), ("asin", "sin"), ("atan", "tan"),
                                   ("tan", "atan"), ("cos", "acos"), ("sin", "asin"),
                                   ("log", "exp"), ("exp", "log")) && return x
            end
        end

        if op == "cbrt" && !(args[1] isa AbstractString)
            aop, aargs = args[1]
            if aop == "pow" && length(aargs) == 2
                bexp = aargs[2] isa AbstractString ? _leaf_to_number(aargs[2]) : nothing
                bexp == 3 && return aargs[1]
            end
        end
        if op == "exp" && !(args[1] isa AbstractString)
            aop, aargs = args[1]
            if aop == "*" && length(aargs) == 2
                for (c, l) in ((aargs[1], aargs[2]), (aargs[2], aargs[1]))
                    if !(l isa AbstractString)
                        lop, largs = l
                        lop == "log" && length(largs) == 1 && return ("pow", [largs[1], c])
                    end
                end
            end
        end
    elseif length(args) == 2
        if op == "pow"
            e = argn(2)
            e == 1 && return args[1]
            if !(args[1] isa AbstractString)
                bop, bargs = args[1]
                bop == "cbrt" && length(bargs) == 1 && e == 3 && return bargs[1]
            end
        end
    end

    return (op, args)
end

function _jerbie_reduce(x::Num)::Num
    try
        tree = parse_sexpr(to_sexpr(x))
        folded = _jerbie_reduce_tree(tree)
        vars = Dict{String, Num}(name => Num(Symbolics.variable(Symbol(name))) for name in _tree_symbols(folded))
        return build_expr(folded, vars)
    catch
        return x
    end
end

# series-ref
function series_ref(s::TSeries, n::Int)::Num
    for i in length(s.cache):n
        fetch = j -> s.cache[j]
        raw = fold_roots(_jerbie_reduce(Num(simplify(s.builder(fetch, i)))))
        s.cache[i] = Num(to_bigInt(Symbolics.unwrap(raw)))
    end
    return s.cache[n]
end

function series_function(s::TSeries)
    return n -> series_ref(s, n)
end

"""
    safe_factorial(n) -> Integer

Julia's factorial() throws OverflowError after n=20 
"""
safe_factorial(n::Integer) = n > 20 ? factorial(big(n)) : factorial(n)

# zero-series
function zero_series(s::TSeries)::Function
    return n -> n < -s.offset ? Num(0) : series_ref(s, n + s.offset)
end

# taylor-exact
function taylor_exact(terms::Num...)::TSeries
    items = collect(terms)
    len = length(items)
    return make_series(0, (fetch, n) -> n < len ? items[n+1] : Num(0))
end

# first-nonzero-exp
function first_nonzero_exp(f::Function)::Int
    n = 0
    while isequal(f(n), 0) && n < 20
        n += 1
    end
    return n
end

# normalize-series
function normalize_series(s::TSeries)::TSeries
    slack = first_nonzero_exp(series_function(s))
    slack == 0 && return s
    return make_series(s.offset - slack, (fetch, n) -> series_ref(s, n + slack))
end

# taylor-add
function taylor_add(left::TSeries, right::TSeries)::TSeries
    target_offset = max(left.offset, right.offset)
    function align(offset, series)
        shift = offset - target_offset
        shift == 0 && return series_function(series)
        return n -> (n + shift < 0) ? Num(0) : series_ref(series, n + shift)
    end
    left_ = align(left.offset, left)
    right_ = align(right.offset, right)
    return make_series(target_offset, (fetch, n) -> left_(n) + right_(n))
end

# taylor-negate
function taylor_negate(term::TSeries)::TSeries
    return make_series(term.offset, (fetch, n) -> -series_ref(term, n))
end

# taylor-mult
function taylor_mult(left::TSeries, right::TSeries)::TSeries
    offset = left.offset + right.offset
    function builder(fetch, n)
        terms = Num[]
        for i in 0:n
            li = series_ref(left, i)
            ri = series_ref(right, n - i)
            (isequal(li, 0) || isequal(ri, 0)) && continue
            push!(terms, li * ri)
        end
        isempty(terms) ? Num(0) : sum(terms)
    end
    return make_series(offset, builder)
end

# taylor-invert
function taylor_invert(term::TSeries)::TSeries
    normalized = normalize_series(term)
    b = series_function(normalized)
    function builder(fetch, n)
        n == 0 && return 1 / b(0)
        return -sum(fetch(i) * (b(n - i) / b(0)) for i in 0:(n - 1))
    end
    return make_series(-normalized.offset, builder)
end

# taylor-quotient
function taylor_quotient(num::TSeries, denom::TSeries)::TSeries
    nn = normalize_series(num)
    nd = normalize_series(denom)
    a = series_function(nn)
    b = series_function(nd)
    function builder(fetch, n)
        n == 0 && return a(0) / b(0)
        s = sum(fetch(i) * (b(n - i) / b(0)) for i in 0:(n - 1))
        return (a(n) / b(0)) - s
    end
    return make_series(nn.offset - nd.offset, builder)
end

# modulo-series
function modulo_series(var, n::Int, s::TSeries)::TSeries
    normalized = normalize_series(s)
    offset = normalized.offset
    coeffs = series_function(normalized)
    offset_star = offset + mod(-offset, n)
    offset == offset_star && return normalized

    cache = Dict{Int,Num}()
    function coeffs_star(i::Int)::Num
        haskey(cache, i) && return cache[i]
        res = if i == 0
            terms = [coeffs(j) * var^(j + mod(-offset, n)) for j in 0:(mod(offset, n) - 1)]
            isempty(terms) ? Num(0) : sum(terms)
        elseif i < n
            Num(0)
        else
            coeffs(i - n + mod(offset, n))
        end
        cache[i] = res
        return res
    end
    return make_series(offset_star, (fetch, i) -> coeffs_star(i))
end

# taylor-sqrt
function taylor_sqrt(var, num::TSeries)::TSeries
    normalized = modulo_series(var, 2, num)
    offset_star = normalized.offset
    coeffs_star = series_function(normalized)
    function builder(fetch, n)
        n == 0 && return sqrt(coeffs_star(0))
        n == 1 && return coeffs_star(1) / (2 * sqrt(coeffs_star(0)))
        cross = Num(0)
        for k in 1:(n - 1)
            2k < n || break
            cross += 2 * fetch(k) * fetch(n - k)
        end
        if iseven(n)
            mid = fetch(n ÷ 2)^2
            return (coeffs_star(n) - mid - cross) / (2 * fetch(0))
        else
            return (coeffs_star(n) - cross) / (2 * fetch(0))
        end
    end
    return make_series(offset_star ÷ 2, builder)
end

# taylor-cbrt
const n_sum_to_cache = Dict{Tuple{Int,Int},Vector{Vector{Int}}}()
function n_sum_to(num_slots::Int, target_sum::Int)::Vector{Vector{Int}}
    key = (num_slots, target_sum)
    haskey(n_sum_to_cache, key) && return n_sum_to_cache[key]
    result = if target_sum == 0
        [fill(0, num_slots)]
    elseif num_slots == 1
        [[target_sum]]
    elseif num_slots == 0
        Vector{Int}[]
    else
        r = Vector{Int}[]
        for i in 0:target_sum, v in n_sum_to(num_slots - 1, target_sum - i)
            push!(r, [i; v])
        end
        r
    end
    return n_sum_to_cache[key] = result
end

function taylor_cbrt(var, num::TSeries)::TSeries
    normalized = modulo_series(var, 3, num)
    offset_star = normalized.offset
    coeffs_star = series_function(normalized)
    function builder(fetch, n)
        n == 0 && return cbrt(coeffs_star(0))
        n == 1 && return coeffs_star(1) / (3 * cbrt(fetch(0) * fetch(0)))
        cross = Num(0)
        for (a, b, c) in n_sum_to(3, n)
            (a == n || b == n || c == n) && continue
            cross += fetch(a) * fetch(b) * fetch(c)
        end
        return (coeffs_star(n) - cross) / (3 * fetch(0) * fetch(0))
    end
    return make_series(offset_star ÷ 3, builder)
end

# taylor-fabs 
function taylor_fabs(var, term::TSeries)::Union{TSeries,Nothing}
    normalized = normalize_series(term)
    offset = normalized.offset
    a0 = series_ref(normalized, 0)
    a0_u = Symbolics.unwrap(a0)
    a0_val = SymbolicUtils.isconst(a0_u) ? SymbolicUtils.unwrap_const(a0_u) : a0_u
    (a0_val isa Number) || return nothing
    iszero(a0_val) && return nothing

    if iseven(offset) && a0_val < 0
        return taylor_negate(normalized)
    elseif iseven(offset) && a0_val > 0
        return normalized
    elseif isodd(offset)
        sign_factor = a0_val < 0 ? -1 : 1
        scale_factor = fabs(var) * sign_factor
        new_offset = offset + 1
        return make_series(new_offset,
            (fetch, n) -> n == 0 ? scale_factor : series_ref(normalized, n + (new_offset - offset)))
    else
        return nothing
    end
end

# taylor-pow (Russian peasant)
function taylor_pow(coeffs::TSeries, n::Int)::TSeries
    n < 0 && return taylor_pow(taylor_invert(coeffs), -n)
    n == 0 && return taylor_exact(Num(1))
    n == 1 && return coeffs
    if iseven(n)
        half = taylor_pow(coeffs, n ÷ 2)
        return taylor_mult(half, half)
    else
        half = taylor_pow(coeffs, (n - 1) ÷ 2)
        return taylor_mult(coeffs, taylor_mult(half, half))
    end
end

# all-partitions
function all_partitions(n::Int, options::Vector{Int})::Vector{Vector{Tuple{Int,Int}}}
    isempty(options) && return n == 0 ? [Tuple{Int,Int}[]] : Vector{Tuple{Int,Int}}[]
    k = options[1]
    rest_options = options[2:end]
    result = Vector{Tuple{Int,Int}}[]
    i = 0
    while k * i <= n
        if i == 0
            append!(result, all_partitions(n, rest_options))
        else
            for p in all_partitions(n - k * i, rest_options)
                push!(result, vcat([(i, k)], p))
            end
        end
        i += 1
    end
    return result
end

# taylor-exp
function taylor_exp(coeffs::Function)::TSeries
    function builder(fetch, n)
        n == 0 && return exp(coeffs(0))
        coeffs_vec = [coeffs(i) for i in 1:n]
        nums = sort([i for i in 1:n if !isequal(coeffs_vec[i], 0)], rev=true)
        terms = Num[]
        for p in all_partitions(n, nums)
            factor = Num(1)
            for (count, num) in p
                factor *= coeffs_vec[num]^count / safe_factorial(count)
            end
            push!(terms, factor)
        end
        total = isempty(terms) ? Num(0) : sum(terms)
        return exp(coeffs(0)) * total
    end
    return make_series(0, builder)
end

# taylor-sin
function taylor_sin(coeffs::Function)::TSeries
    function builder(fetch, n)
        n == 0 && return Num(0)
        coeffs_vec = [coeffs(i) for i in 1:n]
        nums = sort([i for i in 1:n if !isequal(coeffs_vec[i], 0)], rev=true)
        terms = Num[]
        for p in all_partitions(n, nums)
            total_count = sum(c for (c, _) in p; init=0)
            mod(total_count, 2) == 1 || continue
            sign = mod(total_count, 4) == 1 ? 1 : -1
            factor = Num(sign)
            for (count, num) in p
                factor *= coeffs_vec[num]^count / safe_factorial(count)
            end
            push!(terms, factor)
        end
        isempty(terms) ? Num(0) : sum(terms)
    end
    return make_series(0, builder)
end

# taylor-cos
function taylor_cos(coeffs::Function)::TSeries
    function builder(fetch, n)
        n == 0 && return Num(1)
        coeffs_vec = [coeffs(i) for i in 1:n]
        nums = sort([i for i in 1:n if !isequal(coeffs_vec[i], 0)], rev=true)
        terms = Num[]
        for p in all_partitions(n, nums)
            total_count = sum(c for (c, _) in p; init=0)
            mod(total_count, 2) == 0 || continue
            sign = mod(total_count, 4) == 0 ? 1 : -1
            factor = Num(sign)
            for (count, num) in p
                factor *= coeffs_vec[num]^count / safe_factorial(count)
            end
            push!(terms, factor)
        end
        isempty(terms) ? Num(0) : sum(terms)
    end
    return make_series(0, builder)
end

# list-setinc / loggenerate / lognormalize / logstep / logcompute / taylor-log
function list_setinc(l::Vector{Int}, i::Int)::Vector{Int}
    l = copy(l)
    l[i + 1] -= 1
    if i + 1 == length(l)
        push!(l, 1)
    else
        l[i + 2] += 1
    end
    return l
end

function loggenerate(table::Vector{Vector{Int}})::Vector{Vector{Int}}
    result = Vector{Int}[]
    for term in table
        coeff = term[1]
        ps = term[2:end]
        for (i, p) in enumerate(ps)
            p == 0 && continue
            push!(result, vcat([coeff * p], list_setinc(ps, i - 1)))
        end
    end
    return result
end

function lognormalize(table::Vector{Vector{Int}})::Vector{Vector{Int}}
    groups = Dict{Vector{Int},Int}()
    order = Vector{Int}[]
    for term in table
        coeff, ps = term[1], term[2:end]
        if haskey(groups, ps)
            groups[ps] += coeff
        else
            groups[ps] = coeff
            push!(order, ps)
        end
    end
    return [vcat([groups[ps]], ps) for ps in order if groups[ps] != 0]
end

logstep(table) = lognormalize(loggenerate(table))

const _log_cache = Dict{Int,Vector{Vector{Int}}}(1 => [[1, -1, 1]])
function logcompute(i::Int)::Vector{Vector{Int}}
    haskey(_log_cache, i) && return _log_cache[i]
    return _log_cache[i] = logstep(logcompute(i - 1))
end

function taylor_log(var, arg::TSeries)::TSeries
    normalized = normalize_series(arg)
    shift = normalized.offset
    coeffs = series_function(normalized)

    c0 = coeffs(0)
    c0_u = Symbolics.unwrap(c0)
    c0_val = SymbolicUtils.isconst(c0_u) ? SymbolicUtils.unwrap_const(c0_u) : c0_u
    negate = (c0_val isa Number) && !(c0_val > 0)
    maybe_negate(e) = negate ? -e : e

    function base_builder(fetch, n)
        n == 0 && return log(maybe_negate(coeffs(0)))
        tmpl = logcompute(n)
        coeffs_star = [coeffs(i) for i in 1:n]
        relevant = Num[]
        for term in tmpl
            coeff, k, ps = term[1], term[2], term[3:end]
            skip = any(p != 0 && isequal(coeffs_star[i], 0) for (i, p) in enumerate(ps))
            skip && continue
            numerator_factors = [(safe_factorial(i) * coeffs_star[i])^p for (i, p) in enumerate(ps) if p != 0]
            num_product = isempty(numerator_factors) ? Num(1) : prod(numerator_factors)
            push!(relevant, coeff * (num_product / exp(-k * fetch(0))))
        end
        total = isempty(relevant) ? Num(0) : sum(relevant)
        return total / safe_factorial(n)
    end

    base = make_series(0, base_builder)
    shift == 0 && return base
    shift_term = make_series(0, (fetch, n) -> n == 0 ? (-shift * log(maybe_negate(var))) : Num(0))
    return taylor_add(base, shift_term)
end

function expand_taylor(tree)
    tree isa AbstractString && return tree
    op, raw_args = tree
    args = [expand_taylor(a) for a in raw_args]

    if op == "-" && length(args) == 2
        return ("+", [args[1], ("neg", [args[2]])])
    elseif op == "pow" && length(args) == 2
        p = _leaf_to_number(args[2])
        p == 1//2 && return ("sqrt", [args[1]])
        p == 1//3 && return ("cbrt", [args[1]])
        p == 2//3 && return ("cbrt", [("*", [args[1], args[1]])])
        p isa Integer && return ("pow", args)
        return ("exp", [("*", [args[2], ("log", [args[1]])])])
    elseif op == "tan"
        return ("/", [("sin", args), ("cos", args)])
    elseif op == "cosh"
        return ("*", ["1/2", ("+", [("exp", args), ("/", ["1", ("exp", args)])])])
    elseif op == "sinh"
        return ("*", ["1/2", ("+", [("exp", args), ("/", ["-1", ("exp", args)])])])
    elseif op == "tanh"
        return ("/", [("+", [("exp", args), ("neg", [("/", ["1", ("exp", args)])])]),
                      ("+", [("exp", args), ("/", ["1", ("exp", args)])])])
    elseif op == "asinh"
        a = args[1]
        return ("log", [("+", [a, ("sqrt", [("+", [("*", [a, a]), "1"])])])])
    elseif op == "acosh"
        a = args[1]
        return ("log", [("+", [a, ("sqrt", [("+", [("*", [a, a]), "-1"])])])])
    elseif op == "atanh"
        a = args[1]
        return ("*", ["1/2", ("log", [("/", [("+", ["1", a]), ("+", ["1", ("neg", [a])])])])])
    else
        return (op, args)
    end
end

function _tree_to_string(tree)::String
    tree isa AbstractString && return tree
    op, args = tree
    return "($op " * join(_tree_to_string.(args), " ") * ")"
end

function _tree_symbols(tree)::Set{String}
    syms = Set{String}()
    function walk(t)
        if t isa AbstractString
            (_leaf_to_number(t) === nothing && !haskey(NAMED_CONSTANTS, t)) && push!(syms, t)
        else
            foreach(walk, t[2])
        end
    end
    walk(tree)
    return syms
end

function _tree_to_num(tree, var::Num)::Num
    varname = string(var)
    syms = _tree_symbols(tree)
    vars = Dict{String,Num}(s => (s == varname ? var : Num(Symbolics.variable(Symbol(s)))) for s in syms)
    return from_sexpr(_tree_to_string(tree), vars)
end

function taylor_series(var::Num, tree)::TSeries
    varname = string(var)

    if tree isa AbstractString
        tree == varname && return taylor_exact(Num(0), Num(1))
        n = _leaf_to_number(tree)
        n !== nothing && return taylor_exact(Num(n))
        haskey(NAMED_CONSTANTS, tree) && return taylor_exact(Num(NAMED_CONSTANTS[tree]))
        return taylor_exact(Num(Symbolics.variable(Symbol(tree))))
    end

    op, args = tree
    if op == "+"
        return taylor_add(taylor_series(var, args[1]), taylor_series(var, args[2]))
    elseif op == "-"
        return taylor_add(taylor_series(var, args[1]), taylor_negate(taylor_series(var, args[2])))
    elseif op == "neg"
        return taylor_negate(taylor_series(var, args[1]))
    elseif op == "*"
        return taylor_mult(taylor_series(var, args[1]), taylor_series(var, args[2]))
    elseif op == "/"
        _leaf_to_number(args[1]) == 1 && return taylor_invert(taylor_series(var, args[2]))
        return taylor_quotient(taylor_series(var, args[1]), taylor_series(var, args[2]))
    elseif op == "sqrt"
        return taylor_sqrt(var, taylor_series(var, args[1]))
    elseif op == "cbrt"
        return taylor_cbrt(var, taylor_series(var, args[1]))
    elseif op == "fabs" || op == "abs"
        result = taylor_fabs(var, taylor_series(var, args[1]))
        result !== nothing && return result
        return taylor_exact(_tree_to_num(tree, var))
    elseif op == "exp"
        arg_star = normalize_series(taylor_series(var, args[1]))
        arg_star.offset > 0 && return taylor_exact(_tree_to_num(tree, var))
        return taylor_exp(zero_series(arg_star))
    elseif op == "sin"
        arg_star = normalize_series(taylor_series(var, args[1]))
        if arg_star.offset > 0
            return taylor_exact(_tree_to_num(tree, var))
        elseif arg_star.offset == 0
            a0 = series_ref(arg_star, 0)
            return taylor_add(
                taylor_mult(taylor_exact(sin(a0)), taylor_cos(zero_series(arg_star))),
                taylor_mult(taylor_exact(cos(a0)), taylor_sin(zero_series(arg_star))))
        else
            return taylor_sin(zero_series(arg_star))
        end
    elseif op == "cos"
        arg_star = normalize_series(taylor_series(var, args[1]))
        if arg_star.offset > 0
            return taylor_exact(_tree_to_num(tree, var))
        elseif arg_star.offset == 0
            a0 = series_ref(arg_star, 0)
            return taylor_add(
                taylor_mult(taylor_exact(cos(a0)), taylor_cos(zero_series(arg_star))),
                taylor_negate(taylor_mult(taylor_exact(sin(a0)), taylor_sin(zero_series(arg_star)))))
        else
            return taylor_cos(zero_series(arg_star))
        end
    elseif op == "log"
        return taylor_log(var, taylor_series(var, args[1]))
    elseif (op == "pow" || op == "^") && length(args) == 2
        exp_n = _leaf_to_number(args[2])
        exp_n isa Integer && return taylor_pow(normalize_series(taylor_series(var, args[1])), exp_n)
        return taylor_exact(_tree_to_num(tree, var))
    else
        return taylor_exact(_tree_to_num(tree, var))
    end
end

function make_monomial(var, power::Int)::Num
    power == 0 && return Num(1)
    power == 1 && return var
    power < 0 && return 1 / var^(-power)
    return var^power
end

function make_horner(var, terms::Vector{Tuple{Num,Int}}, start::Int=0)::Num
    isempty(terms) && return Num(0)
    c, n = terms[1]
    length(terms) == 1 && return c * make_monomial(var, n - start)
    return make_monomial(var, n - start) * (c + make_horner(var, terms[2:end], n))
end

function make_approximator(s::TSeries, orig_var::Num, finv::Function; iters::Int=5)
    result_var = finv(orig_var)
    terms = Tuple{Num,Int}[]
    i = Ref(0)
    function next()::Num
        iter = 0
        while true
            raw_coeff = series_ref(s, i[])
            coeff = simplify(Symbolics.substitute(raw_coeff, Dict(orig_var => result_var)))
            i[] += 1
            if isequal(coeff, 0)
                iter >= iters && return make_horner(result_var, terms)
                iter += 1
            else
                push!(terms, (coeff, i[] - s.offset - 1))
                return make_horner(result_var, terms)
            end
        end
    end
    return next
end

"""
    taylor_candidates(expr::Num, var::Num; max_candidates::Int=2) -> Vector{Num}

"""
function taylor_candidates(expr::Num, var::Num; max_candidates::Int=2)::Vector{Num}
    candidates = Num[Num(0)]

    transforms = [
        (identity, identity),
        (x -> 1 / x, x -> 1 / x),
        (x -> -1 / x, x -> -1 / x),
    ]

    for (f, finv) in transforms
        substituted = Symbolics.substitute(expr, Dict(var => f(var)))
        tree = expand_taylor(parse_sexpr(to_sexpr(substituted)))
        series = taylor_series(var, tree)
        next_approx = make_approximator(series, var, finv)
        for _ in 1:max_candidates
            push!(candidates, next_approx())
        end
    end

    return candidates
end

"""
    taylor_variations(expr::Num, vars::Vector{Num}) -> Vector{Num}

Generates Taylor-expansion candidates .
"""
function taylor_variations(expr::Num, vars::Vector{Num})::Vector{Num}
    candidates = Num[]
    for var in vars
        append!(candidates, taylor_candidates(expr, var))
    end
    return candidates
end
