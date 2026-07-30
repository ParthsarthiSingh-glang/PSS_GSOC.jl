using BinaryBuilder, Pkg

name = "Jerbie"
version = v"0.1.0"

sources = [
    GitSource("https://github.com/ParthsarthiSingh-glang/Jerbie.jl.git", "a6b508388bdaa7372f930b76affecf9cec50424a"),
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
