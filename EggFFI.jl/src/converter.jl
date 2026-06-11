using TermInterface
using Symbolics
using SymbolicUtils
using SymbolicUtils: BSImpl, MData

include("rules.jl")

# to_sexpr: Symbolics.Num → egg s-expression string
#
# Symbolics stores arithmetic as AddMul nodes — SymbolicUtils/src/types.jl
#   ADD: coeff + sum(dict[term] * term)
#   MUL: coeff * prod(term^exp)
#
# We read coeff/dict directly to emit (- a b) and (neg a)
# matching Herbie rule patterns — herbie/src/core/rules.rkt

function to_sexpr(expr)::String
    expr = Symbolics.unwrap(expr)
    iscall(expr) || return string(expr)

    if SymbolicUtils.ismul(expr)
        return _mul_to_sexpr(expr)
    elseif SymbolicUtils.isadd(expr)
        return _add_to_sexpr(expr)
    else
        op   = operation(expr)
        args = sorted_arguments(expr)
        return "($(nameof(op)) $(join(map(to_sexpr, args), " ")))"
    end
end

# coeff=-1, single dict term → (neg term), else fallback
function _mul_to_sexpr(expr)::String
    coeff = MData.variant_getfield(expr, BSImpl.AddMul, :coeff)
    dict  = MData.variant_getfield(expr, BSImpl.AddMul, :dict)

    if coeff == -1 && length(dict) == 1
        term, exp = only(dict)
        inner = exp == 1 ? to_sexpr(term) : to_sexpr(term ^ exp)
        return "(neg $inner)"
    end

    op   = operation(expr)
    args = sorted_arguments(expr)
    return "($(nameof(op)) $(join(map(to_sexpr, args), " ")))"
end

# emit (- a b) for clean binary subtraction, else (+ ...)
# Case 1: coeff=0, one pos + one neg dict term  →  x - y
# Case 2: coeff<0, one pos dict term            →  x - 1
# Case 3: coeff>0, one neg dict term            →  1 - x
function _add_to_sexpr(expr)::String
    coeff = MData.variant_getfield(expr, BSImpl.AddMul, :coeff)
    dict  = MData.variant_getfield(expr, BSImpl.AddMul, :dict)

    pos = [(t, c) for (t, c) in dict if c > 0]
    neg = [(t, c) for (t, c) in dict if c < 0]

    _term_str(t, c) = c == 1 || c == -1 ? to_sexpr(t) : "(* $(abs(c)) $(to_sexpr(t)))"

    if iszero(coeff) && length(pos) == 1 && length(neg) == 1
        return "(- $(_term_str(pos[1]...)) $(_term_str(neg[1]...)))"
    end

    if coeff < 0 && length(pos) == 1 && isempty(neg)
        return "(- $(_term_str(pos[1]...)) $(abs(coeff)))"
    end

    if coeff > 0 && isempty(pos) && length(neg) == 1
        return "(- $(coeff) $(_term_str(neg[1]...)))"
    end

    op   = operation(expr)
    args = sorted_arguments(expr)
    return "($(nameof(op)) $(join(map(to_sexpr, args), " ")))"
end

# returns either a String (leaf) or Tuple{String, Vector{Any}} (compound node)
# recursive implementation
function parse_sexpr(s::AbstractString)
    s = String(strip(s))
    if startswith(s, "(")
        inner  = String(s[2:end-1])
        tokens = totoken(inner)
        op     = tokens[1]
        args   = [parse_sexpr(t) for t in tokens[2:end]]
        return (op, args)
    else
        return s
    end
end

# totoken: split s-expression into tokens
# "+ (sqrt x) 1" → ["+", "(sqrt x)", "1"]
# AbstractString solves the MethodError
function totoken(s::AbstractString)::Vector{String}
    tokens = String[]
    depth  = 0
    start  = 1
    for (i, c) in enumerate(s)
        if c == '('
            depth += 1
        elseif c == ')'
            depth -= 1
        elseif c == ' ' && depth == 0
            push!(tokens, String(strip(s[start:i-1])))
            start = i + 1
        end
    end
    push!(tokens, String(strip(s[start:end])))
    return tokens
end

# build_expr: nested structure → Symbolics.Num
function build_expr(tree, vars::Dict{String, Num})::Num
    if tree isa String #leaf node
        # try Int , Float64 
        vi = tryparse(Int, tree)
        vi !== nothing && return Num(vi)
        vf = tryparse(Float64, tree)
        vf !== nothing && return Num(vf)
        return vars[tree]
    end
    op, args = tree
    # neg is a special case 
    if op == "neg"
        return -build_expr(args[1], vars)
    end
    f        = OP_MAP[op]
    children = [build_expr(a, vars) for a in args]
    return Num(TermInterface.maketerm(SymbolicUtils.BasicSymbolic{SymbolicUtils.SymReal}, f, Symbolics.unwrap.(children), nothing))
end

# from_sexpr
function from_sexpr(s::String, vars::Dict{String, Num})::Num
    build_expr(parse_sexpr(s), vars)
end
