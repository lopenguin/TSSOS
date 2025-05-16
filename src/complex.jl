mutable struct ccpop_data
    cpop # complex polynomial optimiztion problem
    z # complex variables
    rlorder # relaxation order
    n # number of all variables
    nb # number of binary variables
    m # number of all constraints
    numeq # number of equality constraints
    ipart # include the imaginary part
    ConjugateBasis # include conjugate variables in monomial bases
    normality # normal order
    supp # support data
    coe # coefficient data
    basis # monomial bases
    ebasis # monomial bases for equality constraints
    ksupp # extended support at the k-th step
    cql # number of cliques
    cliquesize # sizes of cliques
    cliques # cliques of variables
    I # index sets of inequality constraints
    J # index sets of equality constraints
    ncc # constraints associated to no clique
    blocksize # sizes of blocks
    blocks # block structure
    eblocks # block structrue for equality constraints
    GramMat # Gram matrices
    multiplier # multipliers for equality constraints
    moment # Moment matrix
    solver # SDP solver
    SDP_status
    tol # tolerance to certify global optimality
    flag # 0 if global optimality is certified; 1 otherwise
end

"""
    opt,sol,data = cs_tssos_first(pop, z, n, d; nb=0, numeq=0, CS="MF", cliques=[], TS="block", reducebasis=false, 
    merge=false, md=3, solver="Mosek", QUIET=false, solve=true, solution=false, dualize=false, Gram=false, 
    MomentOne=false, ConjugateBasis=false, normality=!ConjugateBasis, cosmo_setting=cosmo_para(), mosek_setting=mosek_para())

Compute the first TS step of the CS-TSSOS hierarchy for constrained complex polynomial optimization. 
If `ConjugateBasis=true`, then include conjugate variables in monomial bases.
If `merge=true`, perform the PSD block merging. 
If `solve=false`, then do not solve the SDP.
If `Gram=true`, then output the Gram matrix.
If `MomentOne=true`, add an extra first-order moment PSD constraint to the moment relaxation.

# Input arguments
- `pop`: vector of the objective, inequality constraints, and equality constraints
- `z`: CPOP variables and their conjugate
- `n`: number of CPOP variables
- `d`: relaxation order
- `nb`: number of unit-norm variables in `x`
- `numeq`: number of equality constraints
- `CS`: method of chordal extension for correlative sparsity (`"MF"`, `"MD"`, `false`)
- `cliques`: the set of cliques used in correlative sparsity
- `TS`: type of term sparsity (`"block"`, `"MD"`, `"MF"`, `false`)
- `md`: tunable parameter for merging blocks
- `normality`: normal order
- `QUIET`: run in the quiet mode (`true`, `false`)

# Output arguments
- `opt`: optimum
- `sol`: (near) optimal solution (if `solution=true`)
- `data`: other auxiliary data 
"""
function cs_tssos_first(pop::Vector{DP.Polynomial{V, M, T}}, z, n::Int, d; numeq=0, RemSig=false, nb=0, CS="MF", cliques=[], TS="block", 
    merge=false, md=3, solver="Mosek", reducebasis=false, QUIET=false, solve=true, solution=false, dualize=false, MomentOne=false, 
    ConjugateBasis=false, Gram=false, cosmo_setting=cosmo_para(), mosek_setting=mosek_para(), writetofile=false, normality=!ConjugateBasis) where {V, M, T<:Number}
    supp,coe = polys_info(pop, z, n, ctype=T)
    opt,sol,data = cs_tssos_first(supp, coe, n, d, numeq=numeq, RemSig=RemSig, nb=nb, CS=CS, cliques=cliques, TS=TS, merge=merge, 
    md=md, solver=solver, reducebasis=reducebasis, QUIET=QUIET, solve=solve, dualize=dualize, solution=solution,
    MomentOne=MomentOne, ConjugateBasis=ConjugateBasis, Gram=Gram, cosmo_setting=cosmo_setting, mosek_setting=mosek_setting, 
    writetofile=writetofile, normality=normality, cpop=pop, z=z)
    return opt,sol,data
end

