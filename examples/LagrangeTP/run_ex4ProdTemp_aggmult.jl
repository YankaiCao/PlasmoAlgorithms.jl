include("ex4ProdTemp_aggmult.jl")

method = :subgradient
δ = 0.9
maxiter = 50

result, df = lagrangesolve(deepcopy(g),max_iterations=maxiter,update_method=method,δ=δ)
iters = result[:Iterations]
df[:Example] = ["Example4 ProdTemp" for i in 1:iters]
df[:Method] = [method for i in 1:iters]
df[:δ] = [δ for i in 1:iters]

result[:Example] = "Example4 ProdTemp AggrMult"
result[:Method] = method
result[:δ] = δ

result
