mutable struct poly_data
    n::Int
    supp::Vector{Vector{UInt16}}
    coe::Vector{Number}
end

mutable struct poly_matrix
    m::Int
    poly::Vector{poly_data} # store the upper triangular part by colomn
end

mutable struct mpop_data
    b
    obj_matrix
    cons_matrix
    basis # monomial basis
    gbasis # monomial bases for inequality constraints
    ksupp # extended support at the k-th step
    cl # numbers of blocks
    blocksize # sizes of blocks
    blocks # block structure
    cql # number of cliques
    cliquesize # sizes of cliques
    cliques # cliques of variables
    I # index sets of inequality constraints
    ncc # constraints associated to no clique
    moment # Moment matrix
    SDP_status
end

function tssos_first(F::Matrix{Polynomial{true, T}}, G, x, d; TS="block", QUIET=false, solve=true, Mommat=false) where {T<:Number}
    return cs_tssos_first(F, G, x, d, CS=false, TS=TS, QUIET=QUIET, solve=solve, Mommat=Mommat)
end

function tssos_first(F::Polynomial{true, T1}, G::Vector{Matrix{Polynomial{true, T2}}}, x, d; TS="block", QUIET=false, solve=true, Mommat=false) where {T1,T2<:Number}
    return cs_tssos_first(F, G, x, d, CS=false, TS=TS, QUIET=QUIET, solve=solve, Mommat=Mommat)
end

function tssos_higher!(data::mpop_data; TS="block", QUIET=false, solve=true)
    return cs_tssos_higher!(data, TS=TS, QUIET=QUIET, solve=solve)
end

function cs_tssos_first(F::Matrix{Polynomial{true, T1}}, G::Vector{Polynomial{true, T2}}, x, d; CS="MF", TS="block", QUIET=false, solve=true, Mommat=false) where {T1,T2<:Number}
    nG = Vector{Matrix{Polynomial{true, T2}}}(undef, length(G))
    for i = 1:length(G)
        nG[i] = Matrix{Polynomial{true, T2}}(undef, 1, 1)
        nG[i][1,1] = G[i]
    end
    return cs_tssos_first(F, nG, x, d, CS=CS, TS=TS, QUIET=QUIET, solve=solve, Mommat=Mommat)
end

function cs_tssos_first(F::Polynomial{true, T1}, G::Vector{Matrix{Polynomial{true, T2}}}, x, d; CS="MF", TS="block", QUIET=false, solve=true, Mommat=false) where {T1,T2<:Number}
    nF = Matrix{Polynomial{true, T1}}(undef, 1, 1)
    nF[1,1] = F
    return cs_tssos_first(nF, G, x, d, CS=CS, TS=TS, QUIET=QUIET, solve=solve, Mommat=Mommat)
end

function cs_tssos_first(F::Matrix{Polynomial{true, T1}}, G::Vector{Matrix{Polynomial{true, T2}}}, x, d; CS="MF", TS="block", QUIET=false, solve=true, Mommat=false) where {T1,T2<:Number}
    println("*********************************** TSSOS ***********************************")
    println("TSSOS is launching...")
    n = length(x)
    m = length(G)
    dG = [maximum(maxdegree.(vec(G[i]))) for i=1:m]
    obj_matrix = poly_matrix(size(F,1), Vector{poly_data}(undef, Int((size(F,1)+1)*size(F,1)/2)))
    for i = 1:obj_matrix.m, j = i:obj_matrix.m
        _,supp,coe = polys_info([F[i,j]], x)
        obj_matrix.poly[i+Int(j*(j-1)/2)] = poly_data(n, supp[1], coe[1])
    end
    cons_matrix = Vector{poly_matrix}(undef, m)
    # csupp = Vector{UInt16}[]
    for k = 1:m
        cons_matrix[k] = poly_matrix(size(G[k],1), Vector{poly_data}(undef, Int((size(G[k],1)+1)*size(G[k],1)/2)))
        for i = 1:cons_matrix[k].m, j = i:cons_matrix[k].m
            _,supp,coe = polys_info([G[k][i,j]], x)
            # csupp = [csupp; supp[1]]
            cons_matrix[k].poly[i+Int(j*(j-1)/2)] = poly_data(n, supp[1], coe[1])
        end
    end
    cliques,cql,cliquesize = clique_decomp(n, m, d, dG, obj_matrix, cons_matrix, alg=CS, minimize=true)
    I,ncc = assign_constraint(m, cons_matrix, cliques, cql)
    basis = Vector{Vector{Vector{UInt16}}}(undef, cql)
    gbasis = Vector{Vector{Vector{Vector{UInt16}}}}(undef, cql)
    for i = 1:cql
        basis[i] = get_sbasis(cliques[i], d)
        gbasis[i] = Vector{Vector{Vector{UInt16}}}(undef, length(I[i]))
        for (s,k) in enumerate(I[i])
            gbasis[i][s] = get_sbasis(cliques[i], d-Int(ceil(dG[k]/2)))
        end
    end
    ksupp = Vector{Vector{Vector{UInt16}}}(undef, Int((obj_matrix.m+1)*obj_matrix.m/2))
    if TS != false
        for i = 1:obj_matrix.m, j = i:obj_matrix.m
            ind = i + Int(j*(j-1)/2)
            ksupp[ind] = copy(obj_matrix.poly[ind].supp)
            # ksupp[ind] = [obj_matrix.poly[ind].supp; csupp]
            if i == j
                for k = 1:cql, item in basis[k]
                    push!(ksupp[ind], sadd(item, item))
                end
            end
        end
        unique!.(ksupp)
        sort!.(ksupp)
    end
    blocks,cl,blocksize = get_mblocks(I, obj_matrix.m, cons_matrix, cliques, cql, ksupp, basis, gbasis, QUIET=QUIET, blocks=[], cl=[], blocksize=[], TS=TS)
    opt,ksupp,moment,SDP_status = pmo_sdp(obj_matrix, cons_matrix, basis, gbasis, blocks, cl, blocksize, cql, I, ncc, TS=TS, QUIET=QUIET, solve=solve, Mommat=Mommat)
    data = mpop_data(nothing, obj_matrix, cons_matrix, basis, gbasis, ksupp, cl, blocksize, blocks, cql, cliquesize, cliques, I, ncc, moment, SDP_status)
    return opt,data
