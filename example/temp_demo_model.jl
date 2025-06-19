## Temporary demo script to show how to use the model modifications

using DynamicPolynomials
using TSSOS

# set up (from hpop.jl)
@polyvar x[1:4]
f = x[3]^2*(x[1]^2 + x[1]^4*x[2]^2 + x[3]^4 - 3x[1]^2*x[2]^2) + x[2]^8 + x[1]^2*x[2]^2*x[4]^2

# Option 1: same as before, just returns `model` as well
opt1,sol1,gap1,model1,data1 = cs_tssos_first([f], x, 5, TS="block", solution=true, QUIET=false)

# Option 2: use TSSOS to generate SDP, then solve and extract solution separately
using JuMP
using MosekTools
# using Clarabel

# need MomentOne to extract solution later
_,_,data,_,model = cs_tssos_first([f], x, 5, TS="block", solve=false, solution=false, MomentOne=true, QUIET=false)
set_optimizer(model, Clarabel.Optimizer) # Mosek.Optimizer also works
# could add more constraints here

optimize!(model)

# SDP solution
SDP_status = termination_status(model)
opt = objective_value(model)

# extract original solution
measure = -dual(model[:con])
momone = get_moment(measure, data.tsupp, data.cliques, data.cql, data.cliquesize, nb=data.nb)
sol,gap,data.flag = TSSOS.approx_sol(momone, opt, data.n, data.cliques, data.cql, data.cliquesize, data.supp, data.coe, numeq=data.numeq, gtol=data.gtol, ftol=data.ftol, QUIET=false)
if data.flag == 1
    sol = gap > 0.5 ? randn(data.n) : sol
    sol,data.flag = TSSOS.refine_sol(opt, sol, data, QUIET=false, gtol=data.gtol)
end

# Option 3 (not implemented): use JuMP to generate polynomial problem, refactor with TSSOS then solve


# to print SDP: dualize first
# if encounter issues see https://github.com/jump-dev/Dualization.jl/issues/173
using Dualization

dual_model = dualize(model)
# print(dual_model)