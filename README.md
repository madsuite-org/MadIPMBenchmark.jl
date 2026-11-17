# MadIPMBenchmark.jl

Benchmarks of [MadIPM.jl](https://github.com/madsuite-org/MadIPM.jl), the interior point solver for
linear and quadratic programs, on the host and on CUDA GPUs, with HiGHS's interior point method as a
reference on the host. Results are shown at https://benchmark.madsuite.org/madipm/.

## Sets

| set | instances |
|---|---|
| `netlib` | the LPs of Netlib (114, QPSReader.jl's copy) |
| `mm` | the convex QPs of Maros and Mészáros (138, QPSReader.jl's copy) |
| `miplib` | the LP relaxations of the 43 MIPLIB instances of the IJOC paper's benchmark (`sets/miplib.txt`, MIPLIB.jl) |
| `smoke` | four small Netlib LPs, for a functional check and for CI |

Every instance is read from its MPS file into MadIPM's `QuadraticModel` (`sets.jl`).

## Configurations

| name | device | |
|---|---|---|
| `default` | host | MadIPM's defaults; MA27 where a licensed HSL_jll is installed (`--hsl`) |
| `highs` | host | HiGHS: its interior point method on an LP, without crossover; its QP solver on a QP (HiGHS has no interior point method for QPs); one thread |
| `default` | CUDA | MadIPM's defaults with cuDSS |

`configs.jl` defines them. Every solve has the tolerance `--tol` (1e-8) and a wall limit of 600 s.

## Protocol

As MadNLPBenchmark.jl's, whose harness this is: one row per instance and configuration in
`<set>_<config>.csv`, with MadNLP's status codes (which MadIPM returns), iterations, the objective, the
time of the solve, and a solve repeated while Julia compiled during it. `-100` marks an instance
whose worker was killed at the wall limit, `-101` one whose model could not be built or whose solve
threw.

## Running a benchmark

The website coordinates the machines and builds the report; every machine is one you bring. With a
GitHub token of a member of madsuite-org (`gh auth token`):

    runner/publish.sh new main --note="baseline" --devices=cpu
    runner/publish.sh run --job-file=./benchmark-job-<N>      # on each machine

`new` also takes a pull request number, a branch, a commit, or `--local=PATH`; `--sets` and
`--instances` narrow the job. The top of `runner/publish.sh` documents every option.

## Running locally

    julia setup.jl /path/to/MadIPM.jl [--hsl=PATH]
    julia --project=. run.jl smoke --config=default,highs
    julia --project=. run.jl netlib,mm,miplib --device=cuda