"""
    opt,sol,data = cs_tssos_first(supp::Vector{Vector{Vector{Vector{UInt16}}}}, coe::Vector{Vector{T}}, n, d; 
    nb=0, numeq=0, CS="MF", cliques=[], TS="block", merge=false, md=3, solver="Mosek", solution=false, dualize=false,
    QUIET=false, solve=true, Gram=false, MomentOne=false, normality=!ConjugateBasis, cosmo_setting=cosmo_para(), mosek_setting=mosek_para()) where {T<:Number}

Compute the first TS step of the CS-TSSOS hierarchy for constrained complex polynomial optimization. 
Here the complex polynomial optimization problem is defined by `supp` and `coe`, corresponding to the supports and coeffients of `pop` respectively.
"""
function cs_tssos_first(supp::Vector{Vector{Vector{Vector{UInt16}}}}, coe::Vector{Vector{T}}, n::Int, d; numeq=0, RemSig=false, nb=0, CS="MF", cliques=[], 
    TS="block", merge=false, md=3, solver="Mosek", reducebasis=false, QUIET=false, solve=true, solution=false, dualize=false, MomentOne=false, ConjugateBasis=false, 
    Gram=false, cosmo_setting=cosmo_para(), mosek_setting=mosek_para(), writetofile=false, normality=!ConjugateBasis, cpop=nothing, z=nothing) where {T<:Number}
    println("*********************************** TSSOS ***********************************")
    println("TSSOS is launching...")
    ipart = T <: Real ? false : true
    if nb > 0
        supp[1],coe[1] = resort(supp[1], coe[1], nb=nb)
    end
    supp = copy(supp)
    coe = copy(coe)
    m = length(supp) - 1
    ind = [supp[1][i][1] <= supp[1][i][2] for i=1:length(supp[1])]
    supp[1] = supp[1][ind]
    coe[1] = coe[1][ind]
    dc = zeros(Int, m)
    for i = 1:m
        if ConjugateBasis == false
            dc[i] = maximum([max(length(supp[i+1][j][1]), length(supp[i+1][j][2])) for j = 1:length(supp[i+1])])
        else
            dc[i] = maximum([length(supp[i+1][j][1]) + length(supp[i+1][j][2]) for j = 1:length(supp[i+1])])
        end
    end
    if cliques != []
        cql = length(cliques)
        cliquesize = length.(cliques)
    else
        time = @elapsed begin
        CS = CS == true ? "MF" : CS
        cliques,cql,cliquesize = clique_decomp(n, m, dc, supp, order=d, alg=CS)
        end
        if CS != false && QUIET == false
            mc = maximum(cliquesize)
            println("Obtained the variable cliques in $time seconds.\nThe maximal size of cliques is $mc.")
        end
    end
    I,J,ncc = assign_constraint(m, numeq, supp, cliques, cql)
    if d == "min"
        rlorder = [isempty(I[i]) && isempty(J[i]) ? 1 : maximum(dc[[I[i]; J[i]]]) for i = 1:cql]
    else
        rlorder = d*ones(Int, cql)
    end
    ebasis = Vector{Vector{Vector{Vector{Vector{UInt16}}}}}(undef, cql)
    if ConjugateBasis == false
        if normality == 0
            basis = Vector{Vector{Vector{Vector{UInt16}}}}(undef, cql)
        else
            basis = Vector{Vector{Vector{Union{Vector{UInt16}, Vector{Vector{UInt16}}}}}}(undef, cql)
        end
    else
        basis = Vector{Vector{Vector{Vector{Vector{UInt16}}}}}(undef, cql)
    end
    for i = 1:cql
        ebasis[i] = Vector{Vector{Vector{Vector{UInt16}}}}(undef, length(J[i]))
        if ConjugateBasis == false
            if normality == 0
                basis[i] = Vector{Vector{Vector{UInt16}}}(undef, length(I[i])+1)
                basis[i][1] = get_basis(cliques[i], rlorder[i])
                for s = 1:length(I[i])
                    basis[i][s+1] = get_basis(cliques[i], rlorder[i]-dc[I[i][s]])
                end
            else
                basis[i] = Vector{Vector{Union{Vector{UInt16}, Vector{Vector{UInt16}}}}}(undef, length(I[i])+1+cliquesize[i])
                basis[i][1] = get_basis(cliques[i], rlorder[i])
                for s = 1:cliquesize[i]
                    temp = get_basis(cliques[i], Int(normality))
                    basis[i][s+1] = [[[item, UInt16[]] for item in temp]; [[item, [cliques[i][s]]] for item in temp]]
                    if nb > 0
                        basis[i][s+1] = reduce_unitnorm.(basis[i][s+1], nb=nb)
                        unique!(basis[i][s+1])
                    end
                end
                for s = 1:length(I[i])
                    basis[i][s+1+cliquesize[i]] = get_basis(cliques[i], rlorder[i]-dc[I[i][s]])
                end
            end
            for s = 1:length(J[i])
                temp = get_basis(cliques[i], rlorder[i]-dc[J[i][s]])
                ebasis[i][s] = vec([[item1, item2] for item1 in temp, item2 in temp])
                if nb > 0
                    ebasis[i][s] = reduce_unitnorm.(ebasis[i][s], nb=nb)
                    unique!(ebasis[i][s])
                end
                sort!(ebasis[i][s])
            end
        else
            if normality < d
                basis[i] = Vector{Vector{Vector{Vector{UInt16}}}}(undef, length(I[i])+1)
                basis[i][1] = get_conjugate_basis(cliques[i], rlorder[i], nb=nb)
                for s = 1:length(I[i])
                    basis[i][s+1] = get_conjugate_basis(cliques[i], rlorder[i]-Int(ceil(dc[I[i][s]]/2)), nb=nb)
                end
            else
                basis[i] = Vector{Vector{Vector{Vector{UInt16}}}}(undef, length(I[i])+1+cliquesize[i])
                basis[i][1] = get_conjugate_basis(cliques[i], rlorder[i], nb=nb)
                for s = 1:cliquesize[i]
                    temp = get_basis(cliques[i], normality)
                    basis[i][s+1] = [[[item, UInt16[]] for item in temp]; [[item, [cliques[i][s]]] for item in temp]]
                    if nb > 0
                        basis[i][s+1] = reduce_unitnorm.(basis[i][s+1], nb=nb)
                        unique!(basis[i][s+1])
                    end
                end
                for s = 1:length(I[i])
                    basis[i][s+1+cliquesize[i]] = get_conjugate_basis(cliques[i], rlorder[i]-Int(ceil(dc[I[i][s]]/2)), nb=nb)
                end
            end
            for s = 1:length(J[i])
                ebasis[i][s] = get_conjugate_basis(cliques[i], 2*rlorder[i]-dc[J[i][s]], nb=nb)
            end
        end
    end
    tsupp = copy(supp[1])
    for i = 2:m+1, j = 1:length(supp[i])
        if supp[i][j][1] <= supp[i][j][2]
            push!(tsupp, supp[i][j])
        end
    end
    sort!(tsupp)
    unique!(tsupp)
    if TS != false && QUIET == false
        println("Starting to compute the block structure...")
    end
    time = @elapsed begin
    blocks,eblocks,cl,blocksize = get_blocks(rlorder, I, J, supp, cliques, cliquesize, cql, tsupp, basis, ebasis, TS=TS, ConjugateBasis=ConjugateBasis, normality=normality, merge=merge, md=md, nb=nb)
    if RemSig == true
        for i = 1:cql
            basis[i][1] = basis[i][1][union(blocks[i][1][blocksize[i][1] .> 1]...)]
        end
        tsupp = copy(supp[1])
        for i = 2:m+1, j = 1:length(supp[i])
            if supp[i][j][1] <= supp[i][j][2]
                push!(tsupp, supp[i][j])
            end
        end
        sort!(tsupp)
        unique!(tsupp)
        blocks,eblocks,cl,blocksize = get_blocks(rlorder, I, J, supp, cliques, cliquesize, cql, tsupp, basis, ebasis, TS=TS, ConjugateBasis=ConjugateBasis, normality=normality, merge=merge, md=md, nb=nb)
    end
    if reducebasis == true
        tsupp = get_gsupp(rlorder, basis, ebasis, supp, cql, I, J, ncc, blocks, eblocks, cl, blocksize, cliquesize, norm=true, nb=nb, ConjugateBasis=ConjugateBasis, normality=normality)
        for i = 1:length(supp[1])
            if supp[1][i][1] == supp[1][i][2]
                push!(tsupp, supp[1][i][1])
            end
        end
        sort!(tsupp)
        unique!(tsupp)
        ltsupp = length(tsupp)
        flag = 0
        for i = 1:cql
            ind = [bfind(tsupp, ltsupp, basis[1][i][j]) !== nothing for j=1:length(basis[1][i])]
            if !all(ind)
                basis[1][i] = basis[1][i][ind]
                flag = 1
            end
        end
        if flag == 1
            tsupp = copy(supp[1])
            for i = 2:m+1, j = 1:length(supp[i])
                if supp[i][j][1] <= supp[i][j][2]
                    push!(tsupp, supp[i][j])
                end
            end
            sort!(tsupp)
            unique!(tsupp)
            blocks,eblocks,cl,blocksize = get_blocks(rlorder, I, J, supp, cliques, cliquesize, cql, tsupp, basis, ebasis, TS=TS, nb=nb, ConjugateBasis=ConjugateBasis, normality=normality, merge=merge, md=md)
        end
    end
    end
    if QUIET == false
        mb = maximum(maximum.([maximum.(blocksize[i]) for i = 1:cql]))
        println("Obtained the block structure in $time seconds.\nThe maximal size of blocks is $mb.")
    end
    opt,ksupp,moment,GramMat,multiplier,SDP_status = solvesdp(m, rlorder, supp, coe, basis, ebasis, cliques, cql, cliquesize, I, J, ncc, blocks, eblocks, cl, blocksize,
    numeq=numeq, QUIET=QUIET, TS=TS, ConjugateBasis=ConjugateBasis, solver=solver, solve=solve, MomentOne=MomentOne, ipart=ipart,
    Gram=Gram, nb=nb, cosmo_setting=cosmo_setting, mosek_setting=mosek_setting, dualize=dualize, writetofile=writetofile, normality=normality)
    sol = nothing
    flag = 1
    if solution == true
        pop,x = complex_to_real(cpop, z)
        _,rsupp,rcoe = polys_info(pop, x)
        ub,sol,status = local_solution(2n, m, rsupp, rcoe, numeq=numeq, startpoint=rand(2n), QUIET=true)
        sol = sol[1:n] + sol[n+1:2n]*im
        if status == MOI.LOCALLY_SOLVED
            gap = abs(opt-ub)/max(1, abs(ub))
            if gap < 1e-2
                flag = 0
                println("------------------------------------------------")
                @printf "Global optimality certified with relative optimality gap %.6f%%!\n" 100*gap
                println("Successfully extracted one globally optimal solution.")
                println("------------------------------------------------")
            else
                @printf "Found a locally optimal solution by Ipopt, giving an upper bound: %.8f.\nThe relative optimality gap is: %.6f%%.\n" ub 100*gap
            end
        end
    end
    data = ccpop_data(cpop, z, rlorder, n, nb, m, numeq, ipart, ConjugateBasis, normality, supp, coe, basis, ebasis, ksupp, cql, cliquesize, cliques, I, J, ncc, blocksize, blocks, eblocks, 
    GramMat, multiplier, moment, solver, SDP_status, 1e-2, flag)
    return opt,sol,data
