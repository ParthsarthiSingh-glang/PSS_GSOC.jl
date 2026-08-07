using BinaryBuilder, Pkg

name = "Jerbie"
version = v"0.1.0"

sources = [
    # TEMPORARY: pinned to the fork's build-jl branch for local testing only.
    # Revert to upstream JuliaSymbolics/Jerbie.jl once build-jl is merged.
    GitSource("https://github.com/ParthsarthiSingh-glang/Jerbie.jl.git", "d5d622d46a6dd46b3368f89f72a474e5e5085bc3"),
]

script = raw"""
cd $WORKSPACE/srcdir/Jerbie.jl/Jerbie.jl/deps/egg-jerbie

# musl needs crt-static disabled for cdylib
if [[ "${target}" == *-musl* ]]; then
    export RUSTFLAGS="-C target-feature=-crt-static"
fi

cargo build --release --features gmp-mpfr-sys/use-system-libs
install -Dvm 755 target/${rust_target}/release/*jerbie.${dlext} "${libdir}/libjerbie.${dlext}"
install_license ../../../LICENSE
"""

platforms = supported_platforms()
# i686 Windows Rust toolchain is unusable
filter!(p -> !Sys.iswindows(p) || arch(p) != "i686", platforms)

products = [
    LibraryProduct("libjerbie", :libjerbie)
]

dependencies = Dependency[
    Dependency("CompilerSupportLibraries_jll"),
    Dependency("GMP_jll"),
    Dependency("MPFR_jll"),
    Dependency("MPC_jll"),
]

build_tarballs(ARGS, name, version, sources, script, platforms, products, dependencies; julia_compat="1.9", compilers=[:rust, :c], preferred_gcc_version=v"8")
