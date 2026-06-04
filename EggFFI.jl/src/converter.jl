using TermInterface
using Symbolics

#to_sexpr: Symbolics expression -> s-expression string
#
# Symbolics wraps BasicSymbolic in Num — must call Symbolics.unwrap() first
# before TermInterface dispatch works correctly.
# evidence: iscall(::Num) = false, iscall(::BasicSymbolic) = true
#
#Using TermInterface (on unwrapped BasicSymbolic):
#   iscall(expr)            → true if compound node (has operator + arguments)
#   operation(expr)         → the operator (returns the actual Function, ex. +, sin)
#   sorted_arguments(expr)  → children in deterministic order
#
# Note: Symbolics represents a-b as a + (-1)*b internally (AddMul node)
# so operation() returns + for subtraction expressions — this is correct.
#
# Examples:
#   @variables x
#   to_sexpr(sqrt(x + 1) - sqrt(x))      # → "(+ (sqrt (+ x 1)) (* -1 (sqrt x)))"

function to_sexpr(expr)::String
    expr = Symbolics.unwrap(expr)   # Num → BasicSymbolic, no-op if already unwrapped
    if iscall(expr)
        # compound node: has operator and arguments
        op   = operation(expr)
        args = sorted_arguments(expr)
        # operation() returns a Function — not a Symbol - ALWAYS - \SymbolicUtils.jl\src\terminterface.jl
        op_str   = string(nameof(op))
        # safe for now : length of args <=2
        args_str = join(map(to_sexpr, args), " ")
        return "($(op_str) $(args_str))"
    else
        # only Sym or Const reach here — SymbolicUtils.jl/src/types.jl & terminterface.jl (iscall = false iff Sym or Const)
        # string() on a Sym prints its name, on a Const prints its value — no internal field access needed
        return string(expr)
    end
end
