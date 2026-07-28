using BinaryBuilder, Pkg

name = "Jerbie"
version = v"0.1.0"

sources = [
    GitSource("https://github.com/JuliaSymbolics/Jerbie.jl.git", "b1cc064252ce343830b14720ddb546e14dd1e542"),
    GitSource("https://github.com/herbie-fp/rival3.git", "58cb38e2cbad842a024fe9ef47cd581618ca20f2"; unpack_target="rival3"),
]

script = raw"""
cd $WORKSPACE/srcdir/Jerbie.jl/egg-jerbie

rm -rf rival3
cp -r $WORKSPACE/srcdir/rival3 ./rival3

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
