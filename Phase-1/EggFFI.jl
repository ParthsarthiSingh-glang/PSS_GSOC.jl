module EggFFI


# compile lib.rs and DIR where (.dll on Windows, .so on Linux, .dylib on Mac) lives
const LIBPATH = joinpath(@__DIR__, "target", "release", "egg_julia_ffi")

export egraph_create, egraph_saturate!, egraph_extract, egraph_destroy