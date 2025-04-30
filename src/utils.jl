# find the location of an entry a in a sorted sequence A
function bfind(A, l, a)
    low = 1
    high = l
    while low <= high
        mid = Int(ceil(1/2*(low+high)))
        if ndims(A) == 2
            temp = A[:, mid]
        else
            temp = A[mid]
        end
        if temp == a
           return mid
        elseif temp < a
           low = mid + 1
        else
           high = mid - 1
        end
    end
    return nothing
end

function ncbfind(A, l, a)
    low = 1
    high = l
    while low <= high
        mid = Int(ceil(1/2*(low+high)))
        if A[mid] == a
           return mid
        elseif A[mid] < a
            high = mid - 1
        else
            low = mid + 1
        end
    end
    return nothing
end

function get_signsymmetry(polys::Vector{Polynomial{true, T}}, x) where {T<:Number}
    n = length(x)
    supp = zeros(UInt8, 1, n)
    for k = 1:length(polys)
        mons = MultivariatePolynomials.monomials(polys[k])
        temp = zeros(UInt8, length(mons), n)
        for i in eachindex(mons), j = 1:n
            @inbounds temp[i, j] = MultivariatePolynomials.degree(mons[i], x[j])
        end
        supp = [supp; temp]
    end
    supp = unique(supp, dims=1)
    supp = matrix(GF(2), supp)
    return nullspace(supp)[2]
end

function get_signsymmetry(supp::Vector{Vector{Vector{UInt16}}}, n)
    nsupp = zeros(UInt8, sum(length.(supp)), n)
    l = 1
    for item in supp, bi in item
        for i in bi
            nsupp[l, i] += 1
        end
        l += 1
    end
    nsupp = unique(nsupp, dims=1)
    nsupp = matrix(GF(2), nsupp)
    return nullspace(nsupp)[2]
end

function get_signsymmetry(supp::Matrix{UInt8})
    supp = unique(supp, dims=1)
    supp = matrix(GF(2), supp)
    return nullspace(supp)[2]
end

function bin_add(bi, bj, nb)
    bs = bi + bj
    if nb > 0
        bs[1:nb,:] = isodd.(bs[1:nb,:])
    end
    return bs
end

function sadd(a, b; nb=0)
    c = [a; b]
    sort!(c)
    if nb > 0
        i = 1
        while i < length(c)
            if c[i] <= nb
                if c[i] == c[i+1]
                    deleteat!(c, i:i+1)
                else
                    i += 1
                end
            else
                break
            end
        end
    end
    return c
end

# generate the standard monomial basis
function get_basis(n::Int, d::Int; nb=0, lead=[], var=[])
    if isempty(var)
        lb = binomial(n+d, d)
        basis = zeros(UInt8, n, lb)
        i = 0
        t = 1
        while i < d+1
            t += 1
            if basis[n,t-1] == i
               if i < d
                  basis[1,t] = i+1
               end
               i += 1
            else
                j = findfirst(x->basis[x,t-1]!=0, 1:n)
                basis[:,t] = basis[:,t-1]
                if j == 1
                   basis[1,t] -= 1
                   basis[2,t] += 1
                else
                   basis[1,t] = basis[j,t] - 1
                   basis[j,t] = 0
                   basis[j+1,t] += 1
                end
            end
        end
        if nb > 0
            basis_bin = basis[1:nb,:]
            basis_valid = all.(x->x<=1, eachcol(basis_bin))
            basis = basis[:, basis_valid]
        end
        if !isempty(lead)
            basis_valid = map(a->!divide(a, lead, n, size(lead,2)), eachcol(basis))
            basis = basis[:, basis_valid]
        end
    else
        lb = binomial(length(var)+d, d)
        basis = zeros(UInt8, n, lb)
        i = 0
        t = 1
        while i < d+1
            t += 1
            if basis[var[end], t-1] == i
               if i < d
                  basis[var[1], t] = i + 1
               end
               i += 1
            else
                j = findfirst(x->basis[var[x], t-1] != 0, 1:n)
                basis[:, t] = basis[:, t-1]
                if j == 1
                   basis[var[1], t] -= 1
                   basis[var[2], t] += 1
                else
                   basis[var[1], t] = basis[var[j], t] - 1
                   basis[var[j], t] = 0
                   basis[var[j+1], t] += 1
                end
            end
        end
    end
    return basis
