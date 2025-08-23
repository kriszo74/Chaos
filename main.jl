# ---- main.jl ---- 
using GLMakie
using StaticArrays
using GeometryBasics
using Observables  # Observable támogatás

include("3dtools.jl")

# Alap adatszerkezetek

# Source: mozgás és megjelenítési adatok
mutable struct Source
    act_p::SVector{3, Float64}  # aktuális pozíció
    RV::SVector{3, Float64}     # sebesség vektor
    bas_t::Float64              # indulási idő
    positions::Vector{Point3d}   # pozíciók (Point3d)  # később megfontolandó: Observable
    radii::Observable{Vector{Float64}}       # sugarak (Float64)
    birth::Vector{Float64}       # születési idők (Inf = inaktív)  # később megfontolandó: Observable
    color::Symbol               # szín
    alpha::Float64              # áttetszőség
end

# add_source!: forrás hozzáadása és vizuális regisztráció
function add_source!(src::Source)
    push!(sources, src)
    meshscatter!(scene, src.positions;
        markersize = src.radii,
        color = src.color,
        transparency = true,
        alpha = src.alpha)
    return src
end

# Előregenerálás: impulzusok (birth, positions)
function precompute_pulses!(src::Source)
    N = Int(ceil((max_t - src.bas_t) * density))
    t0 = src.bas_t
    src.birth     = Vector{Float64}(undef, N)
    src.positions = Vector{Point3d}(undef, N)
    p0 = src.act_p
    v  = src.RV
    @inbounds for k in 0:N-1
        tk = t0 + k * dt_emit
        src.birth[k+1] = tk
        pk = p0 + v * tk
        src.positions[k+1] = Point3d(pk[1], pk[2], pk[3])
    end
    src.radii[] = fill(0.0, N)
    return N
end

# K-alapú sugárfrissítés
function update_radii!(src::Source, tnow::Float64)
    birth = src.birth
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
    src.radii[] = radii
    return nothing
end

# Fő indítás
fig, scene = setup_scene(; use_axis3=true)
E = 0.1
density = 1.0
dt_emit = 1 / density   # globális emissziós időköz (emisszió független E-től)
max_t = 10.0

sources = Source[]
src = Source(SVector(0.0,0.0,0.0), SVector(0.0,0.0,0.0), 0.0,
             Point3d[], Observable(Float64[]), Float64[], 
             :cyan, 0.1)
precompute_pulses!(src)
add_source!(src)
display(fig)  # ablak megjelenítése
let t = 0.0  # lokális t a ciklushoz
    while isopen(fig.scene) && t < max_t
        tnow = t
        for src in sources
            src.act_p = src.act_p + src.RV * E  # p(n+1) = p(n) + RV * E
            update_radii!(src, tnow)         # sugárfrissítés
        end
        t = tnow + E
        sleep(E)
    end
end
if isopen(fig.scene)
    wait(fig.scene)  # nyitva marad, amíg be nem zárod
end
