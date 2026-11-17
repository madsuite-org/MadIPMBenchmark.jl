# Point the environment at a MadIPM checkout and install it.
#
#     julia setup.jl MADIPM [--hsl=PATH]
#
# MADIPM is a checkout of MadIPM.jl at the commit to benchmark. It is linked as madipm/, from which
# the environment takes MadIPM and whose commit the results record. --hsl develops a licensed
# HSL_jll, for MA27 on the host.

using Pkg

function main(args)
    pos = filter(!startswith("--"), args)
    length(pos) == 1 || error("usage: julia setup.jl MADIPM [--hsl=PATH]")
    madipm = abspath(only(pos))
    isfile(joinpath(madipm, "src", "MadIPM.jl")) || error("$madipm is not a checkout of MadIPM.jl")
    link = joinpath(@__DIR__, "madipm")
    islink(link) && rm(link)
    ispath(link) && error("$link exists and is not a link")
    symlink(madipm, link)
    Pkg.activate(@__DIR__)
    for a in args
        m = match(r"^--hsl=(.*)$", a)
        m === nothing || Pkg.develop(path = abspath(m[1]))
    end
    isempty(Pkg.Registry.reachable_registries()) && Pkg.Registry.add("General")
    Pkg.resolve()
    Pkg.instantiate()
    Pkg.activate(joinpath(@__DIR__, "format"))
    Pkg.instantiate()
    println("benchmarking ", readchomp(`git -C $link rev-parse HEAD`), " from ", madipm)
    return
end

main(ARGS)