end

function cs_tssos_higher!(data::mpop_data; TS="block", QUIET=false, solve=true)
    basis = data.basis
    gbasis = data.gbasis
    ksupp = data.ksupp
    obj_matrix = data.obj_matrix
    cons_matrix = data.cons_matrix
    blocks = data.blocks
    cl = data.cl
    oblocksize = deepcopy(data.blocksize)
    blocks,cl,blocksize = get_mblocks(data.I, obj_matrix.m, cons_matrix, data.cliques, data.cql, ksupp, basis, gbasis, blocks=blocks, 
    cl=cl, blocksize=data.blocksize, TS=TS, QUIET=QUIET)
    if blocksize == oblocksize
        opt = nothing
        println("No higher TS step of the CS-TSSOS hierarchy!")
    else
        opt,ksupp,_,SDP_status = pmo_sdp(obj_matrix, cons_matrix, basis, gbasis, blocks, cl, blocksize, data.cql, data.I, data.ncc, TS=TS, QUIET=QUIET, solve=solve)
        data.ksupp = ksupp
        data.SDP_status = SDP_status
    end
    return opt,data
end

function clique_decomp(n, m, d, dG, obj_matrix, cons_matrix; alg="MF", minimize=false)
    if alg == false
        cliques,cql,cliquesize = [UInt16[i for i=1:n]],1,[n]
    else
        G = SimpleGraph(n)
        for i = 1:Int((obj_matrix.m + 1)*obj_matrix.m/2)
            foreach(x -> add_clique!(G, unique(x)), obj_matrix.poly[i].supp)
        end
        for k = 1:m
            if d == ceil(Int, dG[k]/2)
                for i = 1:Int((cons_matrix[k].m + 1)*cons_matrix[k].m/2)
                    foreach(x -> add_clique!(G, unique(x)), cons_matrix[k].poly[i].supp)
                end
            else
                add_clique!(G, unique(vcat([isempty(cons_matrix[k].poly[s].supp) ? UInt16[] : reduce(vcat, cons_matrix[k].poly[s].supp) for s=1:Int((cons_matrix[k].m + 1)*cons_matrix[k].m/2)]...)))
            end
        end
        if alg == "NC"
            cliques,cql,cliquesize = max_cliques(G)
        else
            cliques,cql,cliquesize = chordal_cliques!(G, method=alg, minimize=minimize)
        end
    end
    uc = unique(cliquesize)
    sizes = [sum(cliquesize.== i) for i in uc]
    println("-----------------------------------------------------------------------------")
    println("The clique sizes of varibles:\n$uc\n$sizes")
    println("-----------------------------------------------------------------------------")
    return cliques,cql,cliquesize
end

function assign_constraint(m, cons_matrix, cliques, cql)
    I = [UInt16[] for i=1:cql]
    ncc = UInt16[]
    for i = 1:m
        ind = findall(k->issubset(unique(vcat([isempty(cons_matrix[i].poly[s].supp) ? UInt16[] : reduce(vcat, cons_matrix[i].poly[s].supp) for s=1:Int((cons_matrix[i].m + 1)*cons_matrix[i].m/2)]...)), cliques[k]), 1:cql)
        isempty(ind) ? push!(ncc, i) : push!.(I[ind], i)
    end
    return I,ncc
end

function get_mgraph(tsupp, basis, om)
    lb = length(basis)
    G = SimpleGraph(lb*om)
    for i = 1:om, j = i:om
        lt = length(tsupp[i+Int(j*(j-1)/2)])
        for k = 1:lb, l = 1:lb
            bi = sadd(basis[k], basis[l])
            if bfind(tsupp[i+Int(j*(j-1)/2)], lt, bi) !== nothing
               add_edge!(G, i+(k-1)*om, j+(l-1)*om)
            end
        end
    end
    return G
end

function get_mgraph(tsupp, cons_matrix, gbasis, om)
    com = cons_matrix.m*om
    lb = length(gbasis)*com
    G = SimpleGraph(lb)
    for j = 1:lb, k = j+1:lb
        p = cmod(j, com)
        q = cmod(k, com)
        p1 = ceil(Int, p/cons_matrix.m)
        q1 = ceil(Int, q/cons_matrix.m)
        ind = p1 <= q1 ? p1 + Int(q1*(q1-1)/2) : q1 + Int(p1*(p1-1)/2)
        t = cmod(j, cons_matrix.m)
        r = cmod(k, cons_matrix.m)
        loc = t <= r ? t + Int(r*(r-1)/2) : r + Int(t*(t-1)/2)
        flag = 0
        for w = 1:length(cons_matrix.poly[loc].supp)
            if bfind(tsupp[ind], length(tsupp[ind]), sadd(sadd(gbasis[ceil(Int, j/com)], gbasis[ceil(Int, k/com)]), cons_matrix.poly[loc].supp[w])) !== nothing
                flag = 1
                break
            end
        end
        if flag == 1
           add_edge!(G, j, k)
        end
    end
    return G
end

function get_mblocks(om, cons_matrix, tsupp, basis, gbasis; TS="block", blocks=[], cl=[], blocksize=[], QUIET=false)
    if isempty(blocks)
        blocks = Vector{Vector{Vector{UInt16}}}(undef, length(cons_matrix)+1)
        blocksize = Vector{Vector{UInt16}}(undef, length(cons_matrix)+1)
        cl = Vector{UInt16}(undef, length(cons_matrix)+1)
    end
    if TS == false
        for k = 1:length(cons_matrix) + 1
            lb = k == 1 ? om*length(basis) : om*cons_matrix[k-1].m*length(gbasis[k-1])
            blocks[k],blocksize[k],cl[k] = [Vector(1:lb)],[lb],1
        end
    else
        for k = 1:length(cons_matrix) + 1
            if k == 1
                G = get_mgraph(tsupp, basis, om)
            else
                G = get_mgraph(tsupp, cons_matrix[k-1], gbasis[k-1], om)
            end
            if TS == "block"
                blocks[k] = connected_components(G)
                blocksize[k] = length.(blocks[k])
                cl[k] = length(blocksize[k])            
            else
                blocks[k],cl[k],blocksize[k] = chordal_cliques!(G, method=TS, minimize=false)
            end
            # sb = sort(Int.(unique(blocksize[k])), rev=true)
            # numb = [sum(blocksize[k].== i) for i in sb]
            # println("-----------------------------------------------------------------------------")
            # println("The sizes of PSD blocks for the $k-th SOS multiplier:\n$sb\n$numb")
            # println("-----------------------------------------------------------------------------")
        end
    end
    return blocks,cl,blocksize
