# What every process of a benchmark run loads: the packages, the benchmark module, the sets and the
# configurations. `DEVICE` (`:cpu` or `:cuda`) and `SET_NAMES` are defined by run.jl before this file
# is included, on this process and on every worker.

using SHA
import FileWatching
using MadIPM, MadNLP, MadNLPHSL, HSL, HiGHS, NLPModels, QPSReader, MIPLIB, GZip, Adapt, SparseMatricesCOO
DEVICE == :cuda && @eval using CUDA, CUDSS, KernelAbstractions, MadNLPGPU
DEVICE == :cuda || @eval import CUDA   # for the type in sets.jl, without initializing a device

include(joinpath(@__DIR__, "sets.jl"))
include(joinpath(@__DIR__, "configs.jl"))
using MadIPMBenchmark

# Every solve is sequential: the workers fill the machine.
MadIPMBenchmark.LinearAlgebra.BLAS.set_num_threads(1)

# set => (case => build), filled on first use
const CASES = Dict{String, Dict{String, Function}}()

# Solve one case of a set with the named configurations on this process, telling `events` (a
# channel on the coordinating process) how far it has got. Workers that share a GPU also share
# `token`: only its holder runs a timed solve, while the others build and compile.
function solve_here(set, case, config_names, options, warmup, events, token)
    guard = function (solve)
        put!(events, :waiting)
        token === nothing || take!(token)
        put!(events, :solve)
        try
            return solve()
        finally
            token === nothing || put!(token, 1)
            put!(events, :released)
        end
    end
    builds = get!(() -> Dict(SETS[set]()), CASES, set)
    chosen = [c for c in configs(DEVICE) if first(c) in config_names]
    logs = mkpath(joinpath(LOG_DIR, set))
    solve_case(
        case, builds[case], chosen; options, warmup, report = event -> put!(events, event), guard,
        log = config -> joinpath(logs, "$(case)__$config.txt"),
        backend = DEVICE == :cuda ? :cuda : nothing,
        reclaim = DEVICE == :cuda ? CUDA.reclaim : (() -> nothing),
    )
    put!(events, :done)
    return nothing
end

worker_threads() = Dict{String, Any}(
    "julia_threads" => Threads.nthreads(), "blas_threads" => MadIPMBenchmark.LinearAlgebra.BLAS.get_num_threads(),
    "highs_version" => unsafe_string(HiGHS.Highs_version()),
    "hsl_version" => HSL.LIBHSL_isfunctional() ? string(pkgversion(HSL.HSL_jll)) : "none",
)

# Compile the solve path of this process on tiny problems, so that the first real instance a new
# worker gets is not solved twice for it.
function warm_up(config_names, options)
    chosen = [c for c in configs(DEVICE) if first(c) in config_names]
    for (name, build) in SETS["smoke"]()[1:2]
        solve_case("warm-up", build, chosen; backend = DEVICE == :cuda ? :cuda : nothing, options, warmup = false, log = config -> "/dev/null")
    end
    return nothing
end
