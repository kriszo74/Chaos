# ---- main.jl ----
using GLMakie
using StaticArrays
using GeometryBasics
using Observables  # Observable támogatás

include("3dtools.jl")

# Architektúra: adatok kapszulázása Source/Model-ben


# Source: mozgás + saját pool + megjelenítési paraméterek
mutable struct Source
    act_p::SVector{3, Float64}  # aktuális pozíció
    RV::SVector{3, Float64}     # sebesség vektor
    bas_t::Float64              # indulási idő
    positions::Observable{Vector{Point3d}}   # pozíciók (Point3d)
    radii::Observable{Vector{Float64}}       # sugarak (Float64)
    birth::Observable{Vector{Float64}}       # születési idők (Inf = inaktív)
    color::Symbol               # szín
    alpha::Float64              # áttetszőség
end




# add_source! – WHY: egységes API, vizuál regisztráció inline
function add_source!(scene, sources::Vector{Source}, src::Source)
    push!(sources, src)
    meshscatter!(scene, src.positions;
        markersize = src.radii,
        color = src.color,
        transparency = true,
        alpha = src.alpha)
    return src
end

# Előregenerálás: birth_times és positions
function precompute_pulses!(src::Source; E::Float64=0.1, max_t::Float64=10.0, density::Int=1)
    @assert density >= 1
    # N = ceil((max_t - bas_t) * density / E)
    N = Int(max(0, ceil((max_t - src.bas_t) * density / E)))
    if N == 0
        src.positions[] = Point3d[]
        src.radii[]     = Float64[]
        src.birth[]     = Float64[]
        return 0
    end
    dt_emit = E / density
    t0 = src.bas_t
    birth = Vector{Float64}(undef, N)
    pos   = Vector{Point3d}(undef, N)
    p0 = src.act_p
    v  = src.RV
    @inbounds for k in 0:N-1
        tk = t0 + k * dt_emit
        birth[k+1] = tk
        pk = p0 + v * tk
        pos[k+1] = Point3d(pk[1], pk[2], pk[3])
    end
    src.positions[] = pos
    src.radii[]     = fill(0.0, N)
    src.birth[]     = birth
    return N
end

# K-alapú sugárfrissítés
function update_radii!(src::Source, E::Float64, tnow::Float64)
    birth = src.birth[]
    radii = src.radii[]
    N = length(birth)
    # K: eddig megszületett impulzusok száma (t == bas_t → K = 0)
    K = clamp(floor(Int, (tnow - src.bas_t)/E), 0, N)
    @inbounds begin
        for i in 1:K
            radii[i] = max(0.0, E * (tnow - birth[i]))
        end
        if K < N
            fill!(view(radii, K+1:N), 0.0)  # a többinek 0 marad
        end
    end
    src.radii[] = radii  # ping
    return nothing
end


# Model nélküli futtató // WHY: egyszerűbb futtatás Model nélkül
function run!(fig, scene, sources::Vector{Source}, E::Float64, max_t::Float64)
    t = 0.0  # WHY: lokális idő, nem Observable
    while isopen(fig.scene) && t < max_t
        tnow = t
        for src in sources
            src.act_p = src.act_p + src.RV * E  # p(n+1) = p(n) + RV * E
            update_radii!(src, E, tnow)         # WHY: sugárfrissítés
        end
        t = tnow + E
        sleep(E)
    end
    return nothing
end

# Fő indítás – Model nélkül (aktív)
fig, scene = setup_scene(; use_axis3=true)
E = 0.1
density = 1.0
max_t = 10.0

sources = Source[]
src = Source(SVector(0.0,0.0,0.0), SVector(0.0,0.0,0.0), 0.0,
             Observable(Point3d[]), Observable(Float64[]), Observable(Float64[]),
             :cyan, 0.1)  # WHY: kulcsszavas ctor kivezetéséhez
precompute_pulses!(src; E=E, max_t=max_t, density=Int(density))
add_source!(scene, sources, src)  # WHY: egységes add_source API
display(fig)  # az ablak életciklusa ne a run!-hoz kötődjön
run!(fig, scene, sources, E, max_t)
if isopen(fig.scene)
    wait(fig.scene)  # nyitva marad, amíg be nem zárod
end