end

function get_mblocks(I, om, cons_matrix, cliques, cql, tsupp, basis, gbasis; blocks=[], cl=[], blocksize=[], TS="block", QUIET=true)
    if TS != false && QUIET == false
        println("Starting to compute the block structure...")
    end
    time = @elapsed begin
    if isempty(blocks)
        blocks = Vector{Vector{Vector{Vector{UInt16}}}}(undef, cql)
        cl = Vector{Vector{UInt16}}(undef, cql)
        blocksize = Vector{Vector{Vector{UInt16}}}(undef, cql)
        for i = 1:cql
            blocks[i] = Vector{Vector{Vector{UInt16}}}(undef, length(I[i])+1)
            cl[i] = Vector{UInt16}(undef, length(I[i])+1)
            blocksize[i] = Vector{Vector{UInt16}}(undef, length(I[i])+1)
            nsupp = nothing
            if TS != false
                ind = [[issubset(item[j], cliques[i]) for j in eachindex(item)] for item in tsupp]
                nsupp = [tsupp[k][ind[k]] for k = 1:length(tsupp)]
            end
            blocks[i],cl[i],blocksize[i] = get_mblocks(om, cons_matrix[I[i]], nsupp, basis[i], gbasis[i], TS=TS, QUIET=QUIET)
        end
    else
        for i = 1:cql
            ind = [[issubset(item[j], cliques[i]) for j in eachindex(item)] for item in tsupp]
            nsupp = [tsupp[k][ind[k]] for k = 1:length(tsupp)]
            blocks[i],cl[i],blocksize[i] = get_mblocks(om, cons_matrix[I[i]], nsupp, basis[i], gbasis[i], blocks=blocks[i], 
            cl=cl[i], blocksize=blocksize[i], TS=TS, QUIET=QUIET)
        end
    end
    end
    if QUIET == false
        mb = maximum(maximum.([maximum.(blocksize[i]) for i = 1:cql]))
        println("Obtained the block structure in $time seconds.\nThe maximal size of blocks is $mb.")
    end
    return blocks,cl,blocksize
end

