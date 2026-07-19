"""
    taylor_expand(f, x, x0, orders) -> Vector{Num}

"""
function taylor_expand(f, x, x0, orders::AbstractVector{<:Integer})::Vector{Num}
    xshift = Num(Symbolics.variable(gensym(:xshift)))
    f_shifted = Symbolics.substitute(f, Dict(x => xshift + x0))
    return Symbolics.taylor_coeff(f_shifted, xshift, collect(orders))
end
