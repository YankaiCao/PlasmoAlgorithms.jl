using Plasmo
using PlasmoAlgorithms
using Logging
using Gurobi
using JuMP
using DataFrames

Logging.configure(level=DEBUG)

g = PlasmoGraph()
g.solver = GurobiSolver(OutputFlag=0)

include("modelgen4.jl")
psize=6
otime=1:psize
oproducts=1:psize

node = []

for t in otime
    n = add_node(g)
    m = spmodel(oproducts,t)
    setmodel(n,m)
    push!(node,n)
end



#Without Aggregation
#@linkconstraint(g, [s in sites, i in oproducts, t in 1:otime[end-1]], node[t][:vf][s,i,t]  == node[t+1][:vi][s,i,t+1])
#=
#Aggregation of multipliers - sites
for t in otime
    m = getmodel(node[t])
    vi = getindex(m,:vi)
    vf = getindex(m,:vf)
    @variable(m, svi[i in oproducts, t in otime] >= 0)
    @variable(m, svf[i in oproducts, t in otime] >= 0)
    @constraint(m, agg1[i in oproducts], svi[i,t] == sum(vi[s,i,t] for s in sites))
    @constraint(m, agg2[i in oproducts], svf[i,t] == sum(vf[s,i,t] for s in sites))
end
@linkconstraint(g, [i in oproducts, t in 1:otime[end-1]], node[t][:svf][i,t]  == node[t+1][:svi][i,t+1])


#Aggregation of multipliers - Product
for t in otime
    m = getmodel(node[t])
    vi = getindex(m,:vi)
    vf = getindex(m,:vf)
    @variable(m, svi[s in sites, t in otime] >= 0)
    @variable(m, svf[s in sites, t in otime] >= 0)
    @constraint(m, agg1[s in sites], svi[s,t] == sum(vi[s,i,t] for i in oproducts))
    @constraint(m, agg2[s in sites], svf[s,t] == sum(vf[s,i,t] for i in oproducts))
end
@linkconstraint(g, [s in sites, t in 1:otime[end-1]], node[t][:svf][s,t] == node[t+1][:svi][s,t+1])
=#

#Aggregation of multipliers - sites & product
for t in otime
    m = getmodel(node[t])
    vi = getindex(m,:vi)
    vf = getindex(m,:vf)
    @variable(m, svi[t in otime] >= 0)
    @variable(m, svf[t in otime] >= 0)
    @constraint(m, agg1, svi[t] == sum(vi[s,i,t] for i in oproducts for s in sites))
    @constraint(m, agg2, svf[t] == sum(vf[s,i,t] for i in oproducts for s in sites))
end
@linkconstraint(g, [t in 1:otime[end-1]], node[t][:svf][t] == node[t+1][:svi][t+1])
#=
=#

function heur(mf)
  return 72669.0622
end