function pmo_sdp(obj_matrix, cons_matrix, basis, gbasis, blocks, cl, blocksize, cql, I, ncc; TS="block", solve=true, QUIET=false, Mommat=false)
    om = obj_matrix.m
    ksupp = [Vector{UInt16}[] for i = 1:length(obj_matrix.poly)]
    for u = 1:cql, i = 1:cl[u][1], j = 1:blocksize[u][1][i], k = j:blocksize[u][1][i]
        bi = sadd(basis[u][ceil(Int, blocks[u][1][i][j]/om)], basis[u][ceil(Int, blocks[u][1][i][k]/om)])
        p = cmod(blocks[u][1][i][j], om)
        q = cmod(blocks[u][1][i][k], om)
        ind = p <= q ? p + Int(q*(q-1)/2) : q + Int(p*(p-1)/2)
        push!(ksupp[ind], bi)
    end
    if TS != false
        for u = 1:cql, (s,v) in enumerate(I[u])
            com = cons_matrix[v].m*om
            for i = 1:cl[u][s+1], j = 1:blocksize[u][s+1][i], k = j:blocksize[u][s+1][i]
                p = cmod(blocks[u][s+1][i][j], com)
                q = cmod(blocks[u][s+1][i][k], com)
                p1 = ceil(Int, p/cons_matrix[v].m)
                q1 = ceil(Int, q/cons_matrix[v].m)
                ind = p1 <= q1 ? p1 + Int(q1*(q1-1)/2) : q1 + Int(p1*(p1-1)/2)
                t = cmod(blocks[u][s+1][i][j], cons_matrix[v].m)
                r = cmod(blocks[u][s+1][i][k], cons_matrix[v].m)
                loc = t <= r ? t + Int(r*(r-1)/2) : r + Int(t*(t-1)/2)
                for w = 1:length(cons_matrix[v].poly[loc].supp)
                    bi = sadd(sadd(gbasis[u][s][ceil(Int, blocks[u][s+1][i][j]/com)], gbasis[u][s][ceil(Int, blocks[u][s+1][i][k]/com)]), cons_matrix[v].poly[loc].supp[w])
                    push!(ksupp[ind], bi)
                end
            end
        end
    end
    sort!.(ksupp)
    unique!.(ksupp)
    objv = SDP_status = moment = nothing
    if solve == true
        if QUIET == false
            ncons = sum(length.(ksupp))
            println("Assembling the SDP...")
            println("There are $ncons affine constraints.")
        end
        model = Model(optimizer_with_attributes(Mosek.Optimizer))
        set_optimizer_attribute(model, MOI.Silent(), QUIET)
        time = @elapsed begin
        cons = Vector{Vector{AffExpr}}(undef, length(obj_matrix.poly))
        for i = 1:length(obj_matrix.poly)
            cons[i] = [AffExpr(0) for j=1:length(ksupp[i])]
        end
        for u = 1:cql
            pos = Vector{Union{VariableRef,Symmetric{VariableRef}}}(undef, cl[u][1])
            for i = 1:cl[u][1]
                pos[i] = @variable(model, [1:blocksize[u][1][i], 1:blocksize[u][1][i]], PSD)
                for j = 1:blocksize[u][1][i], k = j:blocksize[u][1][i]
                    p = cmod(blocks[u][1][i][j], om)
                    q = cmod(blocks[u][1][i][k], om)
                    ind = p <= q ? p + Int(q*(q-1)/2) : q + Int(p*(p-1)/2)
                    Locb = bfind(ksupp[ind], length(ksupp[ind]), sadd(basis[u][ceil(Int, blocks[u][1][i][j]/om)], basis[u][ceil(Int, blocks[u][1][i][k]/om)]))
                    if p != q || j == k
                        @inbounds add_to_expression!(cons[ind][Locb], pos[i][j,k])
                    else
                        @inbounds add_to_expression!(cons[ind][Locb], 2, pos[i][j,k])
                    end
                end
            end
            gpos = Vector{Vector{Union{VariableRef,Symmetric{VariableRef}}}}(undef, length(I[u]))
            for (s,v) in enumerate(I[u])
                gpos[s] = Vector{Union{VariableRef,Symmetric{VariableRef}}}(undef, cl[u][s+1])
                com = cons_matrix[v].m*om
                for i = 1:cl[u][s+1]
                    gpos[s][i] = @variable(model, [1:blocksize[u][s+1][i], 1:blocksize[u][s+1][i]], PSD)
                    for j = 1:blocksize[u][s+1][i], k = j:blocksize[u][s+1][i]
                        p = cmod(blocks[u][s+1][i][j], com)
                        q = cmod(blocks[u][s+1][i][k], com)
                        p1 = ceil(Int, p/cons_matrix[v].m)
                        q1 = ceil(Int, q/cons_matrix[v].m)
                        ind = p1 <= q1 ? p1 + Int(q1*(q1-1)/2) : q1 + Int(p1*(p1-1)/2)
                        p2 = ceil(Int, blocks[u][s+1][i][j]/com)
                        q2 = ceil(Int, blocks[u][s+1][i][k]/com)
                        t = cmod(blocks[u][s+1][i][j], cons_matrix[v].m)
                        r = cmod(blocks[u][s+1][i][k], cons_matrix[v].m)
                        loc = t <= r ? t + Int(r*(r-1)/2) : r + Int(t*(t-1)/2)
                        for w = 1:length(cons_matrix[v].poly[loc].supp)
                            Locb = bfind(ksupp[ind], length(ksupp[ind]), sadd(sadd(gbasis[u][s][p2], gbasis[u][s][q2]), cons_matrix[v].poly[loc].supp[w]))
                            if p1 != q1 || (p2 == q2 && t == r)
                                @inbounds add_to_expression!(cons[ind][Locb], cons_matrix[v].poly[loc].coe[w], gpos[s][i][j,k])
                            else
                                @inbounds add_to_expression!(cons[ind][Locb], 2*cons_matrix[v].poly[loc].coe[w], gpos[s][i][j,k])
                            end
                        end
                    end
                end
            end
        end
        for i in ncc
            com = cons_matrix[i].m*om
            lpos = @variable(model, [1:com, 1:com], PSD)
            for j = 1:com, k = j:com
                p1 = ceil(Int, j/cons_matrix[i].m)
                q1 = ceil(Int, k/cons_matrix[i].m)
                ind = p1 <= q1 ? p1 + Int(q1*(q1-1)/2) : q1 + Int(p1*(p1-1)/2)
                t = cmod(j, cons_matrix[i].m)
                r = cmod(k, cons_matrix[i].m)
                loc = t <= r ? t + Int(r*(r-1)/2) : r + Int(t*(t-1)/2)
                for w = 1:length(cons_matrix[i].poly[loc].supp)
                    Locb = bfind(ksupp[ind], length(ksupp[ind]), cons_matrix[i].poly[loc].supp[w])
                    if p1 != q1 || t == r
                        @inbounds add_to_expression!(cons[ind][Locb], cons_matrix[i].poly[loc].coe[w], lpos[j,k])
                    else
                        @inbounds add_to_expression!(cons[ind][Locb], 2*cons_matrix[i].poly[loc].coe[w], lpos[j,k])
                    end
                end
            end
        end
        @variable(model, lower)
        for i = 1:om, j = i:om
            ind = i + Int(j*(j-1)/2)
            bc = zeros(length(ksupp[ind]))
            for k = 1:length(obj_matrix.poly[ind].supp)
                Locb = bfind(ksupp[ind], length(ksupp[ind]), obj_matrix.poly[ind].supp[k])
                if Locb === nothing
                   @error "The monomial basis is not enough!"
                   return nothing,nothing,nothing
                else
                   bc[Locb] = obj_matrix.poly[ind].coe[k]
                end
            end
            if i == j
                cons[ind][1] += lower
            end
            @constraint(model, [i=1:length(ksupp[ind])], cons[ind][i]==bc[i], base_name="con$ind")
        end
        @objective(model, Max, lower)
        end
        if QUIET == false
            println("SDP assembling time: $time seconds.")
            println("Solving the SDP...")
        end
        time = @elapsed begin
        optimize!(model)
        end
        if QUIET == false
            println("SDP solving time: $time seconds.")
        end
        SDP_status = termination_status(model)
        objv = objective_value(model)
        if SDP_status != MOI.OPTIMAL
            println("termination status: $SDP_status")
            status = primal_status(model)
            println("solution status: $status")
        end
        println("optimum = $objv")
        if Mommat == true
            measure = [[-dual(constraint_by_name(model, "con$i[$j]")) for j = 1:length(ksupp[i])] for i = 1:length(ksupp)]
            moment = get_mmoment(measure, ksupp[1], cql, basis, om)
        end
    end 
    return objv,ksupp,moment,SDP_status
end

function LinearPMI_first(b, F::Vector{Matrix{Polynomial{true, T1}}}, G::Vector{Polynomial{true, T2}}, x, d; TS="block", QUIET=false, solve=true, Mommat=false) where {T1,T2<:Number}
    nG = Vector{Matrix{Polynomial{true, T2}}}(undef, length(G))
    for i = 1:length(G)
        nG[i] = Matrix{Polynomial{true, T2}}(undef, 1, 1)
        nG[i][1,1] = G[i]
    end
    return LinearPMI_first(b, F, nG, x, d, TS=TS, QUIET=QUIET, solve=solve, Mommat=Mommat)
