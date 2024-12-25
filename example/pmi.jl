using DynamicPolynomials
using TSSOS
using LinearAlgebra
using Random

## Inf mineig(F(x)) s.t. G1(x) >= 0, ..., Gm(x) >= 0
@polyvar x[1:2]
Q = [1/sqrt(2) -1/sqrt(3) 1/sqrt(6); 0 1/sqrt(3) 2/sqrt(6); 1/sqrt(2) 1/sqrt(3) -1/sqrt(6)]
F = Q*[-x[1]^2-x[2]^2 0 0; 0 -1/4*(x[1]+1)^2-1/4*(x[2]-1)^2 0; 0 0 -1/4*(x[1]-1)^2-1/4*(x[2]+1)^2]*Q'
G = [1-4x[1]*x[2] x[1]; x[1] 4-x[1]^2-x[2]^2]
opt,data = tssos_first(F, [G], x, 3, TS=false, QUIET=true)
# opt,data = tssos_higher!(data)

@polyvar x[1:2]
F = [x[1]^2 x[1]+x[2]; x[1]+x[2] x[2]^2]
G = [1-x[1]^2-x[2]^2]
opt,data = tssos_first(F, G, x, 2, TS=false, Gram=true, Mommat=true, QUIET=true)

## polynomial matrix optimization with term sparsity
@polyvar x[1:5]
F = [x[1]^4 x[1]^2-x[2]*x[3] x[3]^2-x[4]*x[5] x[1]*x[4] x[1]*x[5];
x[1]^2-x[2]*x[3] x[2]^4 x[2]^2-x[3]*x[4] x[2]*x[4] x[2]*x[5];
x[3]^2-x[4]*x[5] x[2]^2-x[3]*x[4] x[3]^4 x[4]^2-x[1]*x[2] x[5]^2-x[3]*x[5];
x[1]*x[4] x[2]*x[4] x[4]^2-x[1]*x[2] x[4]^4 x[4]^2-x[1]*x[3];
x[1]*x[5] x[2]*x[5] x[5]^2-x[3]*x[5] x[4]^2-x[1]*x[3] x[5]^4]
G = Vector{Matrix{Polynomial{true, Int}}}(undef, 2)
G[1] = [1-x[1]^2-x[2]^2 x[2]*x[3]; x[2]*x[3] 1-x[3]^2]
G[2] = [1-x[4]^2 x[4]*x[5]; x[4]*x[5] 1-x[5]^2]
@time opt,data = tssos_first(F, G, x, 3, TS="MD", QUIET=true, Mommat=false)
@time opt,data = tssos_higher!(data, TS="MD", QUIET=true)
println(maximum(maximum.([maximum.(data.blocksize[i]) for i = 1:data.cql])))