end

# generate the standard monomial basis in the sparse form
function get_basis(var::Vector{UInt16}, d::Int; nb=0)
    n = length(var)
    lb = binomial(n+d, d)
    basis = Vector{Vector{UInt16}}(undef, lb)
    basis[1] = UInt16[]
    i = 0
    t = 1
    while i < d + 1
        t += 1
        if sum(basis[t-1]) == var[n]*i
           if i < d
               basis[t] = var[1]*ones(UInt16, i+1)
           end
           i += 1
        else
            j = bfind(var, n, basis[t-1][1])
            basis[t] = copy(basis[t-1])
            ind = findfirst(x->basis[t][x]!=var[j], 1:length(basis[t]))
            if ind === nothing
                ind = length(basis[t])+1
            end
            if j != 1
                basis[t][1:ind-2] = var[1]*ones(UInt16, ind-2)
            end
            basis[t][ind-1] = var[j+1]
        end
    end
    if nb > 0
        ind = [!any([basis[i][j] == basis[i][j+1] && basis[i][j] <= nb for j = 1:length(basis[i])-1]) for i = 1:lb]
        basis = basis[ind]
    end
    return basis
end

function newton_basis(n, d, supp; e=1e-5, solver="Mosek")
    lsupp = size(supp,2)
    basis = get_basis(n, d)
    lb = size(basis,2)
    A0 = [-1/2*supp' ones(lsupp,1)]
    t = 1
    indexb = [i for i=1:lb]
    temp = sortslices(supp, dims=2)
    while t <= lb
          i = indexb[t]
          if bfind(temp, lsupp, UInt8(2)*basis[:,i]) !== nothing
             t += 1
          else
             if solver == "Mosek"
                model = Model(optimizer_with_attributes(Mosek.Optimizer))
             elseif solver == "SDPT3"
                model = Model(optimizer_with_attributes(SDPT3.Optimizer))
             elseif solver == "SDPNAL"
                model = Model(optimizer_with_attributes(SDPNAL.Optimizer))
             elseif solver == "COSMO"
                model = Model(optimizer_with_attributes(COSMO.Optimizer))
             else
                @error "The solver is currently not supported!"
                return nothing
             end
             set_optimizer_attribute(model, MOI.Silent(), true)
             @variable(model, x[1:n+1], lower_bound=-10, upper_bound=10)
             @constraint(model, [A0; [basis[:,i]' -1]]*x .<= zeros(lsupp+1))
             @objective(model, Min, [basis[:,i]' -1]*x)
             optimize!(model)
             vx = value.(x)
             if abs(objective_value(model)) <= e && sum(abs.(vx)) <= e
                t += 1
             else
                if abs(objective_value(model)) <= e && sum(abs.(vx)) > e
                   t += 1
                else
                   lb -= 1
                   indexb = deleteat!(indexb, t)
                end
                r = t
                while lb >= r
                      j = indexb[r]
                      if [basis[:,j]' -1]*vx <= -e
                         lb -= 1
                         indexb = deleteat!(indexb, r)
                      else
                         r += 1
                      end
                end
             end
          end
    end
    return basis[:,indexb]
end

function generate_basis!(supp, basis)
    supp = sortslices(supp, dims=2)
    supp = unique(supp, dims=2)
    lsupp = size(supp, 2)
    lb = size(basis, 2)
    indexb = UInt32[]
    for i = 1:lb, j = i:lb
        bi = basis[:,i] + basis[:,j]
        if bfind(supp, lsupp, bi) !== nothing
             push!(indexb, i, j)
        end
    end
    sort!(indexb)
    unique!(indexb)
    return basis[:,indexb]
end

function seval(supp, coe, x)
    val = 0
    for i in eachindex(supp)
        temp = isempty(supp[i]) ? 1 : prod(x[supp[i][j]] for j=1:length(supp[i]))
        val += coe[i]*temp
    end
    return val
end

function npolys_info(p, x)
    m = length(p)
    n = length(x)
    dp = zeros(Int, m)
    pcoe = Vector{Vector{Union{Number, AffExpr}}}(undef, m)
    psupp = Vector{Matrix{UInt8}}(undef, m)
    plt = Vector{Int}(undef, m)
    for i = 1:m
        dp[i] = maxdegree(p[i])
        mon = MultivariatePolynomials.monomials(p[i])
        pcoe[i] = MultivariatePolynomials.coefficients(p[i])
        plt[i] = length(mon)
        psupp[i] = zeros(UInt8, n, plt[i])
        for j = 1:plt[i], k = 1:n
            psupp[i][k, j] = MultivariatePolynomials.degree(mon[j], x[k])
        end
    end
    return psupp,pcoe,plt,dp
end

function poly_info(p, x)
    n = length(x)
    mon = MultivariatePolynomials.monomials(p)
    plt = length(mon)
    pcoe = MultivariatePolynomials.coefficients(p)
    psupp = zeros(UInt8, n, plt)
    for j = 1:plt, k = 1:n
        psupp[k, j] = MultivariatePolynomials.degree(mon[j], x[k])
    end
    return psupp,pcoe
end

function polys_info(pop, x; nb=0)
    n = length(x)
    m = length(pop) - 1
    if nb > 0
        gb = x[1:nb].^2 .- 1
        for i in eachindex(pop)
            pop[i] = rem(pop[i], gb)
        end
    end
    coe = Vector{Vector{Union{Number, AffExpr}}}(undef, m+1)
    supp = Vector{Vector{Vector{UInt16}}}(undef, m+1)
    for k = 1:m+1
        mon = MultivariatePolynomials.monomials(pop[k])
        coe[k] = MultivariatePolynomials.coefficients(pop[k])
        lm = length(mon)
        supp[k] = [UInt16[] for i=1:lm]
        for i = 1:lm
            ind = mon[i].z .> 0
            vars = mon[i].vars[ind]
            exp = mon[i].z[ind]
            for j in eachindex(vars)
                l = ncbfind(x, n, vars[j])
                append!(supp[k][i], l*ones(UInt16, exp[j]))
            end
        end
    end
    return n,supp,coe
end

function polys_info(pop, z, n; ctype=ComplexF64)
    coe = Vector{Vector{ctype}}(undef, length(pop))
    supp = Vector{Vector{Vector{Vector{UInt16}}}}(undef, length(pop))
    for k in eachindex(pop)
        mon = MultivariatePolynomials.monomials(pop[k])
        coe[k] = MultivariatePolynomials.coefficients(pop[k])
        lm = length(mon)
        supp[k] = [[[], []] for i=1:lm]
        for i = 1:lm
            ind = mon[i].z .> 0
            vars = mon[i].vars[ind]
            exp = mon[i].z[ind]
            for j in eachindex(vars)
                l = ncbfind(z, 2n, vars[j])
                if l <= n
                    append!(supp[k][i][1], l*ones(UInt16, exp[j]))
                else
                    append!(supp[k][i][2], (l-n)*ones(UInt16, exp[j]))
                end
            end
        end
    end
    return supp,coe
end

function resort(supp, coe; nb=0)
    if nb > 0
        supp = reduce_unitnorm.(supp, nb=nb)
    end
    nsupp = copy(supp)
    sort!(nsupp)
    unique!(nsupp)
    l = length(nsupp)
    ncoe = zeros(typeof(coe[1]), l)
    for i in eachindex(supp)
        locb = bfind(nsupp, l, supp[i])
        ncoe[locb] += coe[i]
    end
    return nsupp,ncoe
end

function divide(a, lead, n, llead)
    return any(j->all(i->lead[i,j]<=a[i], 1:n), 1:llead)
end

function reminder(a, x, gb, n)
    remind = rem(prod(x.^a), gb)
    mon = MultivariatePolynomials.monomials(remind)
    coe = MultivariatePolynomials.coefficients(remind)
    lm = length(mon)
    supp = zeros(UInt8,n,lm)
    for i = 1:lm, j = 1:n
        @inbounds supp[j,i]=MultivariatePolynomials.degree(mon[i],x[j])
    end
    return lm,supp,coe
end

function sign_type(a::Vector{UInt16})
    st = UInt16[]
    if length(a) == 1
        push!(st, a[1])
    elseif length(a) > 1
        r = 1
        for i = 2:length(a)
            if a[i] == a[i-1]
                r += 1
            else
                if isodd(r)
                    push!(st, a[i-1])
                end
                r = 1
            end
        end
        if isodd(r)
            push!(st, a[end])
        end
    end
    return st
end

"""
    p,coe,mon = add_poly!(model, vars, degree)

Generate an unknown polynomial of given degree whose coefficients are from the JuMP `model`.

# Input arguments
- `model`: a JuMP optimization model
- `vars`: set of variables
- `degree`: degree of the polynomial

# Output arguments
- `p`: the polynomial 
- `coe`: coefficients of the polynomial 
- `mon`: monomials of the polynomial 
"""
function add_poly!(model, vars, degree::Int; signsymmetry=false)
    mon = vcat([MultivariatePolynomials.monomials(vars, i) for i = 0:degree]...)
    if signsymmetry != false
        ind = [all(transpose(signsymmetry)*exponents(item) .== 0) for item in mon]
        mon = mon[ind]
    end
    coe = @variable(model, [1:length(mon)])
    p = coe'*mon
    return p,coe,mon
end

function add_poly!(model, vars, supp::Array{UInt8,2})
    mon = [prod(vars.^supp[:,i]) for i = 1:size(supp,2)]
    coe = @variable(model, [1:length(mon)])
    p = coe'*mon
    return p,coe,mon
end

function numele(a)
    return Int(sum(Int.(a).^2+a)/2)
end

"""
    show_blocks(data)

Display the block structure
"""
function show_blocks(data::cpop_data)
    for j = 1:length(data.blocks[1])
        print("block $j: ")
        println([prod(data.x.^data.basis[1][:, data.blocks[1][j][k]]) for k = 1:length(data.blocks[1][j])])
    end
end

function show_blocks(data::mcpop_data)
    for l = 1:data.cql, j = 1:length(data.blocks[l][1])
        print("clique $l, block $j: ")
        println([prod(data.x[data.basis[l][1][data.blocks[l][1][j][k]]]) for k = 1:length(data.blocks[l][1][j])])
    end
end

function complex_to_real(cpop, z)
    n = Int(length(z)/2)
    @polyvar x[1:2n]
    pop = Vector{Polynomial{true, Float64}}(undef, length(cpop))
    for (i,cp) in enumerate(cpop)
        temp = cp(z[1:n]=>x[1:n]+im*x[n+1:2n], z[n+1:2n]=>x[1:n]-im*x[n+1:2n])
        pop[i] = real.(MultivariatePolynomials.coefficients(temp))'*MultivariatePolynomials.monomials(temp)
    end
    return pop,x
end

function cmod(a, m)
    s = mod(a, m)
    return s == 0 ? m : s
end

# generate an SOS polynomial with variables vars and degree 2d
"""
    sos = add_SOS!(model, vars, d)

Generate an SOS polynomial of degree 2d whose coefficients are from the JuMP `model`.

# Input arguments
- `model`: a JuMP optimization model
- `vars`: set of variables
- `d`: half degree of the SOS polynomial

# Output arguments
- `sos`: the sos polynomial 
"""
function add_SOS!(model, vars, d)
    basis = vcat([MultivariatePolynomials.monomials(vars, i) for i = 0:d]...)
    sos = 0
    pos = @variable(model, [1:length(basis), 1:length(basis)], PSD)
    for j = 1:length(basis), k = j:length(basis)
        if j == k
            @inbounds sos += pos[j,k]*basis[j]*basis[k]
        else
            @inbounds sos += 2*pos[j,k]*basis[j]*basis[k]
        end
    end
    return sos
end

# generate an SOS polynomial with monomial `basis`
"""
    sos = add_SOS!(model, basis)

Generate an SOS polynomial with monomial `basis` whose coefficients are from the JuMP `model`.

# Input arguments
- `model`: a JuMP optimization model
- `basis`: monomial basis

# Output arguments
- `sos`: the sos polynomial 
"""
function add_SOS!(model, basis)
    sos = 0
    pos = @variable(model, [1:length(basis), 1:length(basis)], PSD)
    for j = 1:length(basis), k = j:length(basis)
        if j == k
            @inbounds sos += pos[j,k]*basis[j]*basis[k]
        else
            @inbounds sos += 2*pos[j,k]*basis[j]*basis[k]
        end
    end
    return sos
end