end

"""
    opt,sol,data = cs_tssos_higher!(data; TS="block", merge=false, md=3, QUIET=false, solve=true, dualize=false,
    solution=false, Gram=false, MomentOne=false, cosmo_setting=cosmo_para(), mosek_setting=mosek_para())

Compute higher TS steps of the CS-TSSOS hierarchy.
"""
function cs_tssos_higher!(data::ccpop_data; TS="block", merge=false, md=3, QUIET=false, solve=true, solution=false, Gram=false, dualize=false, 
    MomentOne=false, cosmo_setting=cosmo_para(), mosek_setting=mosek_para(), writetofile=false)
    n = data.n
    nb = data.nb
    m = data.m
    numeq = data.numeq
    normality = data.normality
    supp = data.supp
    basis = data.basis
    ebasis = data.ebasis
    cql = data.cql
    cliques = data.cliques
    cliquesize = data.cliquesize
    I = data.I
    J = data.J
    if TS != false && QUIET == false
        println("Starting to compute the block structure...")
    end
    time = @elapsed begin
    blocks,eblocks,cl,blocksize = get_blocks(data.rlorder, I, J, supp, cliques, cliquesize, cql, data.ksupp, basis, ebasis, nb=nb, TS=TS, ConjugateBasis=data.ConjugateBasis, normality=normality, merge=merge, md=md)
    end
    if blocksize == data.blocksize && eblocks == data.eblocks
        println("No higher TS step of the CS-TSSOS hierarchy!")
        opt = sol = nothing
    else
        if TS != false && QUIET == false
            mb = maximum(maximum.([maximum.(blocksize[i]) for i = 1:cql]))
            println("Obtained the block structure in $time seconds.\nThe maximal size of blocks is $mb.")
        end
        opt,ksupp,moment,GramMat,multiplier,SDP_status = solvesdp(m, data.rlorder, supp, data.coe, basis, ebasis, cliques, cql, cliquesize, I, J, data.ncc, blocks, eblocks, cl,
        blocksize, numeq=numeq, nb=nb, QUIET=QUIET, solver=data.solver, solve=solve, dualize=dualize, ipart=data.ipart, MomentOne=MomentOne, 
        Gram=Gram, ConjugateBasis=data.ConjugateBasis, cosmo_setting=cosmo_setting, mosek_setting=mosek_setting, writetofile=writetofile, normality=normality)
        sol = nothing
        if solution == true
            pop,x = complex_to_real(data.cpop, data.z)
            _,rsupp,rcoe = polys_info(pop, x)
            ub,sol,status = local_solution(2n, m, rsupp, rcoe, numeq=numeq, startpoint=rand(2n), QUIET=true)
            sol = sol[1:n] + sol[n+1:2n]*im
            if status == MOI.LOCALLY_SOLVED
                gap = abs(opt-ub)/max(1, abs(ub))
                if gap < data.tol
                    data.flag = 0
                    println("------------------------------------------------")
                    @printf "Global optimality certified with relative optimality gap %.6f%%!\n" 100*gap
                    println("Successfully extracted one globally optimal solution.")
                    println("------------------------------------------------")
                else
                    @printf "Found a locally optimal solution by Ipopt, giving an upper bound: %.8f.\nThe relative optimality gap is: %.6f%%.\n" ub 100*gap
                end
            end
        end
        data.blocks = blocks
        data.eblocks = eblocks
        data.blocksize = blocksize
        data.ksupp = ksupp
        data.GramMat = GramMat
        data.multiplier = multiplier
        data.moment = moment
        data.SDP_status = SDP_status
    end
    return opt,sol,data
end

