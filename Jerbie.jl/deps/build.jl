cratedir = joinpath(@__DIR__, "egg-jerbie")

cargo = Sys.which("cargo")
if cargo === nothing
    error(
        "cargo not found. Jerbie needs a Rust toolchain to build its native library.\n" *
        "Install one from https://rustup.rs, then run Pkg.build(\"Jerbie\") again."
    )
end

if Sys.iswindows()
    # gmp-mpfr-sys does not support the default MSVC toolchain, only MinGW/GNU
    rustup = Sys.which("rustup")
    if rustup === nothing
        error(
            "rustup not found. On Windows, Jerbie needs the GNU Rust toolchain " *
            "(gmp-mpfr-sys does not support MSVC).\n" *
            "Install rustup from https://rustup.rs, then run:\n" *
            "  rustup toolchain install stable-x86_64-pc-windows-gnu\n" *
            "and run Pkg.build(\"Jerbie\") again."
        )
    end
    run(Cmd(`$rustup run stable-x86_64-pc-windows-gnu cargo build --release`, dir = cratedir))
else
    run(Cmd(`$cargo build --release`, dir = cratedir))
end
