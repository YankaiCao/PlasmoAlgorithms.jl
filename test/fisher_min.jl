using JuMP
using CPLEX
using Plasmo

## Model on x
# Min 16x[1] + 10x[2]
# s.t. x[1] + x[2] <= 1OutputFlag=0
#      x ∈ {0,1}
m1 = Model(solver=CplexSolver())
@variable(m1, xm[i in 1:2],Bin)
@constraint(m1, xm[1] + xm[2] <= 1)
@objective(m1, Min, -16xm[1] - 10xm[2])

## Model on y`
# Max  4y[2]
# s.t. y[1] + y[2] <= 1
#      8x[1] + 2x[2] + y[2] + 4y[2] <= 10
#      x, y ∈ {0,1}

m2 = Model(solver=CplexSolver(CPX_PARAM_PREIND=0,CPX_PARAM_HEURFREQ=-1))
@variable(m2, xs[i in 1:2],Bin)
@variable(m2, y[i in 1:2], Bin)
@constraint(m2, y[1] + y[2] <= 1)
@constraint(m2, 8xs[1] + 2xs[2] + y[1] + 4y[2] <= 10)
@objective(m2, Min, -4y[2])

## Plasmo Graph
g = PlasmoGraph()
g.solver = CplexSolver()
n1 = add_node(g)
setmodel(n1,m1)
n2 = add_node(g)
setmodel(n2,m2)
add_edge(g, n1,n2)
## Linking
# m1[x] = m2[x]  ∀i ∈ {1,2}
@linkconstraint(g, [i in 1:2], n1[:xm][i] == n2[:xs][i])
