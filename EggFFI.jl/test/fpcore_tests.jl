using Test
using Symbolics

include("../src/EggFFI.jl")
using .EggFFI

module FPCoreBench
    include("fpcore_bench.jl")
end

cases_names = [s for s in names(FPCoreBench, all=true) if startswith(string(s), "bench_")]
cases_exprs = [getfield(FPCoreBench, s) for s in cases_names]
cases_pairs = collect(zip(cases_names, cases_exprs))

# use set to get unique eclasses
function canonical_eclass_ids(ptr)
    n = egraph_size(ptr)
    seen = Set{UInt32}()
    for id in 0:(n - 1)
        push!(seen, egraph_find(ptr, id))
    end
    return seen
end

@testset "fpcore enode coverage — from_sexpr on all enodes" begin
    for (name, expr) in cases_pairs
        vars = Dict{String, Num}(string(v) => Num(v) for v in Symbolics.get_variables(expr))
        label = string(name)

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

@testset "display_fpcore_existing_errors per case" begin
    for (name, expr) in cases_pairs
        vars = Dict{String, Num}(string(v) => Num(v) for v in Symbolics.get_variables(expr))
        label = string(name)

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
