module EggFFI


# compile lib.rs and DIR where (.dll on Windows, .so on Linux, .dylib on Mac) lives
const LIBPATH = joinpath(@__DIR__, "target", "release", "egg_julia_ffi")

export egraph_create, egraph_saturate!, egraph_extract, egraph_destroy


"""
    egraph_create(expr::String) -> Ptr{Cvoid}

    Symbolic expression parsing -> Egraph creation -> returns a pointer.
"""
function egraph_create(expr::String)::Ptr{Cvoid}
    ccall((:egraph_create, LIBPATH), Ptr{Cvoid}, (Cstring,), expr)
end

"""
    egraph_saturate!(ptr::Ptr{Cvoid})

    Apply rewrite rules to the e-graph until saturation.
    Rules will we done in Phase-3 . 
"""
function egraph_saturate!(ptr::Ptr{Cvoid})
    ccall((:egraph_saturate, LIBPATH), Cvoid, (Ptr{Cvoid},), ptr)
end

# extract() and destroy() to be implemented.

end 