## polynomial matrix optimization with term sparsity
Random.seed!(1)
@polyvar x[1:3]
p = 60
A = rand(p, p)
A = (A+A')/2
B = rand(p, p)
B = (B+B')/2
F = (1-x[1]^2-x[2]^2)*I(p) + (x[1]^2-x[3]^2)*A + (x[1]^2*x[3]^2-2x[2]^2)*B
G = [1-x[1]^2-x[2]^2 x[2]*x[3]; x[2]*x[3] 1-x[3]^2]
r = 2
@time opt,data = tssos_first(F, [G], x, r, TS="block", QUIET=true)
@time opt,data = tssos_higher!(data, TS="block", QUIET=true)
@time opt,data = tssos_first(F, [G], x, r, TS="MD", QUIET=true)
@time opt,data = tssos_higher!(data, TS="MD", QUIET=true)
@time opt,data = tssos_first(F, [G], x, r, TS=false, QUIET=true)
# println(maximum(maximum.([maximum.(data.blocksize[i]) for i = 1:data.cql])))


## Inf b'*λ s.t. F0 + λ1*F1 + ... λt*Ft >=0 on {x ∈ R^n | G1(x) >= 0, ..., Gm(x) >= 0}
## polynomial matrix optimization with term sparsity
@polyvar x[1:3]
F = Vector{Matrix{Polynomial{true, Int}}}(undef, 3)
F[1] = sum(x.^2)*[x[2]^4 0 0; 0 x[3]^4 0; 0 0 x[1]^4]
F[2] = sum(x.^2)*[0 x[1]^2*x[2]^2 0; x[1]^2*x[2]^2 0 0; 0 0 0]
F[3] = sum(x.^2)*[x[1]^4 0 0; 0 x[2]^4 x[2]^2*x[3]^2; 0 x[2]^2*x[3]^2 x[3]^4]
G = [1 - sum(x.^2)]
@time opt,data = LinearPMI_first([-10, 1], F, G, x, 3, TS="block", QUIET=true)
@time opt,data = LinearPMI_higher!(data, TS="block", QUIET=true)


## polynomial matrix optimization with correlative sparsity
@polyvar x[1:2]
F = [2 0; 0 0]*(x[1]-1)^2 + [0 0; 0 2]*(x[1]-2)^2 + [1 -1; -1 1]*(x[2]-1)^2 + [1 1; 1 1]*(x[2]-2)^2
G = [4 - x[1]^2, 4 - x[2]^2, x[1]^2 - 2.25, 2.25 - x[1]^2]
d = 2
opt,data = cs_tssos_first(F, G, x, d, TS=false, QUIET=true, Mommat=true)
sol = extract_solutions_pmo(1, 2, 2, data.moment[2])
W = extract_weight_matrix(1, 2, 2, sol, data.moment[2])
sol = extract_solutions_robust_pmo(2, d, 2, data.moment[1])

@polyvar x[1:3]
Q = [1/sqrt(2) -1/sqrt(3) 1/sqrt(6); 0 1/sqrt(3) 2/sqrt(6); 1/sqrt(2) 1/sqrt(3) -1/sqrt(6)]
F = (-x[1]^2 + x[2])*(Q[:,1]*Q[:,1]'+Q[:,2]*Q[:,2]') + (x[2]^2 + x[3]^2)*Q[:,3]*Q[:,3]'
G = [1 - x[1]^2 - x[2]^2, 1 - x[2]^2 - x[3]^2, -1 + x[2]^2 + x[3]^2]
opt,data = cs_tssos_first(F, G, x, 2, TS=false, QUIET=true, Mommat=true)
sol = extract_solutions_pmo(2, 2, 3, data.moment[2])
W = extract_weight_matrix(2, 2, 3, sol, data.moment[2])
sol = extract_solutions_robust_pmo(4, 3, 3, data.moment[1])


## polynomial matrix optimization with correlative sparsity
@polyvar x[1:5]
F = [x[1]^4 x[1]^2-x[2]*x[3] x[3]^2-x[4]*x[5] 0.5 0.5;
x[1]^2-x[2]*x[3] x[2]^4 x[2]^2-x[3]*x[4] 0.5 0.5;
x[3]^2-x[4]*x[5] x[2]^2-x[3]*x[4] x[3]^4 x[4]^2-x[1]*x[2] x[5]^2-x[3]*x[4];
0.5 0.5 x[4]^2-x[1]*x[2] x[4]^4 x[4]^2-x[1]*x[3];
0.5 0.5 x[5]^2-x[3]*x[4] x[4]^2-x[1]*x[3] x[5]^4]
G = Vector{Matrix{Polynomial{true, Int}}}(undef, 2)
G[1] = [1-x[1]^2-x[2]^2 x[2]*x[3]; x[2]*x[3] 1-x[3]^2]
G[2] = [1-x[4]^2 x[4]*x[5]; x[4]*x[5] 1-x[5]^2]
r = 2
@time opt,data = tssos_first(F, G, x, r, TS=false, QUIET=true, Mommat=true)
@time opt,data = cs_tssos_first(F, G, x, r, TS=false, QUIET=true, Mommat=true)
@time opt,data = cs_tssos_first(F, G, x, r, TS="block", QUIET=true, Mommat=false)
@time opt,data = cs_tssos_higher!(data, TS="block", QUIET=true)
@time opt,data = cs_tssos_first(F, G, x, r, TS="MD", QUIET=true, Mommat=false)
println(maximum(maximum.([maximum.(data.blocksize[i]) for i = 1:data.cql])))


## polynomial matrix optimization with correlative sparsity
n = 5
r = 2
@polyvar x[1:n]
F = [sum(x[k]^2 for k = 1:n-2) sum(x[k]*x[k+1] for k = 1:n-1) 1.0;
sum(x[k]*x[k+1] for k = 1:n-1) sum(x[k]^2 for k = 2:n-1)  sum(x[k]*x[k+2] for k = 1:n-2);
1 sum(x[k]*x[k+2] for k = 1:n-2) sum(x[k]^2 for k = 3:n)]
G = Vector{Matrix{Polynomial{true, Float64}}}(undef, n-2)
for k = 1:n-2
    G[k] = [1-x[k]^2-x[k+1]^2 x[k+1]+0.5; x[k+1]+0.5 1-x[k+2]^2]
end
@time opt,data = tssos_first(F, G, x, r, TS=false, QUIET=true, Mommat=true)
@time opt,data = cs_tssos_first(F, G, x, r, TS=false, QUIET=true, Mommat=true)
@time opt,data = cs_tssos_first(F, G, x, r, TS="block", QUIET=true, Mommat=false)
@time opt,data = cs_tssos_first(F, G, x, r, TS="MD", QUIET=true, Mommat=false)
# println(maximum(maximum.([maximum.(data.blocksize[i]) for i = 1:data.cql])))


## polynomial matrix optimization with matrix sparsity
@polyvar x[1:5]
F = [x[1]^4 x[1]^2-x[2]*x[3] x[3]^2-x[4]*x[5] 0 0;
x[1]^2-x[2]*x[3] x[2]^4 x[2]^2-x[3]*x[4] 0 0;
x[3]^2-x[4]*x[5] x[2]^2-x[3]*x[4] x[3]^4 x[4]^2-x[1]*x[2] x[5]^2-x[3]*x[4];
0 0 x[4]^2-x[1]*x[2] x[4]^4 x[4]^2-x[1]*x[3];
0 0 x[5]^2-x[3]*x[4] x[4]^2-x[1]*x[3] x[5]^4]
G = Vector{Matrix{Polynomial{true, Float64}}}(undef, 2)
G[1] = [1-x[1]^2-x[2]^2 x[2]*x[3]; x[2]*x[3] 1-x[3]^2]
G[2] = [1-x[4]^2 x[4]*x[5]; x[4]*x[5] 1-x[5]^2]
@time opt,data = tssos_first(F, G, x, 4, TS=false, QUIET=true)
r = 2
@time opt,mb = sparseobj(F, G, x, r, TS=false, QUIET=true)
@time opt,mb = sparseobj(F, G, x, r, TS="block", QUIET=true)
@time opt,mb = sparseobj(F, G, x, r, TS="MD", QUIET=true)


## polynomial matrix optimization with matrix sparsity
@polyvar x[1:5]
F = [x[1]^4+x[2]^4+1 x[1]*x[3]; x[1]*x[3] x[3]^4+x[4]^4+x[5]^4+0.5]
G = Vector{Matrix{Polynomial{true, Float64}}}(undef, 1)
G[1] = [1-x[1]^2 x[1]*x[2] x[1]*x[3] 0 0; x[1]*x[2] 1-x[2]^2 x[2]*x[3] 0 0; x[1]*x[3] x[2]*x[3] 1-x[3]^2 x[3]*x[4] x[3]*x[5]; 0 0 x[3]*x[4] 1-x[4]^2 x[4]*x[5]; 0 0 x[3]*x[5] x[4]*x[5] 1-x[5]^2]
@time opt,data = tssos_first(F, G, x, 4, TS=false, QUIET=true)

@polyvar x[1:6]
F = [x[1]^4+x[2]^4+1 x[1]*x[3]; x[1]*x[3] x[3]^4+x[4]^4+x[5]^4+0.5]
G = Vector{Matrix{Polynomial{true, Float64}}}(undef, 2)
G[1] = [1-x[1]^2 x[1]*x[2] x[1]*x[3]; x[1]*x[2] 1-x[2]^2 x[2]*x[3]; x[1]*x[3] x[2]*x[3] x[6]^2]
G[2] = [1-x[3]^2-x[6]^2 x[3]*x[4] x[3]*x[5]; x[3]*x[4] 1-x[4]^2 x[4]*x[5]; x[3]*x[5] x[4]*x[5] 1-x[5]^2]
r = 4
@time opt,data = cs_tssos_first(F, G, x, r, TS=false, QUIET=true)
@time opt,data = cs_tssos_first(F, G, x, r, TS="block", QUIET=true)
@time opt,data = cs_tssos_first(F, G, x, r, TS="MD", QUIET=true)


## polynomial matrix optimization with matrix sparsity
n = 5
@polyvar x[1:2n-2]
F = [1 x[1]*x[2]; x[1]*x[2] 1+x[n]^2]
G = Vector{Matrix{Polynomial{true, Float64}}}(undef, n-1)
G[1] = [1-x[1]^4 x[1]*x[2]; x[1]*x[2] x[n+1]^2]
for k = 2:n-2
    G[k] = [1-x[k]^4 x[k]*x[k+1]; x[k]*x[k+1] x[n+k]^2-x[n+k-1]^2]
end
G[n-1] = [1-x[n-1]^4 x[n-1]*x[n]; x[n-1]*x[n] 1-x[n]^4-x[2n-2]^2]
@time opt,data = cs_tssos_first(F, G, x, 4, TS=false, QUIET=true)
@time opt,data = cs_tssos_first(F, G, x, 4, TS="block", QUIET=true)
@time opt,data = cs_tssos_first(F, G, x, 4, TS="MD", QUIET=true)

n = 7
@polyvar x[1:n]
F = [1 x[1]*x[2]; x[1]*x[2] 1+x[n]^2]
G = Matrix{Polynomial{true, Float64}}(undef, n, n)
for i = 1:n, j = 1:n
    G[i,j] = 0
end
for k = 1:n
    G[k,k] = 1-x[k]^4
end
for k = 1:n-1
    G[k,n] = G[n,k] = x[k]*x[k+1]
end
@time opt,data = tssos_first(F, [G], x, 4, TS=false, QUIET=true)


## polynomial matrix optimization with matrix sparsity
@polyvar x[1:3]
p = 10
mul = sum(x.^2)^3
F = Vector{Matrix{Polynomial{true, Int}}}(undef, 3)
F[1] = zeros(3p, 3p)
F[2] = zeros(3p, 3p)
F[3] = zeros(3p, 3p)
for i = 1:p
    F[1][3*(i-1)+1,3*(i-1)+1] = mul*x[2]^4
    F[1][3*(i-1)+2,3*(i-1)+2] = mul*x[3]^4
    F[1][3*(i-1)+3,3*(i-1)+3] = mul*x[1]^4
    F[3][3*(i-1)+1,3*(i-1)+1] = mul*x[1]^4
    F[3][3*(i-1)+2,3*(i-1)+2] = mul*x[2]^4
    F[3][3*(i-1)+3,3*(i-1)+3] = mul*x[3]^4
end
for i = 2:2:3p
    if mod(i, 3) == 2
        F[2][i,i-1] = F[2][i-1,i] = mul*x[1]^2*x[2]^2
    elseif mod(i, 3) == 0
        F[2][i,i-1] = F[2][i-1,i] = mul*x[2]^2*x[3]^2
    else
        F[2][i,i-1] = F[2][i-1,i] = mul*x[1]^2*x[3]^2
    end
end
for i = 3:2:3p-1
    if mod(i, 3) == 2
        F[3][i,i-1] = F[3][i-1,i] = mul*x[1]^2*x[2]^2
    elseif mod(i, 3) == 0
        F[3][i,i-1] = F[3][i-1,i] = mul*x[2]^2*x[3]^2
    else
        F[3][i,i-1] = F[3][i-1,i] = mul*x[1]^2*x[3]^2
    end
end
@time opt,mb = sparseobj([-10, 1], F, [], x, 5, TS="block", QUIET=true)
@time opt,mb = sparseobj([-10, 1], F, [], x, 5, TS=false, QUIET=true)


n = 3
@polyvar x[1:n]
Q = [sqrt(1/2) -sqrt(1/3) sqrt(1/6); 0 sqrt(1/3) sqrt(2/3); sqrt(1/2) sqrt(1/3) -sqrt(1/6)]
f1 = sum((x.-1).^2)/(n*(sqrt(1/2)-1)^2)
f2 = sum((x[i]-x[i+1])^2 for i = 1:n-1) + 2
f3 = sum((x[i]+x[i+1])^2 for i = 1:n-1) + 2 
F = Q*Diagonal([f1, f2, f3])*Q'
G = [[1-x[i]^2 x[i]*x[i+1]; x[i]*x[i+1] 1-x[i+1]^2] for i = 1:n-1]
@time opt,data = cs_tssos_first(F, G, x, 1, TS=false, QUIET=true, Mommat=true)
sol = extract_solutions_pmo(n, 2, 3, data.moment[1])


## Extract solutions
n = 2
@polyvar x[1:n]
F = [x[1]^4+1 x[1]*x[2]; x[1]*x[2] x[2]^4+1]
G = [1 - sum(x.^2)]
@time opt,data = tssos_first(F, G, x, 2, TS=false, QUIET=true, Mommat=true)
sol = extract_solutions_pmo(n, 2, 2, data.moment[1])
