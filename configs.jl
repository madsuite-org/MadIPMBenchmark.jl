# The solver configurations. `configs(device)` returns `name => options`: the keyword arguments of
# `madipm(model; options...)`, or a `solver` that solves the model in its place (HiGHS). Included by
# session.jl after the solver packages are loaded.

# HiGHS as a reference on the host: its interior point method on an LP, without crossover, and its
# QP solver on a QP (HiGHS has no interior point method for QPs). It reads the instance's MPS file
# itself. Returns the fields of MadNLP's statistics that a result row reads, so that it goes
# through the same loop; HiGHS reports no time breakdown and no evaluation counts.
const HIGHS_STATUS = Dict(
    HiGHS.kHighsModelStatusOptimal => MadNLP.SOLVE_SUCCEEDED, HiGHS.kHighsModelStatusInfeasible => MadNLP.INFEASIBLE_PROBLEM_DETECTED,
    HiGHS.kHighsModelStatusUnbounded => MadNLP.DIVERGING_ITERATES, HiGHS.kHighsModelStatusUnboundedOrInfeasible => MadNLP.INFEASIBLE_PROBLEM_DETECTED,
    HiGHS.kHighsModelStatusTimeLimit => MadNLP.MAXIMUM_WALLTIME_EXCEEDED, HiGHS.kHighsModelStatusIterationLimit => MadNLP.MAXIMUM_ITERATIONS_EXCEEDED,
)

function run_highs(m; tol, max_wall_time, output_file = "", _...)
    h = HiGHS.Highs_create()
    try
        HiGHS.Highs_setBoolOptionValue(h, "output_flag", !isempty(output_file))
        isempty(output_file) || HiGHS.Highs_setStringOptionValue(h, "log_file", output_file)
        HiGHS.Highs_setStringOptionValue(h, "solver", "ipm")
        HiGHS.Highs_setStringOptionValue(h, "run_crossover", "off")
        HiGHS.Highs_setStringOptionValue(h, "presolve", "on")
        HiGHS.Highs_setDoubleOptionValue(h, "time_limit", max_wall_time)
        for o in ("ipm_optimality_tolerance", "primal_feasibility_tolerance", "dual_feasibility_tolerance")
            HiGHS.Highs_setDoubleOptionValue(h, o, tol)
        end
        HiGHS.Highs_setIntOptionValue(h, "threads", 1)
        # HiGHS takes the format from the extension: Netlib's and Maros-Meszaros's are .SIF, MPS inside
        file = CURRENT_FILE[]
        if !occursin(r"\.mps(\.gz)?$", file)
            file = joinpath(mkpath(joinpath(tempdir(), "highs-$(getpid())")), replace(basename(file), r"\.[A-Za-z]+$" => ".mps"))
            isfile(file) || symlink(CURRENT_FILE[], file)
        end
        HiGHS.Highs_readModel(h, file) == HiGHS.kHighsStatusError && error("HiGHS could not read $(CURRENT_FILE[])")
        # a QP has no interior point method in HiGHS: its QP solver
        HiGHS.Highs_getHessianNumNz(h) > 0 && HiGHS.Highs_setStringOptionValue(h, "solver", "choose")
        t = time()
        HiGHS.Highs_run(h)
        elapsed = time() - t
        status = get(HIGHS_STATUS, HiGHS.Highs_getModelStatus(h), MadNLP.ERROR_IN_STEP_COMPUTATION)
        iters = Ref{Cint}(0)
        HiGHS.Highs_getIntInfoValue(h, "ipm_iteration_count", iters)
        if iters[] == 0
            HiGHS.Highs_getIntInfoValue(h, "qp_iteration_count", iters)
        end
        obj, pinf, dinf = Ref(NaN), Ref(NaN), Ref(NaN)
        HiGHS.Highs_getDoubleInfoValue(h, "objective_function_value", obj)
        HiGHS.Highs_getDoubleInfoValue(h, "max_primal_infeasibility", pinf)
        HiGHS.Highs_getDoubleInfoValue(h, "max_dual_infeasibility", dinf)
        n = NLPModels.get_nvar(m)
        x = zeros(n)
        HiGHS.Highs_getSolution(h, x, C_NULL, C_NULL, C_NULL)
        counters = (;
            factorization_cnt = 0, backsolve_cnt = 0, ir = 0, obj_cnt = 0, obj_grad_cnt = 0, con_cnt = 0, con_jac_cnt = 0,
            lag_hess_cnt = 0, total_time = elapsed, linear_solver_time = NaN, eval_function_time = NaN, init_time = NaN,
        )
        return (; status, iter = Int(iters[]), objective = obj[], primal_feas = pinf[], dual_feas = dinf[], solution = x, counters)
    finally
        HiGHS.Highs_destroy(h)
    end
end

function configs(device::Symbol; hsl::Bool = HSL.LIBHSL_isfunctional())
    c = Pair{String, NamedTuple}[]
    if device == :cpu
        # MadIPM's defaults on the host, with MA27 where a licensed HSL_jll is installed
        push!(c, "default" => (hsl ? (; linear_solver = MadNLPHSL.Ma27Solver) : (;)))
        push!(c, "highs" => (; solver = run_highs))
    elseif device == :cuda
        # MadIPM's defaults on a CUDA device, with cuDSS
        push!(c, "default" => (; linear_solver = MadNLPGPU.CUDSSSolver))
    end
    return c
end

# no option set given on the command line: the configurations are these
custom_name(options) = error("--options is not supported by this benchmark")
validate(configs) = nothing
