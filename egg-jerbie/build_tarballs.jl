using BinaryBuilder, Pkg

name = "Jerbie"
version = v"0.1.0"

sources = [
    GitSource("https://github.com/JuliaSymbolics/Jerbie.jl.git", "b1cc064252ce343830b14720ddb546e14dd1e542"),
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
]

build_tarballs(ARGS, name, version, sources, script, platforms, products, dependencies; julia_compat="1.9", compilers=[:rust, :c])
