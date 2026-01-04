using Pkg
Pkg.activate(".")

using PackageCompiler

create_app(
    ".",                 # projekt gyoker
    "build/Chaos";        # output mappa
    script = "main.jl",
    force = true,
    incremental = true,
    include_transitive_dependencies = false,
    sysimage_build_args = `--strip-metadata`,
)