function reduce_unitnorm(a; nb=0)
    a = [copy(a[1]), copy(a[2])]
    i = 1
    while i <= length(a[1])
        if length(a[2]) == 0
            return a
        end
        if a[1][i] <= nb
            loc = bfind(a[2], length(a[2]), a[1][i])
            if loc !== nothing
                deleteat!(a[1], i)
                deleteat!(a[2], loc)
            else
                i += 1
            end
        else
            return a
        end
    end
    return a
end

function get_gsupp(rlorder, basis, ebasis, supp, cql, I, J, ncc, blocks, eblocks, cl, blocksize, cliquesize; norm=false, nb=0, ConjugateBasis=false, normality=1)
    if norm == true
        gsupp = Vector{UInt16}[]
    else
        gsupp = Vector{Vector{UInt16}}[]
    end
    for i = 1:cql
        if ConjugateBasis == false
            a = normality > 0 ? 1 + cliquesize[i] : 1
        else
            a = normality >= rlorder[i] ? 1 + cliquesize[i] : 1
        end
        for (j, w) in enumerate(I[i]), l = 1:cl[i][j+a], t = 1:blocksize[i][j+a][l], r = t:blocksize[i][j+a][l], item in supp[w+1]
            ind1 = blocks[i][j+a][l][t]
            ind2 = blocks[i][j+a][l][r]
            if ConjugateBasis == false
                @inbounds bi = [sadd(basis[i][j+a][ind1], item[1]), sadd(basis[i][j+a][ind2], item[2])]
            else
                @inbounds bi = [sadd(sadd(basis[i][j+a][ind1][1], item[1]), basis[i][j+a][ind2][2]), sadd(sadd(basis[i][j+a][ind1][2], item[2]), basis[i][j+a][ind2][1])]
            end
            if nb > 0
                bi = reduce_unitnorm(bi, nb=nb)
            end
            if norm == true
                if bi[1] == bi[2]
                    push!(gsupp, bi[1])
                end
            else
                if bi[1] <= bi[2]
                    push!(gsupp, bi)
                else
                    push!(gsupp, bi[2:-1:1])
                end
            end
        end
        for (j, w) in enumerate(J[i]), k in eblocks[i][j], item in supp[w+1]
            @inbounds bi = [sadd(ebasis[i][j][k][1], item[1]), sadd(ebasis[i][j][k][2], item[2])]
            if nb > 0
                bi = reduce_unitnorm(bi, nb=nb)
            end
            if norm == true
                if bi[1] == bi[2]
                    push!(gsupp, bi[1])
                end
            else
                if bi[1] <= bi[2]
                    push!(gsupp, bi)
                else
                    push!(gsupp, bi[2:-1:1])
                end
            end
        end
    end
    for i ∈ ncc, j = 1:length(supp[i+1])
        if norm == true
            if supp[i+1][j][1] == supp[i+1][j][2]
                push!(gsupp, supp[i+1][j][1])
            end
        else
            if supp[i+1][j][1] <= supp[i+1][j][2]
                push!(gsupp, supp[i+1][j])
            end
        end
    end
    return gsupp
end

