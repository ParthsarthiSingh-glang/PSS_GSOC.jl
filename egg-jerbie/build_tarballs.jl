using BinaryBuilder, Pkg

name = "Jerbie"
version = v"0.1.0"

sources = [
    GitSource("https://github.com/JuliaSymbolics/Jerbie.jl.git", "1ed69d016e66e716fa3c91505e549955a176c0be"),
]

script = raw"""
cd $WORKSPACE/srcdir/Jerbie.jl/egg-jerbie

# musl needs crt-static disabled for cdylib
if [[ "${target}" == *-musl* ]]; then
    export RUSTFLAGS="-C target-feature=-crt-static"
fi

cargo build --release
install -Dvm 755 target/${rust_target}/release/*jerbie.${dlext} "${libdir}/libjerbie.${dlext}"
install_license ../LICENSE
"""

platforms = supported_platforms()
# i686 Windows Rust toolchain is unusable
filter!(p -> !Sys.iswindows(p) || arch(p) != "i686", platforms)

products = [
    LibraryProduct("libjerbie", :libjerbie)
]

dependencies = Dependency[
    Dependency("CompilerSupportLibraries_jll"),
]

build_tarballs(ARGS, name, version, sources, script, platforms, products, dependencies; julia_compat="1.9", compilers=[:rust, :c], preferred_gcc_version=v"8")
