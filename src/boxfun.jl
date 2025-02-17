"""
    BoxFun(partition, vals)

Discretization of a measure over the domain `partition.domain`,
as a piecewise constant function over the boxes of `partition`. 
    
Implemented as a sparse vector over the indices of `partition`. 

Constructors:
* BoxFun with constant weight 1 of Type `T` (default Float64) 
supported over a `BoxSet` `B`:
```julia
μ = BoxFun(B, T)
```
* BoxFun with specified weights per key
```julia
P = B.partition
weights = Dict( key => 1 for key in keys(B) )
BoxFun(P, weights)
```
* BoxFun with vector of weights supportted over a `BoxSet` `B`: 
```julia
weights = rand(length(B))
μ = BoxFun(B, weights)
```
(Note that since `Boxset`s do not have a deterministic iteration 
order by default, this may have unintented results. This 
constructor should therefore only be used with 
`BoxSet{<:Any, <:Any, <:OrderedSet}` types)

Fields:
* `partition`: An `AbstractBoxPartition` whose indices are used 
for `vals`
* `vals`: A dictionary whose keys are the box indices from 
`partition`, and whose values represent the values of the function. 

Methods implemented:

    length, sum, iterate, values, isapprox, ∘, LinearAlgebra.norm, LinearAlgebra.normalize!


"""
struct BoxFun{B,K,V,P<:AbstractBoxPartition{B},D<:AbstractDict{K,V}} <: AbstractVector{V}
    partition::P
    vals::D
end

BoxFun(boxset::BoxSet, vals, dicttype=OrderedDict) = BoxFun(boxset.partition, dicttype(zip(boxset.set, vals)))
BoxFun(boxset::BoxSet, T::Type, dicttype=OrderedDict) = BoxFun(boxset.partition, dicttype(key=>one(T) for key in boxset.set))
BoxFun(boxset::BoxSet{B}) where {N,T,B<:Box{N,T}} = BoxFun(boxset, T)
BoxFun(boxfun::BoxFun, vals, dicttype=OrderedDict)= BoxFun(boxfun.partition, dicttype(zip( keys(boxfun), vals )))

BoxSet(boxfun::BoxFun; settype=OrderedSet) = BoxSet(boxfun.partition, settype(keys(boxfun)))

Base.Dict(boxfun::BoxFun) = Dict( zip( keys(boxfun), values(boxfun) ) )
OrderedCollections.OrderedDict(boxfun::BoxFun) = OrderedDict( zip( keys(boxfun), values(boxfun) ) )

box_pairs(fun::BoxFun) = (key_to_box(fun.partition, key) => weight for (key,weight) in fun.vals)

Core.@doc raw"""
    sum(f, μ::BoxFun)
    sum(f, μ::BoxFun, B::BoxSet)
    μ(B) = sum(x->1, μ, B)

Integrate a function `f` with respect to the measure `μ`, that is,
if `boxfun` is the discretization of a measure ``\mu`` over the domain 
``Q``, then approximate the value of 
```math
\int_Q f \, d\mu .
```
If a BoxSet `B` is passed as the third argument, then the 
integration is restricted to the boxes in `B`
```math
\int_{Q \cap \bigcup_{b \in B} b} f \, d\mu .
```
The notation `μ(B)` is offered to compute 
``\mu (\bigcup_{b \in B} b)``. 
"""
function Base.sum(f, boxfun::BoxFun{B,K,V,P,D}; init...) where {B,K,V,P,D}
    sum(box_pairs(boxfun); init...) do pair
        box, val = pair
        f(box.center) * volume(box) * val
    end
end

function Base.sum(f, boxfun::BoxFun{B,K,V,P,D}, boxset::Union{Box,BoxSet}; init...) where {B,K,V,P,D}
    support = cover(boxfun.partition, boxset)
    boxfun_new = BoxFun(
        boxfun.partition, 
        D((key=>val) for (key,val) in boxfun.vals if key in support.set)
    )
    sum(f, boxfun_new; init...)
end

(boxfun::BoxFun)(boxset::Union{Box,BoxSet}) = sum(_->1, boxfun, boxset)

function Base.show(io::IO, g::BoxFun)
    print(io, "BoxFun in $(g.partition) with $(length(g.vals)) stored weights")
end

Base.length(fun::BoxFun) = length(fun.vals)
Base.size(fun::BoxFun) = (length(fun),)
Base.keytype(::BoxFun{B,K,V}) where {B,K,V} = K
Base.eltype(::BoxFun{B,K,V}) where {B,K,V} = V
Base.keys(fun::BoxFun) = keys(fun.vals)
Base.values(fun::BoxFun) = values(fun.vals)
Base.pairs(fun::BoxFun) = pairs(fun.vals)
Base.show(io::IO, ::MIME"text/plain", fun::BoxFun) = show(io, fun)
Base.maximum(fun::BoxFun) = maximum(values(fun))
Base.minimum(fun::BoxFun) = minimum(values(fun))

function Base.iterate(boxfun::BoxFun, i...)
    itr = iterate(boxfun.vals, i...)
    isnothing(itr) && return itr
    ((key, val), j) = itr
    box = key_to_box(boxfun.partition, key)
    ((box => val), j)
end

LinearAlgebra.norm(boxfun::BoxFun) = (sqrt ∘ sum)((volume(box)*abs2(val) for (box,val) in boxfun))

