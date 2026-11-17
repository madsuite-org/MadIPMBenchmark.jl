# The problem sets. `SETS[name]()` returns the instances of a set as `name => build`, where
# `build(backend)` returns the model on that backend (`nothing` for the host), a MadIPM
# QuadraticModel read from the instance's MPS file. Included by session.jl after the packages are
# loaded.

# The file the last model was built from, for a reference solver that reads it itself (HiGHS).
const CURRENT_FILE = Ref("")

minimize(qps) = qps.objsense != :max

"The QuadraticModel of a problem in an MPS file, as the IJOC paper's benchmark builds it."
function qps_model(file)
    # Netlib and Maros-Meszaros are fixed MPS (BLEND does not read as free MPS); MIPLIB's free
    read(format) = endswith(file, ".gz") ? GZip.open(io -> readqps(io; mpsformat = format), file, "r") : readqps(file; mpsformat = format)
    # without QPSReader's messages about each section it reads
    qps = Base.CoreLogging.with_logger(Base.CoreLogging.NullLogger()) do
        try
            read(:fixed)
        catch
            read(:free)
        end
    end
    nvar, ncon = length(qps.lvar), length(qps.lcon)
    A = SparseMatricesCOO.SparseMatrixCOO(ncon, nvar, qps.arows, qps.acols, qps.avals)
    H = SparseMatricesCOO.SparseMatrixCOO(nvar, nvar, qps.qrows, qps.qcols, qps.qvals)
    data = MadIPM.Models.QPData(A, qps.c, H; lvar = qps.lvar, uvar = qps.uvar, lcon = qps.lcon, ucon = qps.ucon, c0 = qps.c0)
    return MadIPM.Models.QuadraticModel(data; minimize = minimize(qps), name = something(qps.name, basename(file)))
end

function file_case(file)
    name = replace(basename(file), r"\.(SIF|mps|mps\.gz|QPS)$"i => "")
    return name => function (backend)
        CURRENT_FILE[] = file
        m = qps_model(file)
        return backend === nothing ? m : Adapt.adapt(CUDA.CuArray, m)
    end
end

files(dir, pattern) = sort!([joinpath(dir, f) for f in readdir(dir) if occursin(pattern, f)])

const SETS = Dict{String, Function}(
    # the LPs of Netlib (QPSReader's copy)
    "netlib" => () -> file_case.(files(QPSReader.fetch_netlib(), r"\.SIF$")),
    # the convex QPs of Maros and Meszaros (QPSReader's copy)
    "mm" => () -> file_case.(files(QPSReader.fetch_mm(), r"\.SIF$")),
    # the LP relaxations of the MIPLIB instances of the IJOC paper's benchmark (sets/miplib.txt)
    "miplib" => () -> [file_case(joinpath(MIPLIB.miplib2010_path, f)) for f in readlines(joinpath(@__DIR__, "sets", "miplib.txt"))],
    # a few small instances, for a functional check of a configuration and for CI
    "smoke" => () -> file_case.(filter(f -> basename(f) in ("AFIRO.SIF", "ADLITTLE.SIF", "SC50A.SIF", "BLEND.SIF"), files(QPSReader.fetch_netlib(), r"\.SIF$"))),
)

instance_group(set, case) = case
