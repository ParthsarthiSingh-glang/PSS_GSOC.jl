using TermInterface

#to_sexpr: Symbolics expression -> s-expression string
#
#Using TermInterface:
#   iscall(expr)            → true if compound node (has operator + arguments)
#   operation(expr)         → the operator (returns the actual Function, ex. +, sin)
#   sorted_arguments(expr)  → children in deterministic order
#
# Leaves are treated in the Else branch.
#
# Examples:
#   @variables x
#   to_sexpr(sqrt(x + 1) - sqrt(x))      # → "(- (sqrt (+ x 1)) (sqrt x))"

function to_sexpr(expr)::String
    if iscall(expr)
        # compound node: has operator and arguments
        op   = operation(expr)
        args = sorted_arguments(expr)
        # operation() returns a Function — not a Symbol - ALWAYS - \SymbolicUtils.jl\src\terminterface.jl
        op_str = string(nameof(op))
        # safe for now : length of args <=2
        args_str = join(map(to_sexpr, args), " ")
        return "($(op_str) $(args_str))"
    else
        # only Sym{name::Symbol} or Const{val::Any} reach here — SymbolicUtils.jl/src/types.jl & terminterface.jl (iscall = false iff Sym or Const)
        if issym(expr)
            return string(expr.name)
        else
            val = expr.val
            return val isa Integer ? string(val) : string(Float64(val))
        end
    end
end
