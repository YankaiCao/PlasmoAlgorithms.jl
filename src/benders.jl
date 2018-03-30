using JuMP
using Gurobi
using Plasmo

function fix(var,value)
  ##Sets value for constraint variable
  setlowerbound(var,value)
  setupperbound(var,value)
end

function isChildNode(g::Plasmo.PlasmoGraph, n1::PlasmoNode, n2::PlasmoNode)
  ##Checks if n1 is a child node of n2
  for node in LightGraphs.out_neighbors(g.graph,getindex(g,n2))
    if (n1 == g.nodes[node]) return true
      return true
    end
  end
  return false
end

function numChildNodes(g::PlasmoGraph, n1::PlasmoNode)
  return length(LightGraphs.out_neighbors(g.graph,getindex(g,n1)))
end

function numParentNodes(g::PlasmoGraph, n1::PlasmoNode)
  return length(LightGraphs.in_neighbors(g.graph,getindex(g,n1)))
end

function levels(graph::Plasmo.PlasmoGraph)
  #Create lists of root and leaf nodes in graph
  graph.attributes[:roots] = []
  graph.attributes[:leaves] = []
  #Create dictionary to keep track of levels of nodes
  graph.attributes[:levels] = Dict()
  #Iterate through every node to check for root/leaf nodes
  for nodeIndex in 1:length(graph.nodes)
    node = graph.nodes[nodeIndex]
    #If the node does not have parents it is a root node
    if numParentNodes(graph,node)==0
      push!(graph.attributes[:roots],node)
      #Root nodes are the first level
    end
    #If the node does not have children it is a leaf node
    if numChildNodes(graph,node)==0
      push!(graph.attributes[:leaves],node)
    end
  end

  #Start mapping level from the root nodes
  currentNodes = graph.attributes[:roots]
  levels = graph.attributes[:levels]
  level = 1
  while currentNodes != []
    levels[level] = currentNodes
    childrenNodes = []
    for node in currentNodes
      childNodeIndex = LightGraphs.out_neighbors(graph.graph,getindex(graph,node))
      for index in childNodeIndex
        childNode = graph.nodes[index]
        push!(childrenNodes,childNode)
      end
    end
    level += 1
    currentNodes = childrenNodes
  end
end

function preProcess(graph::Plasmo.PlasmoGraph)
  if get(graph.attributes,:preprocessed,false)
    return 0
  end

  levels(graph)

  links = getlinkconstraints(graph)
  numLinks = length(links)
  numNodes = length(graph.nodes)

  graph.attributes[:links] = Dict()
  graph.attributes[:childlinks] = Dict()
  graph.attributes[:duals] = Dict()
  dualMap = graph.attributes[:duals]
  linkIndex = graph.attributes[:links]
  childLinkIndex = graph.attributes[:childlinks]

  #Add each node as a key to the dictionary
  for index in 1:length(graph.nodes)
    node = graph.nodes[index]
    nodeModel = getmodel(node)
    nodeModel.ext[:preobj] = nodeModel.obj
    linkIndex[node] = []
    childLinkIndex[node] = []
    #Add valbar to child nodes
    if numParentNodes(graph,node) != 0
      sp = getmodel(node)
      @constraintref dual[1:numLinks]
      @variable(sp, valbar[1:numLinks])
    end
    #Add theta to parent nodes
    if numChildNodes(graph,node) != 0
      mp = getmodel(node)
      @variable(mp,θ[1:numNodes] >= -1e6)
      for node in LightGraphs.out_neighbors(graph.graph,getindex(graph,node))
        childNode = graph.nodes[node]
        childNodeIndex = getindex(graph,childNode)
        θ = getindex(mp,:θ)
        mp.obj += θ[childNodeIndex]
      end
    end
  end

  #Add dual constraint to child nodes using the linking constraints
  for link in 1:numLinks
    #Take the two variables of the constraint
    var1 = links[link].terms.vars[1]
    var2 = links[link].terms.vars[2]
    #Determine which nodes they belong to
    nodeV1 = getnode(var1)
    nodeV2 = getnode(var2)
    #Set the order of the nodes
    if isChildNode(graph,nodeV1,nodeV2)
      childNode = nodeV1
      childvar = var1
      parentNode = nodeV2
    elseif isChildNode(graph,nodeV2,nodeV1)
      childNode = nodeV2
      childvar = var2
      parentNode = nodeV1
    end
    #Add theta[childNode] to the parent node objective
    mp = getmodel(parentNode)
    childNodeIndex = getindex(graph,childNode)
    # θ = getindex(mp,:θ)
    # mp.obj += θ[childNodeIndex]
    #Add linking constraint to the parent node dictionary
    linkList = linkIndex[parentNode]
    childLinkList = childLinkIndex[childNode]
    push!(linkList,link)
    push!(childLinkList,link)
  end
  for child in keys(childLinkIndex)
    sp = getmodel(child)
    childLinkList = childLinkIndex[child]
    @constraintref dual[1:length(childLinkList)]
    for i in 1:length(childLinkList)
      link = childLinkList[i]
      var1 = links[link].terms.vars[1]
      var2 = links[link].terms.vars[2]
      #Determine which nodes they belong to
      nodeV1 = getnode(var1)
      nodeV2 = getnode(var2)
      #Set the order of the nodes
      if isChildNode(graph,nodeV1,nodeV2)
        childNode = nodeV1
        childvar = var1
        parentNode = nodeV2
      elseif isChildNode(graph,nodeV2,nodeV1)
        childNode = nodeV2
        childvar = var2
        parentNode = nodeV1
      end
      valbar = getindex(sp,:valbar)
      dual[i] = @constraint(sp,valbar[link] - childvar == 0)
    end
    dualMap[child] = dual
  end
  graph.attributes[:preprocessed] = true