end

function LinearPMI_first(b, F::Vector{Matrix{Polynomial{true, T1}}}, G::Vector{Matrix{Polynomial{true, T2}}}, x, d; TS="block", QUIET=false, solve=true, Mommat=false) where {T1,T2<:Number}
    println("*********************************** TSSOS ***********************************")
    println("TSSOS is launching...")
    n = length(x)
    s = length(F)
    m = length(G)
    dG = [maximum(maxdegree.(vec(G[i]))) for i=1:m]
    obj_matrix = Vector{poly_matrix}(undef, s)
    for k = 1:s
        obj_matrix[k] = poly_matrix(size(F[k],1), Vector{poly_data}(undef, Int((size(F[k],1)+1)*size(F[k],1)/2)))
        for i = 1:obj_matrix[k].m, j = i:obj_matrix[k].m
            _,supp,coe = polys_info([F[k][i,j]], x)
            obj_matrix[k].poly[i+Int(j*(j-1)/2)] = poly_data(n, supp[1], coe[1])
        end
    end
    basis = get_sbasis(Vector(1:n), d)
    cons_matrix = Vector{poly_matrix}(undef, m)
    # csupp = Vector{UInt16}[]
    gbasis = Vector{Vector{Vector{UInt16}}}(undef, m)
    for k = 1:m
        gbasis[k] = get_sbasis(Vector(1:n), d-Int(ceil(dG[k]/2)))
        cons_matrix[k] = poly_matrix(size(G[k],1), Vector{poly_data}(undef, Int((size(G[k],1)+1)*size(G[k],1)/2)))
        for i = 1:cons_matrix[k].m, j = i:cons_matrix[k].m
            _,supp,coe = polys_info([G[k][i,j]], x)
            # csupp = [csupp; supp[1]]
            cons_matrix[k].poly[i+Int(j*(j-1)/2)] = poly_data(n, supp[1], coe[1])
        end
    end
    ksupp = Vector{Vector{Vector{UInt16}}}(undef, Int((obj_matrix[1].m+1)*obj_matrix[1].m/2))
    if TS != false
        for i = 1:obj_matrix[1].m, j = i:obj_matrix[1].m
            ind = i + Int(j*(j-1)/2)
            ksupp[ind] = reduce(vcat, [obj_matrix[k].poly[ind].supp for k=1:s])
            # ksupp[ind] = [reduce(vcat, [obj_matrix[k].poly[ind].supp for k=1:s]); csupp]
            if i == j
                for item in basis
                    push!(ksupp[ind], sadd(item, item))
                end
            end
        end
        unique!.(ksupp)
        sort!.(ksupp)
        if QUIET == false
            println("Starting to compute the block structure...")
        end
    end
    time = @elapsed begin
    blocks,cl,blocksize = get_mblocks(obj_matrix[1].m, cons_matrix, ksupp, basis, gbasis, TS=TS, QUIET=QUIET)
    end
    if QUIET == false
        mb = maximum(maximum.(blocksize))
        println("Obtained the block structure in $time seconds.\nThe maximal size of blocks is $mb.")
    end
    opt,ksupp,moment,SDP_status = LinearPMI_sdp(b, obj_matrix, cons_matrix, basis, gbasis, blocks, cl, blocksize, TS=TS, QUIET=QUIET, solve=solve, Mommat=Mommat)
    data = mpop_data(b, obj_matrix, cons_matrix, basis, gbasis, ksupp, cl, blocksize, blocks, nothing, nothing, nothing, nothing, nothing, moment, SDP_status)
    return opt,data
end

function LinearPMI_higher!(data::mpop_data; TS="block", QUIET=false, solve=true)
    basis = data.basis
    gbasis = data.gbasis
    ksupp = data.ksupp
    obj_matrix = data.obj_matrix
    cons_matrix = data.cons_matrix
    blocks = data.blocks
    cl = data.cl
    oblocksize = deepcopy(data.blocksize)
    if TS != false && QUIET == false
        println("Starting to compute the block structure...")
    end
    time = @elapsed begin
    blocks,cl,blocksize = get_mblocks(obj_matrix[1].m, cons_matrix, ksupp, basis, gbasis, blocks=blocks, cl=cl, blocksize=data.blocksize, TS=TS, QUIET=QUIET)
    end
    if QUIET == false
        mb = maximum(maximum.(blocksize))
        println("Obtained the block structure in $time seconds.\nThe maximal size of blocks is $mb.")
    end
    if blocksize == oblocksize
        opt = nothing
        println("No higher TS step of the TSSOS hierarchy!")
    else
        opt,ksupp,SDP_status = LinearPMI_sdp(data.b, obj_matrix, cons_matrix, basis, gbasis, blocks, cl, blocksize, TS=TS, QUIET=QUIET, solve=solve)
        data.ksupp = ksupp
        data.SDP_status = SDP_status
    end
    return opt,data
end

