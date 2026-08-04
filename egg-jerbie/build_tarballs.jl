using BinaryBuilder, Pkg

name = "Jerbie"
version = v"0.1.0"

sources = [
    GitSource("https://github.com/JuliaSymbolics/Jerbie.jl.git", "1ed69d016e66e716fa3c91505e549955a176c0be"),
]

script = raw"""
cd $WORKSPACE/srcdir/Jerbie.jl/egg-jerbie

cargo build --release
install -Dvm 755 target/${rust_target}/release/*jerbie.${dlext} "${libdir}/libjerbie.${dlext}"
install_license ../LICENSE
"""

platforms = supported_platforms(exclude=p -> libc(p) == "musl" || p == Platform("i686", "windows"))

products = [
    LibraryProduct("libjerbie", :libjerbie)
]

dependencies = Dependency[
    Dependency("CompilerSupportLibraries_jll"),
]

build_tarballs(ARGS, name, version, sources, script, platforms, products, dependencies; julia_compat="1.9", compilers=[:rust, :c], preferred_gcc_version=v"8")
