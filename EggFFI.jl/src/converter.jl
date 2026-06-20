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

# Rational(p,0) is Julia's exact-arithmetic infinity — egg has no such literal.
struct ExactInfinityError <: Exception end

# before we used string() which worked fine for Int , but not for rational . 
# ex. string(3//7) -> "3//7" (egg can't parse) vs "(/ 3 7)" (egg can parse) [rational_fuzz]
function _num_to_sexpr(n)::String
    if n isa Rational
        # zero denominator — exact infinity, egg has no such literal, skip
        denominator(n) == 0 && throw(ExactInfinityError())
        denominator(n) == 1 && return string(numerator(n))
        return "(/ $(numerator(n)) $(denominator(n)))"
    end
    return string(n)
end

function to_sexpr(expr)::String
    expr = Symbolics.unwrap(expr)

    # Numeric leaf: Julia Number (Int, Float64, Rational, etc.)
    # Must be checked before iscall since iscall only works on BSImpl.Type.
    expr isa Number && return _num_to_sexpr(expr)

    # from printing.jl : BSImpl.Const(; val) get covered in parens {not egg parsable}
    if SymbolicUtils.isconst(expr)
        val = SymbolicUtils.unwrap_const(expr)
        val isa Number && return _num_to_sexpr(val)
        error("to_sexpr: unexpected non-numeric Const value: $(typeof(val)) = $val")
    end

    iscall(expr) || return string(expr)

    if SymbolicUtils.ismul(expr)
        return _mul_to_sexpr(expr)
    elseif SymbolicUtils.isadd(expr)
        return _add_to_sexpr(expr)
    else
        op = operation(expr)
        args = sorted_arguments(expr)
        return "($(nameof(op)) $(join(map(to_sexpr, args), " ")))"
    end
end

# fold a list of s-expr term strings into nested binary form
# herbie/src/syntax/sugar.rkt
# egg/MathLang's Add/Mul/Sub are strictly binary (Add([Id; 2])) 
# N-ary (op a b c ...) must be folded to binary before crossing the FFI boundary and before reaching egg-herbie.
function _fold_to_binary(op::String, terms::Vector{String})::String
    length(terms) == 1 && return terms[1]
    return "($op $(terms[1]) $(_fold_to_binary(op, terms[2:end])))"
end

function _mul_to_sexpr(expr)::String
    coeff = MData.variant_getfield(expr, BSImpl.AddMul, :coeff)
    dict = MData.variant_getfield(expr, BSImpl.AddMul, :dict)

    # coeff=-1, single dict term → (neg term)
    if coeff == -1 && length(dict) == 1
        term, exp = only(dict)
        inner = exp == 1 ? to_sexpr(term) : to_sexpr(term ^ exp)
        return "(neg $inner)"
    end

    # fold coeff (if != 1) and all dict factors into nested binary (* ...)
    factors = String[]
    coeff == 1 || push!(factors, _num_to_sexpr(coeff))
    for (term, exp) in dict
        push!(factors, exp == 1 ? to_sexpr(term) : to_sexpr(term ^ exp))
    end

    return _fold_to_binary("*", factors)
end

# emit (+ c x) for all cases — constant first, consistent ordering
# Case 1: coeff=0, one pos + one neg dict term  →  (- x y)
# Case 2: coeff<0, one pos dict term            →  (+ -c x)  ← fixed: was (- x c)
# Case 3: coeff>0, one neg dict term            →  (- c x)
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

    # fixed
    if coeff < 0 && length(pos) == 1 && isempty(neg)
        return "(+ $(_num_to_sexpr(coeff)) $(_term_str(pos[1]...)))"
    end

    if coeff > 0 && isempty(pos) && length(neg) == 1
        return "(- $(_num_to_sexpr(coeff)) $(_term_str(neg[1]...)))"
    end

    # coeff first:sorted_arguments places numeric constants before symbolic terms
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

# returns either a String (leaf) or Tuple{String, Vector{Any}} (compound node)
# recursive implementation
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

# totoken: split s-expression into tokens
# "+ (sqrt x) 1" → ["+", "(sqrt x)", "1"]
# AbstractString solves the MethodError
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

# build_expr: nested structure → Symbolics.Num
function build_expr(tree, vars::Dict{String, Num})::Num
    if tree isa String #leaf node
        # try Int
        vi = tryparse(Int, tree)
        vi !== nothing && return Num(vi)
        # try Float64
        vf = tryparse(Float64, tree)
        vf !== nothing && return Num(vf)
        return vars[tree]
    end
    op, args = tree
    # neg is a special case 
    if op == "neg"
        return -build_expr(args[1], vars)
    end
    f = OP_MAP[op]
    children = [build_expr(a, vars) for a in args]
    # Symbolics.jl/src/Symbolics.jl: VartypeT = @load_preference("vartype", "SymReal")
    # safer to deal with SafeReal/TreeReal
    return Num(TermInterface.maketerm(Symbolics.SymbolicT, f, Symbolics.unwrap.(children), nothing))
end

# from_sexpr
function from_sexpr(s::String, vars::Dict{String, Num})::Num
    build_expr(parse_sexpr(s), vars)
end
