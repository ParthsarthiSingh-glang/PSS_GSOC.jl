using Test
using Symbolics

include("../src/EggFFI.jl")
using .EggFFI

@variables x

cases = [
    (1,   0),
    (2,   0),
    (0,   1),
    (0,   2),
    (3,   2),
    (3,   -2),
    (-2,  3),
    (-3,  -2),
]

@testset "egraph enode coverage — from_sexpr on all enodes" begin
    for (a, b) in cases
        if b == 0
            expr = sqrt(x + a) - sqrt(x)
        elseif a == 0
            expr = sqrt(x) - sqrt(x + b)
        else
            expr = sqrt(x + a) - sqrt(x + b)
        end

        vars = Dict("x" => x)
        label = "a=$a,b=$b"

        ptr = egraph_create(to_sexpr(expr))
        egraph_saturate!(ptr)

        n_classes = egraph_size(ptr)
        missing_ops = Dict{String, Int}()
        ok = 0

        for id in 0:(n_classes - 1)
            for enode in egraph_eclass_enodes(ptr, id)
                try
                    from_sexpr(enode, vars)
                    ok += 1
                catch e
                    if e isa KeyError
                        key = string(e.key)
                        missing_ops[key] = get(missing_ops, key, 0) + 1
                    end
                end
            end
        end

        egraph_destroy(ptr)

        @info "[$label] ok=$ok, missing=$(missing_ops)"
        @test isempty(missing_ops)
    end
end
