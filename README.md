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

With [`madbench`](https://benchmark.madsuite.org/queue/help), the site's command line tool
(`curl -fsSL https://benchmark.madsuite.org/queue/install.sh | sh`), and a GitHub token of a member of
madsuite-org (`gh auth login`):

    madbench new madipm main --devices=cpu --note="baseline"     # a job; prints its number
    madbench up JOB                                         # a node of it on this machine (-d: in the background)
    madbench up JOB --slurm=4 --sbatch="--partition=... --time=06:00:00"   # or as Slurm batch jobs
    madbench status JOB
    madbench report madipm "title" JOB JOB

`new` also takes a pull request number, a branch, a commit, or `--local=PATH`; `--sets` and
`--instances` narrow the job. A node clones this harness, sets up that commit and runs the instances
the website hands out (`runner/publish.sh run`, which madbench runs); nodes can be added or stopped
at any time.

## Running locally

    julia setup.jl /path/to/MadIPM.jl [--hsl=PATH]
    julia --project=. run.jl smoke --config=default,highs
    julia --project=. run.jl netlib,mm,miplib --device=cuda
