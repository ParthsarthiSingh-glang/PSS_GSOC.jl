using TermInterface
using Symbolics
using SymbolicUtils
using SymbolicUtils: BSImpl, MData

include("rules.jl")

struct ExactInfinityError <: Exception end

const NAMED_CONSTANTS = Dict{String, Irrational}(
    "PI" => pi,
    "E"  => MathConstants.e,
)

const NAMED_CONSTANT_NAMES = Dict{Irrational, String}(
    pi => "PI",
    MathConstants.e => "E",
)

function _num_to_sexpr(n)::String
    if n isa Rational
        denominator(n) == 0 && throw(ExactInfinityError())
        denominator(n) == 1 && return string(numerator(n))
        return "(/ $(numerator(n)) $(denominator(n)))"
    end
    if n isa Irrational
        haskey(NAMED_CONSTANT_NAMES, n) && return NAMED_CONSTANT_NAMES[n]
        error("to_sexpr: no named-constant mapping for irrational $n; egg/rival only know PI and E")
    end
    if n isa AbstractFloat
        (isnan(n) || isinf(n)) && throw(ExactInfinityError())
        isinteger(n) && return string(BigInt(n))
        r = Rational{BigInt}(n)
        denominator(r) == 0 && throw(ExactInfinityError())
        return "(/ $(numerator(r)) $(denominator(r)))"
    end
    return string(n)
end

function to_sexpr(expr)::String
    expr = Symbolics.unwrap(expr)

    expr isa Number && return _num_to_sexpr(expr)

    if SymbolicUtils.isconst(expr)
        val = SymbolicUtils.unwrap_const(expr)
        val isa Number && return _num_to_sexpr(val)
        error("to_sexpr: unexpected non-numeric Const value: $(typeof(val)) = $val")
    end

    iscall(expr) || return string(expr)

    op = operation(expr)
    if op === identity
        arg = only(sorted_arguments(expr))
        SymbolicUtils.isconst(arg) && return _num_to_sexpr(SymbolicUtils.unwrap_const(arg))
        return to_sexpr(arg)
    end

    if SymbolicUtils.ismul(expr)
        return _mul_to_sexpr(expr)
    elseif SymbolicUtils.isadd(expr)
        return _add_to_sexpr(expr)
    else
        args = sorted_arguments(expr)
        return "($(nameof(op)) $(join(map(to_sexpr, args), " ")))"
    end
end

function _fold_to_binary(op::String, terms::Vector{String})::String
    length(terms) == 1 && return terms[1]
    return "($op $(terms[1]) $(_fold_to_binary(op, terms[2:end])))"
end

function _mul_to_sexpr(expr)::String
    coeff = MData.variant_getfield(expr, BSImpl.AddMul, :coeff)
    dict = MData.variant_getfield(expr, BSImpl.AddMul, :dict)

    if coeff == -1 && length(dict) == 1
        term, exp = only(dict)
        inner = exp == 1 ? to_sexpr(term) : to_sexpr(term ^ exp)
        return "(neg $inner)"
    end

    factors = String[]
    coeff == 1 || push!(factors, _num_to_sexpr(coeff))
    for (term, exp) in dict
        push!(factors, exp == 1 ? to_sexpr(term) : to_sexpr(term ^ exp))
    end

    return _fold_to_binary("*", factors)
end

function _add_to_sexpr(expr)::String
    coeff = MData.variant_getfield(expr, BSImpl.AddMul, :coeff)
    dict = MData.variant_getfield(expr, BSImpl.AddMul, :dict)

    pos = [(t, c) for (t, c) in dict if c > 0]
    neg = [(t, c) for (t, c) in dict if c < 0]

    _term_str(t, c) = c == 1 || c == -1 ? to_sexpr(t) :
                      "(* $(_num_to_sexpr(abs(c))) $(to_sexpr(t)))"

    if iszero(coeff) && length(pos) == 1 && length(neg) == 1
        return "(- $(_term_str(pos[1]...)) $(_term_str(neg[1]...)))"
    end

    if coeff < 0 && length(pos) == 1 && isempty(neg)
        return "(- $(_term_str(pos[1]...)) $(_num_to_sexpr(abs(coeff))))"
    end

    if coeff > 0 && isempty(pos) && length(neg) == 1
        return "(- $(_num_to_sexpr(coeff)) $(_term_str(neg[1]...)))"
    end

    terms = String[]
    if !iszero(coeff)
        coeff > 0 ? push!(terms, _num_to_sexpr(coeff)) :
        push!(terms, "(neg $(_num_to_sexpr(abs(coeff))))")
    end
    for (t, c) in pos
        push!(terms, _term_str(t, c))
    end
    for (t, c) in neg
        push!(terms, "(neg $(_term_str(t, abs(c))))")
    end

    return _fold_to_binary("+", terms)
end

function parse_sexpr(s::AbstractString)
    s = String(strip(s))
    if startswith(s, "(")
        inner = String(s[2:(end - 1)])
        tokens = totoken(inner)
        op = tokens[1]
        args = [parse_sexpr(t) for t in tokens[2:end]]
        return (op, args)
    else
        return s
    end
end

function totoken(s::AbstractString)::Vector{String}
    tokens = String[]
    depth = 0
    start = 1
    for (i, c) in enumerate(s)
        if c == '('
            depth += 1
        elseif c == ')'
            depth -= 1
        elseif c == ' ' && depth == 0
            push!(tokens, String(strip(s[start:(i - 1)])))
            start = i + 1
        end
    end
    push!(tokens, String(strip(s[start:end])))
    return tokens
end

function try_parse_rational(s::String)::Union{Rational{Int}, Rational{BigInt}, Nothing}
    try
        return parse(Rational{Int}, s)
    catch
    end
    try
        return parse(Rational{BigInt}, s)
    catch
        return nothing
    end
end

function _leaf_to_number(tree)::Union{Number, Nothing}
    tree isa String || return nothing
    vi = tryparse(Int, tree)
    vi !== nothing && return vi
    vr = try_parse_rational(tree)
    vr !== nothing && return vr
    vf = tryparse(Float64, tree)
    vf !== nothing && return vf
    return nothing
end

function build_expr(tree, vars::Dict{String, Num})::Num
    if tree isa String
        n = _leaf_to_number(tree)
        n !== nothing && return Num(n)
        haskey(NAMED_CONSTANTS, tree) && return Num(NAMED_CONSTANTS[tree])
        return vars[tree]
    end
    op, args = tree
    if op == "neg"
        return -build_expr(args[1], vars)
    end
    if op == "pow" || op == "^"
        base_n = _leaf_to_number(args[1])
        exp_n  = _leaf_to_number(args[2])
        if base_n isa Integer && exp_n isa Integer && exp_n < 0
            return Num(float(base_n)^exp_n)
        end
        return build_expr(args[1], vars) ^ build_expr(args[2], vars)
    end
    if op == "fma" || op == "muladd"
        f = op == "fma" ? fma : muladd
        return f(build_expr(args[1], vars), build_expr(args[2], vars), build_expr(args[3], vars))
    end
    f = OP_MAP[op]
    children = [build_expr(a, vars) for a in args]
    return Num(TermInterface.maketerm(Symbolics.SymbolicT, f, Symbolics.unwrap.(children), nothing))
end

function from_sexpr(s::String, vars::Dict{String, Num})::Num
    build_expr(parse_sexpr(s), vars)
end
