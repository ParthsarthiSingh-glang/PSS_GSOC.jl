using BinaryBuilder, Pkg

name = "Jerbie"
version = v"0.1.0"

sources = [
    GitSource("https://github.com/JuliaSymbolics/Jerbie.jl.git", "FILL_IN_MAIN_REPO_COMMIT_SHA"),
    GitSource("https://github.com/herbie-fp/rival3.git", "FILL_IN_RIVAL3_COMMIT_SHA"; unpack_target="rival3"),
]

script = raw"""
cd $WORKSPACE/srcdir/Jerbie.jl/egg-julia-ffi

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