function solvesdp(m, rlorder, supp::Vector{Vector{Vector{Vector{UInt16}}}}, coe, basis, ebasis, cliques, cql, cliquesize, I, J, ncc, blocks, eblocks, cl, blocksize; 
    numeq=0, nb=0, QUIET=false, TS="block", ConjugateBasis=false, solver="Mosek", solve=true, dualize=false, Gram=false, MomentOne=false, ipart=true, 
    cosmo_setting=cosmo_para(), mosek_setting=mosek_para(), writetofile=false, normality=1)
    tsupp = Vector{Vector{UInt16}}[]
    for i = 1:cql
        if ConjugateBasis == false
            a = normality > 0 ? 1 + cliquesize[i] : 1
        else
            a = normality >= rlorder[i] ? 1 + cliquesize[i] : 1
        end
        for s = 1:a, j = 1:cl[i][s], k = 1:blocksize[i][s][j], r = k:blocksize[i][s][j]
            if ConjugateBasis == false && s == 1
                @inbounds bi = [basis[i][s][blocks[i][s][j][k]], basis[i][s][blocks[i][s][j][r]]]
            else
                @inbounds bi = [sadd(basis[i][s][blocks[i][s][j][k]][1], basis[i][s][blocks[i][s][j][r]][2]), sadd(basis[i][s][blocks[i][s][j][k]][2], basis[i][s][blocks[i][s][j][r]][1])]
            end
            if nb > 0
                bi = reduce_unitnorm(bi, nb=nb)
            end
            if bi[1] <= bi[2]
                push!(tsupp, bi)
            else
                push!(tsupp, bi[2:-1:1])
            end
        end
    end
    if TS != false
        gsupp = get_gsupp(rlorder, basis, ebasis, supp, cql, I, J, ncc, blocks, eblocks, cl, blocksize, cliquesize, ConjugateBasis=ConjugateBasis, nb=nb, normality=normality)
        append!(tsupp, gsupp)
    end
    ksupp = copy(tsupp)
    if MomentOne == true
        for i = 1:cql, j = 1:cliquesize[i]
            push!(tsupp, [UInt16[], UInt16[cliques[i][j]]])
            for k = j+1:cliquesize[i]
                bi = [UInt16[cliques[i][j]], UInt16[cliques[i][k]]]
                if nb > 0
                    bi = reduce_unitnorm(bi, nb=nb)
                end
                push!(tsupp, bi)
            end
        end
    end
    sort!(tsupp)
    unique!(tsupp)
    if MomentOne == true
        sort!(ksupp)
        unique!(ksupp)
    else
        ksupp = tsupp
    end
    objv = moment = GramMat = multiplier = SDP_status= nothing
    if solve == true
        ltsupp = length(tsupp)
        if QUIET == false
            println("Assembling the SDP...")
        end
        if solver == "Mosek"
            if dualize == false
                model = Model(optimizer_with_attributes(Mosek.Optimizer, "MSK_DPAR_INTPNT_CO_TOL_PFEAS" => mosek_setting.tol_pfeas, "MSK_DPAR_INTPNT_CO_TOL_DFEAS" => mosek_setting.tol_dfeas, 
                "MSK_DPAR_INTPNT_CO_TOL_REL_GAP" => mosek_setting.tol_relgap, "MSK_DPAR_OPTIMIZER_MAX_TIME" => mosek_setting.time_limit, "MSK_IPAR_NUM_THREADS" => mosek_setting.num_threads))
            else
                model = Model(dual_optimizer(Mosek.Optimizer))
            end
        elseif solver == "COSMO"
            model = Model(optimizer_with_attributes(COSMO.Optimizer, "eps_abs" => cosmo_setting.eps_abs, "eps_rel" => cosmo_setting.eps_rel, "max_iter" => cosmo_setting.max_iter, "time_limit" => cosmo_setting.time_limit))
        elseif solver == "SDPT3"
            model = Model(optimizer_with_attributes(SDPT3.Optimizer))
        elseif solver == "SDPNAL"
            model = Model(optimizer_with_attributes(SDPNAL.Optimizer))
        else
            @error "The solver is currently not supported!"
            return nothing,nothing,nothing,nothing,nothing,nothing
        end
        set_optimizer_attribute(model, MOI.Silent(), QUIET)
        time = @elapsed begin
        rcons = [AffExpr(0) for i=1:ltsupp]
        if ipart == true
            icons = [AffExpr(0) for i=1:ltsupp]
        end
        pos = Vector{Vector{Vector{Union{VariableRef,Symmetric{VariableRef}}}}}(undef, cql)
        for i = 1:cql
            if MomentOne == true
                bs = cliquesize[i] + 1
                if ipart == true
                    pos0 = @variable(model, [1:2*bs, 1:2*bs], PSD)
                else
                    pos0 = @variable(model, [1:bs, 1:bs], PSD)
                end
                for t = 1:bs, r = t:bs
                    if t == 1 && r == 1
                        bi = [UInt16[], UInt16[]]
                    elseif t == 1 && r > 1
                        bi = [UInt16[], UInt16[cliques[i][r-1]]]
                    else
                        bi = [UInt16[cliques[i][t-1]], UInt16[cliques[i][r-1]]]
                        if nb > 0
                            bi = reduce_unitnorm(bi, nb=nb)
                        end
                    end
                    Locb = bfind(tsupp, ltsupp, bi)
                    if ipart == true
                        @inbounds add_to_expression!(rcons[Locb], pos0[t,r]+pos0[t+bs,r+bs])
                        @inbounds add_to_expression!(icons[Locb], pos0[t,r+bs]-pos0[r,t+bs])
                    else
                        @inbounds add_to_expression!(rcons[Locb], pos0[t,r])
                    end
                end
            end
            if ConjugateBasis == false
                a = normality > 0 ? 1 + cliquesize[i] : 1
            else
                a = normality >= rlorder[i] ? 1 + cliquesize[i] : 1
            end
            pos[i] = Vector{Vector{Union{VariableRef,Symmetric{VariableRef}}}}(undef, a+length(I[i]))
            for j = 1:a
                pos[i][j] = Vector{Union{VariableRef,Symmetric{VariableRef}}}(undef, cl[i][j])
                for l = 1:cl[i][j]
                    @inbounds bs = blocksize[i][j][l]
                    if bs == 1
                        pos[i][j][l] = @variable(model, lower_bound=0)
                        if ConjugateBasis == false && j == 1
                            @inbounds bi = [basis[i][j][blocks[i][j][l][1]], basis[i][j][blocks[i][j][l][1]]]
                        else
                            @inbounds bi = [sadd(basis[i][j][blocks[i][j][l][1]][1], basis[i][j][blocks[i][j][l][1]][2]), sadd(basis[i][j][blocks[i][j][l][1]][1], basis[i][j][blocks[i][j][l][1]][2])]
                        end
                        if nb > 0
                            bi = reduce_unitnorm(bi, nb=nb)
                        end
                        Locb = bfind(tsupp, ltsupp, bi)
                        @inbounds add_to_expression!(rcons[Locb], pos[i][j][l])
                    else
                        if ipart == true
                            pos[i][j][l] = @variable(model, [1:2bs, 1:2bs], PSD)
                        else
                            pos[i][j][l] = @variable(model, [1:bs, 1:bs], PSD)
                        end
                        for t = 1:bs, r = t:bs
                            @inbounds ind1 = blocks[i][j][l][t]
                            @inbounds ind2 = blocks[i][j][l][r]
                            if ConjugateBasis == false && j == 1
                                @inbounds bi = [basis[i][j][ind1], basis[i][j][ind2]]
                            else
                                @inbounds bi = [sadd(basis[i][j][ind1][1], basis[i][j][ind2][2]), sadd(basis[i][j][ind1][2], basis[i][j][ind2][1])]
                            end
                            if nb > 0
                                bi = reduce_unitnorm(bi, nb=nb)
                            end
                            if bi[1] <= bi[2]
                                Locb = bfind(tsupp, ltsupp, bi)
                                if ipart == true && bi[1] != bi[2]
                                    @inbounds add_to_expression!(icons[Locb], pos[i][j][l][t,r+bs]-pos[i][j][l][r,t+bs])
                                end
                            else
                                Locb = bfind(tsupp, ltsupp, bi[2:-1:1])
                                if ipart == true
                                    @inbounds add_to_expression!(icons[Locb], -1, pos[i][j][l][t,r+bs]-pos[i][j][l][r,t+bs])
                                end
                            end
                            if ipart == true
                                if bi[1] == bi[2] && t != r
                                    @inbounds add_to_expression!(rcons[Locb], 2*pos[i][j][l][t,r]+2*pos[i][j][l][t+bs,r+bs])
                                else
                                    @inbounds add_to_expression!(rcons[Locb], pos[i][j][l][t,r]+pos[i][j][l][t+bs,r+bs])
                                end
                            else
                                if bi[1] == bi[2] && t != r
                                    @inbounds add_to_expression!(rcons[Locb], 2*pos[i][j][l][t,r])
                                else
                                    @inbounds add_to_expression!(rcons[Locb], pos[i][j][l][t,r])
                                end
                            end
                        end
                    end
                end
            end
        end
        for i = 1:cql, (j, w) in enumerate(I[i])
            if ConjugateBasis == false
                a = normality > 0 ? 1 + cliquesize[i] : 1
            else
                a = normality >= rlorder[i] ? 1 + cliquesize[i] : 1
            end
            pos[i][j+a] = Vector{Union{VariableRef,Symmetric{VariableRef}}}(undef, cl[i][j+a])
            for l = 1:cl[i][j+a]
                bs = blocksize[i][j+a][l]
                if bs == 1
                    pos[i][j+a][l] = @variable(model, lower_bound=0)
                    ind = blocks[i][j+a][l][1]
                    for s = 1:length(supp[w+1])
                        if ConjugateBasis == false
                            @inbounds bi = [sadd(basis[i][j+a][ind], supp[w+1][s][1]), sadd(basis[i][j+a][ind], supp[w+1][s][2])]
                        else
                            @inbounds bi = [sadd(sadd(basis[i][j+a][ind][1], supp[w+1][s][1]), basis[i][j+a][ind][2]), sadd(sadd(basis[i][j+a][ind][2], supp[w+1][s][2]), basis[i][j+a][ind][1])]
                        end
                        if nb > 0
                            bi = reduce_unitnorm(bi, nb=nb)
                        end
                        if bi[1] <= bi[2]
                            Locb = bfind(tsupp, ltsupp, bi)
                            if ipart == true
                                @inbounds add_to_expression!(icons[Locb], imag(coe[w+1][s]), pos[i][j+a][l])
                            end
                            @inbounds add_to_expression!(rcons[Locb], real(coe[w+1][s]), pos[i][j+a][l])
                        end
                    end
                else
                    if ipart == true
                        pos[i][j+a][l] = @variable(model, [1:2bs, 1:2bs], PSD)
                    else
                        pos[i][j+a][l] = @variable(model, [1:bs, 1:bs], PSD)
                    end
                    for t = 1:bs, r = 1:bs
                        ind1 = blocks[i][j+a][l][t]
                        ind2 = blocks[i][j+a][l][r]
                        for s = 1:length(supp[w+1])
                            if ConjugateBasis == false
                                @inbounds bi = [sadd(basis[i][j+a][ind1], supp[w+1][s][1]), sadd(basis[i][j+a][ind2], supp[w+1][s][2])]
                            else
                                @inbounds bi = [sadd(sadd(basis[i][j+a][ind1][1], supp[w+1][s][1]), basis[i][j+a][ind2][2]), sadd(sadd(basis[i][j+a][ind1][2], supp[w+1][s][2]), basis[i][j+a][ind2][1])]
                            end
                            if nb > 0
                                bi = reduce_unitnorm(bi, nb=nb)
                            end
                            if bi[1] <= bi[2]
                                Locb = bfind(tsupp, ltsupp, bi)
                                if ipart == true
                                    @inbounds add_to_expression!(rcons[Locb], real(coe[w+1][s]), pos[i][j+a][l][t,r]+pos[i][j+a][l][t+bs,r+bs])
                                    @inbounds add_to_expression!(rcons[Locb], -imag(coe[w+1][s]), pos[i][j+a][l][t,r+bs]-pos[i][j+a][l][r,t+bs])
                                    if bi[1] != bi[2]
                                        @inbounds add_to_expression!(icons[Locb], imag(coe[w+1][s]), pos[i][j+a][l][t,r]+pos[i][j+a][l][t+bs,r+bs])
                                        @inbounds add_to_expression!(icons[Locb], real(coe[w+1][s]), pos[i][j+a][l][t,r+bs]-pos[i][j+a][l][r,t+bs])
                                    end
                                else
                                    @inbounds add_to_expression!(rcons[Locb], real(coe[w+1][s]), pos[i][j+a][l][t,r])
                                end
                            end
                        end
                    end
                end
            end
        end
        if numeq > 0
            free = Vector{Vector{Vector{VariableRef}}}(undef, cql)
            for i = 1:cql
                if !isempty(J[i])
                    free[i] = Vector{Vector{VariableRef}}(undef, length(J[i]))
                    for (j, w) in enumerate(J[i])
                        mons = ebasis[i][j][eblocks[i][j]]
                        temp = mons[[item[1] <= item[2] for item in mons]]
                        lb = length(temp)
                        if ipart == true
                            free[i][j] = @variable(model, [1:2*lb])
                        else
                            free[i][j] = @variable(model, [1:lb])
                        end
                        for k in eblocks[i][j], s = 1:length(supp[w+1])
                            @inbounds bi = [sadd(ebasis[i][j][k][1], supp[w+1][s][1]), sadd(ebasis[i][j][k][2], supp[w+1][s][2])]
                            if nb > 0
                                bi = reduce_unitnorm(bi, nb=nb)
                            end
                            if bi[1] <= bi[2]
                                Locb = bfind(tsupp, ltsupp, bi)
                                if ebasis[i][j][k][1] <= ebasis[i][j][k][2]
                                    loc = bfind(temp, lb, ebasis[i][j][k])
                                    tag = 1
                                    if ebasis[i][j][k][1] == ebasis[i][j][k][2]
                                        tag = 0
                                    end
                                else
                                    loc = bfind(temp, lb, ebasis[i][j][k][2:-1:1])
                                    tag = -1
                                end
                                if ipart == true
                                    @inbounds add_to_expression!(rcons[Locb], real(coe[w+1][s])*free[i][j][loc]-tag*imag(coe[w+1][s])*free[i][j][loc+lb])
                                    if bi[1] != bi[2]
                                        @inbounds add_to_expression!(icons[Locb], tag*real(coe[w+1][s])*free[i][j][loc+lb]+imag(coe[w+1][s])*free[i][j][loc])
                                    end
                                else
                                    @inbounds add_to_expression!(rcons[Locb], real(coe[w+1][s]), free[i][j][loc])
                                end
                            end
                        end
                    end
                end
            end
        end
        for i in ncc
            if i <= m - numeq
                pos0 = @variable(model, lower_bound=0)
            else
                pos0 = @variable(model)
            end
            for j = 1:length(supp[i+1])
                if supp[i+1][j][1] <= supp[i+1][j][2]
                    Locb = bfind(tsupp, ltsupp, supp[i+1][j])
                    if ipart == true
                        @inbounds add_to_expression!(icons[Locb], imag(coe[i+1][j]), pos0)
                    end
                    @inbounds add_to_expression!(rcons[Locb], real(coe[i+1][j]), pos0)
                end
            end
        end
        rbc = zeros(ltsupp)
        ncons = ltsupp
        itsupp = nothing
        if ipart == true
            ind = [item[1] != item[2] for item in tsupp]
            itsupp = tsupp[ind]
            icons = icons[ind]
            ibc = zeros(length(itsupp))
            ncons += length(itsupp)
        end
        if QUIET == false
            println("There are $ncons affine constraints.")
        end
        for i = 1:length(supp[1])
            Locb = bfind(tsupp, ltsupp, supp[1][i])
            if Locb === nothing
               @error "The monomial basis is not enough!"
               return nothing,nothing,nothing,nothing,nothing,nothing
            else
               rbc[Locb] = real(coe[1][i])
               if ipart == true && supp[1][i][1] != supp[1][i][2]
                   Locb = bfind(itsupp, length(itsupp), supp[1][i])
                   ibc[Locb] = imag(coe[1][i])
               end
            end
        end
        @variable(model, lower)
        rcons[1] += lower
        @constraint(model, rcon, rcons==rbc)
        if ipart == true
            @constraint(model, icon, icons==ibc)
        end
        @objective(model, Max, lower)
        end
        if QUIET == false
            println("SDP assembling time: $time seconds.")
            println("Solving the SDP...")
        end
        # println(all_constraints(model, include_variable_in_set_constraints=false))
        time = @elapsed begin
        optimize!(model)
        end
        if QUIET == false
            println("SDP solving time: $time seconds.")
        end
        if writetofile != false
            write_to_file(dualize(model), writetofile)
        end
        SDP_status = termination_status(model)
        objv = objective_value(model)
        if SDP_status != MOI.OPTIMAL
           println("termination status: $SDP_status")
           status = primal_status(model)
           println("solution status: $status")
        end
        println("optimum = $objv")
        if Gram == true
            ctype = ipart==true ? ComplexF64 : Float64
            GramMat = Vector{Vector{Vector{Union{Float64,ComplexF64,Matrix{ctype}}}}}(undef, cql)
            for i = 1:cql
                if ConjugateBasis == false
                    a = normality > 0 ? 1 + length(I[i]) + cliquesize[i] : 1 + length(I[i])
                else
                    a = normality >= rlorder[i] ? 1 + length(I[i]) + cliquesize[i] : 1 + length(I[i])
                end
                GramMat[i] = Vector{Vector{Union{ctype,Matrix{ctype}}}}(undef, a)
                for j = 1:a
                    GramMat[i][j] = Vector{Union{ctype,Matrix{ctype}}}(undef, cl[i][j])
                    for l = 1:cl[i][j]
                        if ipart == true && blocksize[i][j][l] > 1
                            bs = blocksize[i][j][l]
                            temp = value.(pos[i][j][l][1:bs,bs+1:2bs])
                            GramMat[i][j][l] = value.(pos[i][j][l][1:bs,1:bs]+pos[i][j][l][bs+1:2bs,bs+1:2bs]) + im*(temp-temp')
                        else
                            GramMat[i][j][l] = value.(pos[i][j][l])
                        end
                    end
                end
            end
            multiplier = Vector{Vector{Vector{Float64}}}(undef, cql)
            for i = 1:cql
                if !isempty(J[i])
                    multiplier[i] = [value.(free[i][j]) for j = 1:length(J[i])]
                end
            end
        end
        rmeasure = -dual(rcon)
        imeasure = nothing
        if ipart == true
            imeasure = -dual(icon)
        end
        moment = get_cmoment(rmeasure, imeasure, tsupp, itsupp, cql, blocks, cl, blocksize, basis, ipart=ipart, nb=nb, ConjugateBasis=ConjugateBasis)
    end
    return objv,ksupp,moment,GramMat,multiplier,SDP_status
end

function get_eblock(tsupp::Vector{Vector{Vector{UInt16}}}, hsupp::Vector{Vector{Vector{UInt16}}}, basis::Vector{Vector{Vector{UInt16}}}; nb=nb)
    ltsupp = length(tsupp)
    eblock = Int[]
    for (i,item) in enumerate(basis)
        flag = 0
        for temp in hsupp
            bi = [sadd(item[1], temp[1]), sadd(item[2], temp[2])]
            if nb > 0
                bi = reduce_unitnorm(bi, nb=nb)
            end
            if (bi[1] <= bi[2] && bfind(tsupp, ltsupp, bi) !== nothing) || (bi[1] > bi[2] && bfind(tsupp, ltsupp, bi[2:-1:1]) !== nothing)
                flag = 1
                break
            end
        end
        if flag == 1
            push!(eblock, i)
        end
    end
    return eblock
end

function get_blocks(m, l, d, tsupp, supp::Vector{Vector{Vector{Vector{UInt16}}}}, basis, ebasis; nb=0, normality=1, nvar=0, TS="block", ConjugateBasis=false, merge=false, md=3)
    if (ConjugateBasis == false && normality > 0) || (ConjugateBasis == true && normality >= d)
        uk = m + 1 + nvar
    else
        uk = m + 1 
    end
    blocks = Vector{Vector{Vector{Int}}}(undef, uk)
    blocksize = Vector{Vector{Int}}(undef, uk)
    cl = Vector{Int}(undef, uk)
    eblocks = Vector{Vector{Int}}(undef, l)
    if TS == false
        for k = 1:uk
            lb = length(basis[k])
            blocks[k],blocksize[k],cl[k] = [Vector(1:lb)],[lb],1
        end
        for k = 1:l
            eblocks[k] = Vector(1:length(ebasis[k]))
        end
    else
        for k = 1:uk
            if k == 1
                G = get_graph(tsupp, basis[1], nb=nb, ConjugateBasis=ConjugateBasis)
            elseif ((ConjugateBasis == false && normality > 0) || (ConjugateBasis == true && normality >= d)) && k <= 1 + nvar
                G = get_graph(tsupp, basis[k], nb=nb, ConjugateBasis=true)
            elseif ((ConjugateBasis == false && normality > 0) || (ConjugateBasis == true && normality >= d)) && k > 1 + nvar
                G = get_graph(tsupp, supp[k-1-nvar], basis[k], nb=nb, ConjugateBasis=ConjugateBasis)
            else
                G = get_graph(tsupp, supp[k-1], basis[k], nb=nb, ConjugateBasis=ConjugateBasis)
            end
            if TS == "block"
                blocks[k] = connected_components(G)
                blocksize[k] = length.(blocks[k])
                cl[k] = length(blocksize[k])
            else
                blocks[k],cl[k],blocksize[k] = chordal_cliques!(G, method=TS)
                if merge == true
                    blocks[k],cl[k],blocksize[k] = clique_merge!(blocks[k], d=md, QUIET=true)
                end
            end
        end
        for k = 1:l
            eblocks[k] = get_eblock(tsupp, supp[k+m], ebasis[k], nb=nb)
        end
    end
    return blocks,eblocks,cl,blocksize
end

function get_blocks(rlorder, I, J, supp::Vector{Vector{Vector{Vector{UInt16}}}}, cliques, cliquesize, cql, tsupp, basis, ebasis; TS="block", ConjugateBasis=false, nb=0, normality=1, merge=false, md=3)
    blocks = Vector{Vector{Vector{Vector{Int}}}}(undef, cql)
    eblocks = Vector{Vector{Vector{Int}}}(undef, cql)
    cl = Vector{Vector{Int}}(undef, cql)
    blocksize = Vector{Vector{Vector{Int}}}(undef, cql)
    for i = 1:cql
        ksupp = TS == false ? nothing : tsupp[[issubset(union(tsupp[j][1], tsupp[j][2]), cliques[i]) for j in eachindex(tsupp)]]
        blocks[i],eblocks[i],cl[i],blocksize[i] = get_blocks(length(I[i]), length(J[i]), rlorder[i], ksupp, supp[[I[i]; J[i]].+1], basis[i], 
        ebasis[i], TS=TS, ConjugateBasis=ConjugateBasis, merge=merge, md=md, nb=nb, normality=normality, nvar=cliquesize[i])
    end
    return blocks,eblocks,cl,blocksize
end

function assign_constraint(m, numeq, supp::Vector{Vector{Vector{Vector{UInt16}}}}, cliques, cql)
    I = [Int[] for i=1:cql]
    J = [Int[] for i=1:cql]
    ncc = Int[]
    for i = 1:m
        ind = findall(k->issubset(unique(reduce(vcat, [item[1] for item in supp[i+1]])), cliques[k]), 1:cql)
        if isempty(ind)
            push!(ncc, i)
        elseif i <= m - numeq
            push!.(I[ind], i)
        else
            push!.(J[ind], i)
        end
    end
    return I,J,ncc
end

function get_graph(tsupp::Vector{Vector{Vector{UInt16}}}, basis; nb=0, ConjugateBasis=false)
    lb = length(basis)
    G = SimpleGraph(lb)
    ltsupp = length(tsupp)
    for i = 1:lb, j = i+1:lb
        if ConjugateBasis == false
            bi = [basis[i], basis[j]]
        else
            bi = [sadd(basis[i][1], basis[j][2]), sadd(basis[i][2], basis[j][1])]
        end
        if nb > 0
            bi = reduce_unitnorm(bi, nb=nb)
        end
        if bi[1] > bi[2]
            bi = bi[2:-1:1]
        end
        if bfind(tsupp, ltsupp, bi) !== nothing
            add_edge!(G, i, j)
        end
    end
    return G
end

function get_graph(tsupp::Vector{Vector{Vector{UInt16}}}, supp, basis; nb=0, ConjugateBasis=false)
    lb = length(basis)
    ltsupp = length(tsupp)
    G = SimpleGraph(lb)
    for i = 1:lb, j = i+1:lb
        r = 1
        while r <= length(supp)
            if ConjugateBasis == false
                bi = [sadd(basis[i], supp[r][1]), sadd(basis[j], supp[r][2])]
            else
                bi = [sadd(sadd(basis[i][1], supp[r][1]), basis[j][2]), sadd(sadd(basis[i][2], supp[r][2]), basis[j][1])]
            end
            if nb > 0
                bi = reduce_unitnorm(bi, nb=nb)
            end
            if bi[1] > bi[2]
                bi = bi[2:-1:1]
            end
            if bfind(tsupp, ltsupp, bi) !== nothing
               break
            else
                r += 1
            end
        end
        if r <= length(supp)
            add_edge!(G, i, j)
        end
    end
    return G
end

function clique_decomp(n, m, dc, supp::Vector{Vector{Vector{Vector{UInt16}}}}; order="min", alg="MF")
    if alg == false
        cliques = [UInt16[i for i=1:n]]
        cql = 1
        cliquesize = [n]
    else
        G = SimpleGraph(n)
        for i = 1:m+1
            if order == "min" || i == 1 || order == dc[i-1]
                for j = 1:length(supp[i])
                    add_clique!(G, unique([supp[i][j][1];supp[i][j][2]]))
                end
            else
                temp = copy(supp[i][1][1])
                for j = 2:length(supp[i])
                    append!(temp, supp[i][j][1])
                end
                add_clique!(G, unique(temp))
            end
        end
        if alg == "NC"
            cliques,cql,cliquesize = max_cliques(G)
        else
            cliques,cql,cliquesize = chordal_cliques!(G, method=alg, minimize=true)
        end
    end
    uc = unique(cliquesize)
    sizes = [sum(cliquesize.== i) for i in uc]
    println("-----------------------------------------------------------------------------")
    println("The clique sizes of varibles:\n$uc\n$sizes")
    println("-----------------------------------------------------------------------------")
    return cliques,cql,cliquesize
end

function get_cmoment(rmeasure, imeasure, tsupp, itsupp, cql, blocks, cl, blocksize, basis; ipart=true, nb=0, ConjugateBasis=false)
    moment = Vector{Vector{Matrix{Union{Float64,ComplexF64}}}}(undef, cql)
    for i = 1:cql
        moment[i] = Vector{Matrix{Union{Float64,ComplexF64}}}(undef, cl[i][1])
        for l = 1:cl[i][1]
            bs = blocksize[i][1][l]
            rtemp = zeros(Float64, bs, bs)
            if ipart == true
                itemp = zeros(Float64, bs, bs)
            end
            for t = 1:bs, r = t:bs
                ind1 = blocks[i][1][l][t]
                ind2 = blocks[i][1][l][r]
                if ConjugateBasis == false
                    bi = [basis[i][1][ind1], basis[i][1][ind2]]
                else
                    bi = [sadd(basis[i][1][ind1][1], basis[i][1][ind2][2]), sadd(basis[i][1][ind1][2], basis[i][1][ind2][1])]
                end
                if nb > 0
                    bi = reduce_unitnorm(bi, nb=nb)
                end
                if ipart == true
                    if bi[1] < bi[2]
                        Locb = bfind(itsupp, length(itsupp), bi)
                        itemp[t,r] = imeasure[Locb]
                    elseif bi[1] > bi[2]
                        Locb = bfind(itsupp, length(itsupp), bi[2:-1:1])
                        itemp[t,r] = -imeasure[Locb]
                    end
                end
                if bi[1] <= bi[2]
                    Locb = bfind(tsupp, length(tsupp), bi)
                else
                    Locb = bfind(tsupp, length(tsupp), bi[2:-1:1])
                end
                rtemp[t,r] = rmeasure[Locb]
            end
            rtemp = (rtemp + rtemp')/2
            if ipart == true
                itemp = (itemp - itemp')/2
                moment[i][l] = rtemp - itemp*im
            else
                moment[i][l] = rtemp
            end
        end
    end
    return moment
end