function LinearAlgebra.normalize!(boxfun::BoxFun)
    λ = inv(norm(boxfun))
    map!(x -> λ*x, values(boxfun.vals))
    boxfun
end

Base.getindex(boxfun::BoxFun{B,K,V}, key::Vararg{<:Integer,N}) where {N,B<:Box{N},K,V} = get(boxfun.vals, key, zero(V))
Base.getindex(boxfun::BoxFun{B,K,V}, key::L) where {N,B<:Box{N},K,V,L<:Union{<:CartesianIndex{N},<:SVNT{N}}} = get(boxfun.vals, key, zero(V))
Base.setindex!(boxfun::BoxFun{B}, val, key::Vararg{<:Integer,N}) where {N,B<:Box{N}} = setindex!(boxfun.vals, val, key)
Base.setindex!(boxfun::BoxFun{B}, val, key::L) where {N,B<:Box{N},L<:Union{<:CartesianIndex{N},<:SVNT{N}}} = setindex!(boxfun.vals, val, key)
Base.fill!(boxfun::BoxFun, val) = (for key in keys(boxfun); boxfun[key] = val; end; boxfun)
Base.sizehint!(boxfun::BoxFun, sz) = sizehint!(boxfun.vals, sz)
Base.copy(boxfun::BoxFun) = BoxFun(boxfun.partition, copy(boxfun.vals))
Base.deepcopy(boxfun::BoxFun) = BoxFun(boxfun.partition, deepcopy(boxfun.vals))
SparseArrays.findnz(boxfun::BoxFun) = (collect(keys(boxfun)), collect(values(boxfun)))

"""
    marginal(μ::BoxFun{Box{N}}; dim) -> BoxFun{Box{N-1}}

Compute the marginal distribution of μ along an axis given
by its dimension `dim`. 
"""
function marginal(μ⁺::BoxFun; dim)
    support = marginal(BoxSet(μ⁺); dim=dim)
    μ = 0.0*BoxFun(support, eltype(μ⁺))

    for key⁺ in keys(μ⁺)
        key = tuple_deleteat(key⁺, dim)
        box = key_to_box(μ.partition, key)
        box⁺ = key_to_box(μ⁺.partition, key⁺)
        μ[key] += μ⁺[key⁺]*volume(box⁺)/volume(box)
    end

    return μ
end

Core.@doc raw"""
    density(μ::BoxFun) -> Function

Return the measure `μ` as a callable density `g`, i.e.
```math
\int f(x) \, d\mu (x) = \int f(x)g(x) \, dx . 
```
"""
function density(μ::BoxFun)
    P = μ.partition
    function eval_density(x)
        xi = point_to_key(P, x)
        b = key_to_box(P, xi)
        return μ[xi] / volume(b)
    end
end

function Base.isapprox(
        l::BoxFun{B,K,V}, r::BoxFun{R,J,W}; 
        atol=0, rtol=Base.rtoldefault(V,W,atol), kwargs...
    ) where {B,K,V,R,J,W}
    
    l === r && return true
    atol_used = max(atol, rtol * max(norm(values(l)), norm(values(r))))
    for key in (keys(l) ∪ keys(r))
        isapprox(l[key], r[key]; atol=atol_used, rtol=rtol, kwargs...) || return false
    end
    return true
end

function Base.:(==)(l::BoxFun{B,K,V}, r::BoxFun{R,J,W}) where {B,K,V,R,J,W}
    l === r && return true
    for key in (keys(l) ∪ keys(r))
        l[key] == r[key] || return false
    end
    return true
end

gen_type(d::AbstractDict{K,V}, f) where {K,V} = Dict{K,(typeof ∘ f ∘ first ∘ values)(d)}
gen_type(d::OrderedDict{K,V}, f) where {K,V} = OrderedDict{K,(typeof ∘ f ∘ first ∘ values)(d)}

"""
    ∘(f, boxfun::BoxFun) -> BoxFun
    ∘(boxfun::BoxFun, F::BoxMap) -> BoxFun

Postcompose the function `f` with the `boxfun`,
or precompose a BoxMap `F` with the `boxfun` 
(by applying the Koopman operator). Note that 
the support of `BoxFun` must be forward-invariant
under `F`. 
"""
function ∘(f, boxfun::BoxFun)
    D = gen_type(boxfun.vals, f)
    BoxFun(
        boxfun.partition, 
        D(key => f(val) for (key,val) in boxfun.vals)
    )
end

function ∘(boxfun::BoxFun, F::BoxMap)
    T = TransferOperator(F, BoxSet(boxfun))
    T'boxfun
end

Base.:(*)(a::Number, boxfun::BoxFun) = (x -> x*a) ∘ boxfun
Base.:(*)(boxfun::BoxFun, a::Number) = (x -> x*a) ∘ boxfun
Base.:(/)(boxfun::BoxFun, a::Number) = (x -> x/a) ∘ boxfun
Base.:(-)(b::BoxFun) = -1 * b
Base.:(-)(b1::BoxFun, b2::BoxFun) = b1 + (-b2)

function Base.:(+)(b1::BoxFun, b2::BoxFun)
    b1.partition == b2.partition || throw(DomainError("Partitions of BoxFuns do not match."))

    v1 = first(values(b1))
    D = gen_type(b2.vals, x -> x + v1)
    b = BoxFun(b1.partition, D())

    sizehint!(b, max(length(b1), length(b2)))
    for key in (keys(b1) ∪ keys(b2))
        b[key] = b1[key] + b2[key]
    end

    return b
end