function LinearPMI_sdp(b, obj_matrix, cons_matrix, basis, gbasis, blocks, cl, blocksize; TS="block", solve=true, QUIET=false, Mommat=false)
    om = obj_matrix[1].m
    ksupp = [Vector{UInt16}[] for i = 1:length(obj_matrix[1].poly)]
    for i = 1:cl[1], j = 1:blocksize[1][i], k = j:blocksize[1][i]
        bi = sadd(basis[ceil(Int, blocks[1][i][j]/om)], basis[ceil(Int, blocks[1][i][k]/om)])
        p = cmod(blocks[1][i][j], om)
        q = cmod(blocks[1][i][k], om)
        ind = p <= q ? p + Int(q*(q-1)/2) : q + Int(p*(p-1)/2)
        push!(ksupp[ind], bi)
    end
    if TS != false
        for s = 1:length(cons_matrix)
            com = cons_matrix[s].m*om
            for i = 1:cl[s+1], j = 1:blocksize[s+1][i], k = j:blocksize[s+1][i]
                p = cmod(blocks[s+1][i][j], com)
                q = cmod(blocks[s+1][i][k], com)
                p1 = ceil(Int, p/cons_matrix[s].m)
                q1 = ceil(Int, q/cons_matrix[s].m)
                ind = p1 <= q1 ? p1 + Int(q1*(q1-1)/2) : q1 + Int(p1*(p1-1)/2)
                t = cmod(blocks[s+1][i][j], cons_matrix[s].m)
                r = cmod(blocks[s+1][i][k], cons_matrix[s].m)
                loc = t <= r ? t + Int(r*(r-1)/2) : r + Int(t*(t-1)/2)
                for w = 1:length(cons_matrix[s].poly[loc].supp)
                    bi = sadd(sadd(gbasis[s][ceil(Int, blocks[s+1][i][j]/com)], gbasis[s][ceil(Int, blocks[s+1][i][k]/com)]), cons_matrix[s].poly[loc].supp[w])
                    push!(ksupp[ind], bi)
                end
            end
        end
    end
    unique!.(ksupp)
    sort!.(ksupp)
    objv = SDP_status = moment = nothing
    if solve == true
        if QUIET == false
            ncons = sum(length.(ksupp))
            println("Assembling the SDP...")
            println("There are $ncons affine constraints.")
        end
        model = Model(optimizer_with_attributes(Mosek.Optimizer))
        set_optimizer_attribute(model, MOI.Silent(), QUIET)
        time = @elapsed begin
        cons = Vector{Vector{AffExpr}}(undef, length(obj_matrix[1].poly))
        for i = 1:length(obj_matrix[1].poly)
            cons[i] = [AffExpr(0) for j=1:length(ksupp[i])]
        end
        pos = Vector{Union{VariableRef,Symmetric{VariableRef}}}(undef, cl[1])
        for i = 1:cl[1]
            pos[i] = @variable(model, [1:blocksize[1][i], 1:blocksize[1][i]], PSD)
            for j = 1:blocksize[1][i], k = j:blocksize[1][i]
                p = cmod(blocks[1][i][j], om)
                q = cmod(blocks[1][i][k], om)
                ind = p <= q ? p + Int(q*(q-1)/2) : q + Int(p*(p-1)/2)
                Locb = bfind(ksupp[ind], length(ksupp[ind]), sadd(basis[ceil(Int, blocks[1][i][j]/om)], basis[ceil(Int, blocks[1][i][k]/om)]))
                if p != q || j == k
                    @inbounds add_to_expression!(cons[ind][Locb], pos[i][j,k])
                else
                    @inbounds add_to_expression!(cons[ind][Locb], 2, pos[i][j,k])
                end
            end
        end
        gpos = Vector{Vector{Union{VariableRef,Symmetric{VariableRef}}}}(undef, length(cons_matrix))
        for s = 1:length(cons_matrix)
            gpos[s] = Vector{Union{VariableRef,Symmetric{VariableRef}}}(undef, cl[s+1])
            com = cons_matrix[s].m*om
            for i = 1:cl[s+1]
                gpos[s][i] = @variable(model, [1:blocksize[s+1][i], 1:blocksize[s+1][i]], base_name="P", PSD)
                for j = 1:blocksize[s+1][i], k = j:blocksize[s+1][i]
                    p = cmod(blocks[s+1][i][j], com)
                    q = cmod(blocks[s+1][i][k], com)
                    p1 = ceil(Int, p/cons_matrix[s].m)
                    q1 = ceil(Int, q/cons_matrix[s].m)
                    ind = p1 <= q1 ? p1 + Int(q1*(q1-1)/2) : q1 + Int(p1*(p1-1)/2)
                    p2 = ceil(Int, blocks[s+1][i][j]/com)
                    q2 = ceil(Int, blocks[s+1][i][k]/com)
                    t = cmod(blocks[s+1][i][j], cons_matrix[s].m)
                    r = cmod(blocks[s+1][i][k], cons_matrix[s].m)
                    loc = t <= r ? t + Int(r*(r-1)/2) : r + Int(t*(t-1)/2)
                    for w = 1:length(cons_matrix[s].poly[loc].supp)
                        Locb = bfind(ksupp[ind], length(ksupp[ind]), sadd(sadd(gbasis[s][p2], gbasis[s][q2]), cons_matrix[s].poly[loc].supp[w]))
                        if p1 != q1 || (p2 == q2 && t == r)
                            @inbounds add_to_expression!(cons[ind][Locb], cons_matrix[s].poly[loc].coe[w], gpos[s][i][j,k])
                        else
                            @inbounds add_to_expression!(cons[ind][Locb], 2*cons_matrix[s].poly[loc].coe[w], gpos[s][i][j,k])
                        end
                    end
                end
            end
        end
        λ = @variable(model, [1:length(b)])
        for i = 1:om, j = i:om
            ind = i + Int(j*(j-1)/2)
            bc = [AffExpr(0) for k = 1:length(ksupp[ind])]
            for k = 1:length(obj_matrix[1].poly[ind].supp)
                Locb = bfind(ksupp[ind], length(ksupp[ind]), obj_matrix[1].poly[ind].supp[k])
                if Locb === nothing
                    @error "The monomial basis is not enough!"
                    return nothing,nothing,nothing
                else
                    @inbounds add_to_expression!(bc[Locb], obj_matrix[1].poly[ind].coe[k])
                end
            end
            for t = 2:length(obj_matrix), k = 1:length(obj_matrix[t].poly[ind].supp)
                Locb = bfind(ksupp[ind], length(ksupp[ind]), obj_matrix[t].poly[ind].supp[k])
                if Locb === nothing
                    @error "The monomial basis is not enough!"
                    return nothing,nothing,nothing
                else
                    @inbounds add_to_expression!(bc[Locb], λ[t-1], obj_matrix[t].poly[ind].coe[k])
                end
            end
            @constraint(model, [i=1:length(ksupp[ind])], cons[ind][i]==bc[i], base_name="con$ind")
        end
        @objective(model, Min, b'*λ)
        end
        if QUIET == false
            println("SDP assembling time: $time seconds.")
            println("Solving the SDP...")
        end
        time = @elapsed begin
        optimize!(model)
        end
        if QUIET == false
            println("SDP solving time: $time seconds.")
        end
        SDP_status = termination_status(model)
        objv = objective_value(model)
        if SDP_status != MOI.OPTIMAL
            println("termination status: $SDP_status")
            status = primal_status(model)
            println("solution status: $status")
        end
        println("optimum = $objv")
        if Mommat == true
            measure = [[-dual(constraint_by_name(model, "con$i[$j]")) for j = 1:length(ksupp[i])] for i = 1:length(ksupp)]
            moment = get_mmoment(measure, ksupp[1], 1, basis, om)
        end
    end
    return objv,ksupp,moment,SDP_status
end

function add_SOSMatrix!(model, vars, m, d; constraint=nothing, TS=false, QUIET=true, tsupp=[])
    mons = vcat([MultivariatePolynomials.monomials(vars, i) for i = 0:d]...)
    if TS == false
        lb = m*length(mons)
        blocks,blocksize,cl = [Vector(1:lb)],[lb],1
    else
        basis = get_sbasis(Vector(1:length(vars)), d)
        if constraint === nothing
            G = get_mgraph(tsupp, basis, m)
        else
            s = size(constraint, 1)
            cons_matrix = poly_matrix(s, Vector{poly_data}(undef, Int((s+1)*s/2)))
            for i = 1:s, j = i:s
                _,supp,coe = polys_info([constraint[i,j]], vars)
                cons_matrix.poly[i+Int(j*(j-1)/2)] = poly_data(length(vars), supp[1], coe[1])
            end
            G = get_mgraph(tsupp, cons_matrix, basis, Int(m/s))
        end
        if TS == "block"
            blocks = connected_components(G)
            blocksize = length.(blocks)
            cl = length(blocksize)            
        else
            blocks,cl,blocksize = chordal_cliques!(G, method=TS, minimize=false)
        end
    end
    if QUIET == false
        sb = sort(Int.(unique(blocksize)), rev=true)
        numb = [sum(blocksize.== i) for i in sb]
        println("-----------------------------------------------------------------------------")
        println("The sizes of PSD blocks:\n$sb\n$numb")
        println("-----------------------------------------------------------------------------")
    end
    sosmatrix = Matrix{Polynomial{true, AffExpr}}(undef, m, m)
    for i = 1:m, j = 1:m
        sosmatrix[i,j] = 0
    end
    for i = 1:cl
        pos = @variable(model, [1:blocksize[i], 1:blocksize[i]], PSD)
        for j = 1:blocksize[i], k = j:blocksize[i]
            p = cmod(blocks[i][j], m)
            q = cmod(blocks[i][k], m)
            if p > q
                p,q = q,p
            end
            if p != q || j == k
                @inbounds sosmatrix[p,q] += pos[j,k]*mons[ceil(Int, blocks[i][j]/m)]*mons[ceil(Int, blocks[i][k]/m)]
            else
                @inbounds sosmatrix[p,q] += 2*pos[j,k]*mons[ceil(Int, blocks[i][j]/m)]*mons[ceil(Int, blocks[i][k]/m)]
            end
        end
    end
    return sosmatrix,maximum(blocksize)
end

function sparseobj(F::Matrix{Polynomial{true, T1}}, G::Vector{Polynomial{true, T2}}, x, d; TS="block", QUIET=false) where {T1,T2<:Number}
    nG = Vector{Matrix{Polynomial{true, T2}}}(undef, length(G))
    for i = 1:length(G)
        nG[i] = Matrix{Polynomial{true, T2}}(undef, 1, 1)
        nG[i][1,1] = G[i]
    end
    return sparseobj(F, nG, x, d, TS=TS, QUIET=QUIET)
end

function sparseobj(F::Matrix{Polynomial{true, T1}}, G::Vector{Matrix{Polynomial{true, T2}}}, x, d; TS="block", QUIET=false) where {T1,T2<:Number}
    println("*********************************** TSSOS ***********************************")
    println("TSSOS is launching...")
    m = size(F, 1)
    n = length(x)
    dG = [maximum(maxdegree.(vec(G[i]))) for i=1:length(G)]
    K = SimpleGraph(m)
    for i = 1:m, j = i+1:m
        if F[i,j] != 0
            add_edge!(K, i, j)
        end
    end
    blocks,cl,blocksize = chordal_cliques!(K, method="MF", minimize=true)
    tsupp = []
    if TS != false
        tsupp = Vector{Vector{Vector{UInt16}}}(undef, Int((m+1)*m/2))
        supp = Vector{UInt16}[]
        for i = 1:m, j = i:m
            supp = [supp; polys_info([F[i,j]], x)[2][1]]
        end
        basis = get_sbasis(Vector(1:n), d)
        for item in basis
            push!(supp, sadd(item, item))
        end
        unique!(supp)
        sort!(supp)
        for i = 1:m, j = i:m
            tsupp[i + Int(j*(j-1)/2)] = supp
        end
    end
    model = Model(optimizer_with_attributes(Mosek.Optimizer))
    set_optimizer_attribute(model, MOI.Silent(), QUIET)
    sos = Vector{Vector{Matrix{Polynomial{true, AffExpr}}}}(undef, length(G)+1)
    mb = zeros(Int, length(G)+1, cl)
    for i = 1:length(G) + 1
        sos[i] = Vector{Matrix{Polynomial{true, AffExpr}}}(undef, cl)
        for j = 1:cl
            if i == 1
                sos[1][j],mb[1,j] = add_SOSMatrix!(model, x, blocksize[j], d, TS=TS, QUIET=QUIET, tsupp=tsupp)
            else
                sos[i][j],mb[i,j] = add_SOSMatrix!(model, x, blocksize[j]*size(G[i-1],1), d-Int(ceil(dG[i-1]/2)), constraint=G[i-1], TS=TS, QUIET=QUIET, tsupp=tsupp)
            end
        end
    end
    @variable(model, lower)
    temp = Matrix{Polynomial{true, AffExpr}}(undef, m ,m)
    for i = 1:m, j = i:m
        temp[i,j] = F[i,j]
        if i == j
            temp[i,i] -= lower
        end
    end
    for i = 1:cl, j = 1:blocksize[i], k = j:blocksize[i]
        temp[blocks[i][j], blocks[i][k]] -= sos[1][i][j,k]
        for l = 1:length(G)
            sG = size(G[l],1)
            if j != k
                temp[blocks[i][j], blocks[i][k]] -= sum(sos[l+1][i][(j-1)*sG+1:j*sG,(k-1)*sG+1:k*sG].*G[l])
            else
                for s = (j-1)*sG+1:j*sG, t = s:j*sG
                    if s == t
                        temp[blocks[i][j], blocks[i][k]] -= sum(sos[l+1][i][s,t]*G[l][s-((j-1)*sG),t-((j-1)*sG)])
                    else
                        temp[blocks[i][j], blocks[i][k]] -= 2*sum(sos[l+1][i][s,t]*G[l][s-((j-1)*sG),t-((j-1)*sG)])
                    end
                end
            end
        end
    end
    for i = 1:m, j = i:m
        if i == j || has_edge(K, i, j)
            @constraint(model, MultivariatePolynomials.coefficients(temp[i,j]).==0)
        end
    end
    @objective(model, Max, lower)
    println("Solving the SDP...")
    time = @elapsed begin
    optimize!(model)
    end
    println("SDP solving time: $time seconds.")
    SDP_status = termination_status(model)
    optimum = objective_value(model)
    if SDP_status != MOI.OPTIMAL
        println("termination status: $SDP_status")
        status = primal_status(model)
        println("solution status: $status")
    end
    @show optimum
    return optimum,maximum(mb)
end

function sparseobj(b, F::Vector{Matrix{Polynomial{true, T}}}, G, x, d; TS="block", QUIET=false) where {T<:Number}
    println("*********************************** TSSOS ***********************************")
    println("TSSOS is launching...")
    m = size(F[1], 1)
    n = length(x)
    dG = [maximum(maxdegree.(vec(G[i]))) for i=1:length(G)]
    K = SimpleGraph(m)
    for k = 1:length(F), i = 1:m, j = i+1:m
        if F[k][i,j] != 0
            add_edge!(K, i, j)
        end
    end
    blocks,cl,blocksize = chordal_cliques!(K, method="MF", minimize=true)
    tsupp = []
    if TS != false
        tsupp = Vector{Vector{Vector{UInt16}}}(undef, Int((m+1)*m/2))
        supp = Vector{UInt16}[]
        for k = 1:length(F), i = 1:m, j = i:m
            supp = [supp; polys_info([F[k][i,j]], x)[2][1]]
        end
        basis = get_sbasis(Vector(1:n), d)
        for item in basis
            push!(supp, sadd(item, item))
        end
        unique!(supp)
        sort!(supp)
        for i = 1:m, j = i:m
            tsupp[i + Int(j*(j-1)/2)] = supp
        end
    end
    model = Model(optimizer_with_attributes(Mosek.Optimizer))
    set_optimizer_attribute(model, MOI.Silent(), QUIET)
    sos = Vector{Vector{Matrix{Polynomial{true, AffExpr}}}}(undef, length(G)+1)
    mb = zeros(Int, length(G)+1, cl)
    for i = 1:length(G) + 1
        sos[i] = Vector{Matrix{Polynomial{true, AffExpr}}}(undef, cl)
        for j = 1:cl
            if i == 1
                sos[1][j],mb[1,j] = add_SOSMatrix!(model, x, blocksize[j], d, TS=TS, QUIET=QUIET, tsupp=tsupp)
            else
                sos[i][j],mb[i,j] = add_SOSMatrix!(model, x, blocksize[j]*size(G[i-1],1), d-Int(ceil(dG[i-1]/2)), constraint=G[i-1], TS=TS, QUIET=QUIET, tsupp=tsupp)
            end
        end
    end
    λ = @variable(model, [1:length(b)])
    temp = Matrix{Polynomial{true, AffExpr}}(undef, m ,m)
    for i = 1:m, j = i:m
        temp[i,j] = F[1][i,j]
        for k = 1:length(b)
            temp[i,j] += λ[k]*F[k+1][i,j]
        end
    end
    for i = 1:cl, j = 1:blocksize[i], k = j:blocksize[i]
        temp[blocks[i][j], blocks[i][k]] -= sos[1][i][j,k]
        for l = 1:length(G)
            sG = size(G[l],1)
            temp[blocks[i][j], blocks[i][k]] -= sum(sos[l+1][i][(j-1)*sG+1:j*sG,(k-1)*sG+1:k*sG].*G[l])
        end
    end
    for i = 1:m, j = i:m
        if i == j || has_edge(K, i, j)
            @constraint(model, MultivariatePolynomials.coefficients(temp[i,j]).==0)
        end
    end
    @objective(model, Min, b'*λ)
    println("Solving the SDP...")
    time = @elapsed begin
    optimize!(model)
    end
    println("SDP solving time: $time seconds.")
    SDP_status = termination_status(model)
    optimum = objective_value(model)
    if SDP_status != MOI.OPTIMAL
        println("termination status: $SDP_status")
        status = primal_status(model)
        println("solution status: $status")
    end
    @show optimum
    return optimum,maximum(mb)
end

function get_mmoment(measure, tsupp, cql, basis, om)
    moment = Vector{Union{Symmetric{Float64}, Array{Float64,2}}}(undef, cql)
    ltsupp = length(tsupp)
    for i = 1:cql
        lb = length(basis[i])
        moment[i] = zeros(Float64, om*lb, om*lb)
        for j = 1:lb, k = j:lb
            bi = sadd(basis[i][j], basis[i][k])
            Locb = bfind(tsupp, ltsupp, bi)
            for s = 1:om, t = 1:om
                ind = s <= t ? s + Int(t*(t-1)/2) : t + Int(s*(s-1)/2)
                if s == t
                    moment[i][(j-1)*om+s,(k-1)*om+t] = measure[ind][Locb]
                else
                    moment[i][(j-1)*om+s,(k-1)*om+t] = measure[ind][Locb]/2
                end
            end
        end
        moment[i] = Symmetric(moment[i],:U)
    end
    return moment
end