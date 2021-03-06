include("ex4Temporal.jl")

method = :subgradient
δ = 0.9
maxiter = 300000
timelimit = 1000


result, df = lagrangesolve(deepcopy(g),max_iterations=maxiter,update_method=method,δ=δ ,timelimit=timelimit,solveheuristic=cheat20, λinit=:relaxation, ϵ=0)
iters = result[:Iterations]
df[:Example] = ["Example4 Temporal" for i in 1:iters]
df[:Method] = [method for i in 1:iters]
df[:δ] = [δ for i in 1:iters]

result[:Example] = "Example4 Product Temporal"
result[:Method] = method
result[:δ] = δ

writetable("res6lp_ex4Temporal.csv",df)