end

function forwardStep(graph::Plasmo.PlasmoGraph)
  levels = graph.attributes[:levels]
  links = getlinkconstraints(graph)
  linksMap = graph.attributes[:links]
  for level in 1:length(levels)
    currentLevel = levels[level]
    for node in currentLevel
      mp = getmodel(node)
      solve(mp)
      #Get the constraints linked to this node from the dictionary
      nodelinks = linksMap[node]
      #Iterate through linking constraints
      for link in nodelinks
        #Get the nodes and variables in the linked constraint
        var1 = links[link].terms.vars[1]
        var2 = links[link].terms.vars[2]
        nodeV1 = getnode(var1)
        nodeV2 = getnode(var2)
        #Determine which nodes are parents and children
        if isChildNode(graph,nodeV1,nodeV2)
          childNode = nodeV1
          parentNode = nodeV2
          val = getvalue(var2)
        elseif isChildNode(graph,nodeV2,nodeV1)
          childNode = nodeV2
          parentNode = nodeV1
          val = getvalue(var1)
        end
        #Set valbar in child node associated with link to variable value in parent
        sp = getmodel(childNode)
        valbar = getindex(sp, :valbar)
        fix(valbar[link], val)
      end
    end
  end

  leaves = graph.attributes[:leaves]
  roots = graph.attributes[:roots]
  LB = 0
  UB = 0
  for root in roots
    rootmodel = getmodel(root)
    LB = LB + getobjectivevalue(rootmodel)
    # UB += getvalue(rootmodel.ext[:preobj])
  end
  for index in 1:length(graph.nodes)
    node = graph.nodes[index]
    nodeModel = getmodel(node)
    UB += getvalue(nodeModel.ext[:preobj])
  end
  return LB,UB
end

function backwardStep(graph::Plasmo.PlasmoGraph,cut::Symbol)
  levels = graph.attributes[:levels]
  for level in length(keys(levels)):-1:2
    for node in levels[level]
      cutGeneration(graph,node,cut)
    end
  end
end

function bendersolve(graph::Plasmo.PlasmoGraph; max_iterations::Int64=3, cut::Symbol=:LP;)
  preProcess(graph)
  ϵ = 10e-5
  UB = Inf
  LB = -Inf

  for i in 1:max_iterations
    LB,UB = forwardStep(graph)
    debug("***** ITERATION $i ***********")
    debug("*** UB = ",UB)
    debug("*** LB = ",LB)
    if abs(UB - LB)<ϵ
      debug("Converged!")
      break
    end
    backwardStep(graph,cut)
  end
  return getobjectivevalue(getmodel(graph.nodes[1]))
end

function cutGeneration(graph::PlasmoGraph, node::PlasmoNode,cut::Symbol;θlb=0)
  linkList= graph.attributes[:links]
  childLinks = graph.attributes[:childlinks]
  dualMap = graph.attributes[:duals]
  links = getlinkconstraints(graph)

  sp = getmodel(node)
  valbars = []
  variables = []
  λs = []
  for childLink in childLinks[node]
    valbar = getindex(sp,:valbar)
    push!(valbars,valbar[childLink])

    var1 = links[childLink].terms.vars[1]
    var2 = links[childLink].terms.vars[2]
    nodeV1 = getnode(var1)
    nodeV2 = getnode(var2)
    #Determine which nodes are parents and children
    if isChildNode(graph,nodeV1,nodeV2)
      var = var2
    elseif isChildNode(graph,nodeV2,nodeV1)
      var = var1
    end
    push!(variables,var)
    if cut == :NLP
      nlp = sp.ext[:nlp]
      nlp.colVal = sp.colVal
      nlp.colUpper[end] = nlp.colLower[end] = nlp.colVal[end]
      status = solve(nlp)
      dualCon = getindex(nlp,:dualcon)
      println("dcon = $dualCon")
      λs = getdual(dualCon)
      println("lambda = $λs")
      graph.attributes[:λs] = λs
    end
    if cut == :LP
      status = solve(sp, relaxation = true)
      dualCon = dualMap[node]
      λs = getdual(dualCon)
      graph.attributes[:λs] = λs
    end
  end
  graph.attributes[:variables] = variables
  graph.attributes[:valbars] = valbars

  if cut == :NLP
    LPcut(graph,node)
  end
  if cut == :LP
    LPcut(graph,node)
  end
  if cut == :Bin
    binarycut(graph,node,θlb=θlb)
  end
  if cut == :Superset
    supersetcut(graph,node)
  end
  if cut == :Subset
    subsetcut(graph,node)
  end
