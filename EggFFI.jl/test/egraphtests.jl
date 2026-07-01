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

# use set to get unique eclasses
function canonical_eclass_ids(ptr)
    n = egraph_size(ptr)
    seen = Set{UInt32}()
    for id in 0:(n - 1)
        push!(seen, egraph_find(ptr, id))
    end
    return seen
end

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

        ids = canonical_eclass_ids(ptr)
        missing_ops = Dict{String, Int}()
        ok = 0

        for id in ids
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

        @info "[$label] unique_eclasses=$(length(ids)) ok=$ok, missing=$(missing_ops)"
        @test isempty(missing_ops)
    end
end


@testset "display_existing_errors  per case" begin
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

        ids = canonical_eclass_ids(ptr)
        total_enodes = sum(length(egraph_eclass_enodes(ptr, id)) for id in ids)
        seen = Dict{String, Int}()

        for id in ids
            for enode in egraph_eclass_enodes(ptr, id)
                try
                    from_sexpr(enode, vars)
                catch e
                    key = "$enode  →  $(typeof(e)): $(e)"
                    seen[key] = get(seen, key, 0) + 1
                end
            end
        end

        egraph_destroy(ptr)

        @info "[$label] unique_eclasses=$(length(ids)) total_enodes=$total_enodes, errors=$(length(seen))"
        for (msg, count) in sort(collect(seen), by = x -> -x[2])
            println("    [×$count]  $msg")
        end
    end
end

@testset "egraph ConstantFold soundness — unsound flag per case" begin
    for (a, b) in cases
        if b == 0
            expr = sqrt(x + a) - sqrt(x)
        elseif a == 0
            expr = sqrt(x) - sqrt(x + b)
        else
            expr = sqrt(x + a) - sqrt(x + b)
        end

        label = "a=$a,b=$b"

        ptr = egraph_create(to_sexpr(expr))
        egraph_saturate!(ptr)

        unsound = ccall((:egraph_unsound, EggFFI.LIBPATH), Bool, (Ptr{Cvoid},), ptr)

        egraph_destroy(ptr)

        @info "[$label] unsound=$unsound"
        @test !unsound
    end
end