end

function LPcut(graph::PlasmoGraph, node::PlasmoNode)
  status = :Optimal
  variables = graph.attributes[:variables]
  valbars = graph.attributes[:valbars]
  λs = graph.attributes[:λs]
  parentNodes = LightGraphs.in_neighbors(graph.graph,getindex(graph,node))
  parentNode = graph.nodes[parentNodes[1]]

  mp = getmodel(parentNode)
  θ = getindex(mp,:θ)

  # TODO: There are two solve calls in the function... there should be only one
  rhs = 0
  for i in 1:length(variables)
      rhs = rhs + λs[i]*(getupperbound(valbars[i])-variables[i])
      rhs2 = λs[i]*(getupperbound(valbars[i])-variables[i])
  end
  if status != :Optimal
    @constraint(mp, 0 >= rhs)
    debug("Infeasible Model, adding feasibility cut")
  else
    if haskey(getmodel(node).ext,:nlp)
      θk = getobjectivevalue(getmodel(node).ext[:nlp])
    else
      θk = getobjectivevalue(getmodel(node))
    end
    @constraint(mp, θ[getindex(graph,node)] >= θk + rhs)
    i = getindex(graph,node)
  end
end

function supersetcut(graph::PlasmoGraph, node::PlasmoNode)
  status = graph.attributes[:status]
  variables = graph.attributes[:variables]
  valbars = graph.attributes[:valbars]
  Z1 = []
  Z0 = []
  parentNodes = LightGraphs.in_neighbors(graph.graph,getindex(graph,node))
  parentNode = graph.nodes[parentNodes[1]]

  mp = getmodel(parentNode)
  θ = getindex(mp,:θ)
  rhs = 0

  for i in 1:length(variables)
      value = getvalue(variables[i])
      if value == 1
        push!(Z1,variables[i])
      else
        push!(Z0,variables[i])
      end
  end
  if status != :Optimal
    debug("Infeasible Model")
  else
    debug("ADDED SUPERSET CUT")
    @constraint(mp, [i in 1:length(Z0)], sum(Z1[n] for n in 1:length(Z1)) + Z0[i] <= length(Z1))
    debug(mp.linconstr[end])
  end
end

function subsetcut(graph::PlasmoGraph, node::PlasmoNode)
  status = graph.attributes[:status]
  variables = graph.attributes[:variables]
  valbars = graph.attributes[:valbars]
  Z1 = []
  Z0 = []
  status = solve(sp)
  parentNodes = LightGraphs.in_neighbors(graph.graph,getindex(graph,node))
  parentNode = graph.nodes[parentNodes[1]]

  mp = getmodel(parentNode)
  θ = getindex(mp,:θ)
  rhs = 0

  for i in 1:length(variables)
      value = getvalue(variables[i])
      if value == 1
        push!(Z0,variables[i])
      else
        push!(Z1,variables[i])
      end
  end
  if status != :Optimal
    debug("Infeasible Model")
  else
    @constraint(mp, [i in 1:length(Z1)], sum(Z0[n] for n in 1:length(Z0)) + Z1[i] >= 1)
    debug(mp.linconstr[end])
  end
end

function binarycut(graph::PlasmoGraph, node::PlasmoNode;θlb=0)
  status = graph.attributes[:status]
  variables = graph.attributes[:variables]
  valbars = graph.attributes[:valbars]
  parentNodes = LightGraphs.in_neighbors(graph.graph,getindex(graph,node))
  parentNode = graph.nodes[parentNodes[1]]

  mp = getmodel(parentNode)
  θ = getindex(mp,:θ)
  rhs = 0

  for i in 1:length(variables)
      value = getvalue(variables[i])
      if value == 0
        rhs += variables[i]
      elseif value == 1
        rhs += 1 - variables[i]
      end
  end
  if status != :Optimal
    debug("Infeasible Model")
  else
    θk = getobjectivevalue(getmodel(node))
    @constraint(mp, θ[getindex(graph,node)] >= θk - (θk-θlb)*rhs)
    debug(mp.linconstr[end])
  end
end

function initialCuts(graph::PlasmoGraph, A::Array{JuMP.JuMPDict{Float64,3},1})
  varUpdate = Dict()
  sp = getmodel(getnodes(graph)[2])
  vars = getindex(sp, :w)
  for k in keys(vars)
    var = vars[k...]
    for i in 1:length(A)
      if k in keys(A[i])
        val = A[i][k...]
        varUpdate[var] = val
      end
    end
  end

  links = getlinkconstraints(graph)
  linksMap = graph.attributes[:links]
  nodelinks = linksMap[getnodes(graph)[1]]
  #Iterate through linking constraints
  for link in nodelinks
    #Get the nodes and variables in the linked constraint
    var = links[link].terms.vars[2]
    updateVal = varUpdate[var]
    #Set valbar in child node associated with link to variable value in parent
    valbar = getindex(sp, :valbar)
    fix(valbar[link], updateVal)
  end
end
