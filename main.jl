# ---- main.jl ----
using GLMakie
using StaticArrays
using GeometryBasics
using Observables      # Observable támogatás

include("3dtools.jl")

# ============================
# ÚJ ARCHITEKTÚRA
# Cél: minden adat a Source-ban / Modelben legyen kapszulázva
# ============================

# -- Szimulációs modell tartó --
mutable struct PulsePool
    positions::Observable{Vector{Point3d}}   # aktív/üres slotok pozíciói (Float64)
    radii::Observable{Vector{Float64}}       # megjelenített sugarak (Float64)
    birth::Observable{Vector{Float64}}       # születési idők (Inf = szabad slot)
end

function PulsePool(max::Int)
    PulsePool(
        Observable(fill(Point3d(0, 0, 0), max)),
        Observable(fill(0.0, max)),
        Observable(fill(Inf, max)),
    )
end

mutable struct Source
    act_p::SVector{3, Float64}  # aktuális pozíció (számítás: Float64)
    RV::SVector{3, Float64}     # sebesség vektor
    bas_t::Float64              # indulási idő (jövőbeli használatra)
    pool::PulsePool             # saját pulzus-pool
    color::Symbol               # megjelenítési szín
    alpha::Float64              # áttetszőség
end

function Source(; pos=SVector(0.0,0.0,0.0), vel=SVector(0.0,0.0,0.0), start_t=0.0,
                 color::Symbol=:cyan, alpha::Float64=0.1)
    Source(pos, vel, start_t, PulsePool(0), color, alpha)
end

mutable struct Model
    fig
    scene
    sources::Vector{Source}
    t::Observable{Float64}
    E::Float64
    density::Float64
    max_t::Float64
end

function Model(; E=0.1, density=1.0, max_t=10.0)
    fig, scene = setup_scene(; use_axis3=true)
    Model(fig, scene, Source[], Observable(0.0), E, density, max_t)
end

# -- Vizuális regisztráció forrásonként --
function register_visual!(scene, src::Source)
    meshscatter!(scene, src.pool.positions;
        markersize = src.pool.radii,
        color = src.color,
        transparency = true,
        alpha = src.alpha)
end

function add_source!(m::Model, src::Source)
    push!(m.sources, src)
    register_visual!(m.scene, src)
    return src
end

# -----------------------------------------------------------------------------
# ÚJ MÓDSZER (elszigetelt): előregenerált impulzusok (birth_times, positions)
# -----------------------------------------------------------------------------
function precompute_pulses!(src::Source; E::Float64=0.1, max_t::Float64=10.0, density::Int=1)
    @assert density >= 1
    # N = ceil((max_t - bas_t) * density / E)
    N = Int(max(0, ceil((max_t - src.bas_t) * density / E)))
    if N == 0
        src.pool.positions[] = Point3d[]
        src.pool.radii[]     = Float64[]
        src.pool.birth[]     = Float64[]
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
    src.pool.positions[] = pos
    src.pool.radii[]     = fill(0.0, N)
    src.pool.birth[]     = birth
    return N
end



function update_radii!(src::Source, E::Float64, tnow::Float64)
    birth = src.pool.birth[]
    radii = src.pool.radii[]
    @inbounds for i in eachindex(birth)
        b = birth[i]
        radii[i] = isfinite(b) ? max(0.0, E * (tnow - b)) : 0.0
    end
    src.pool.radii[] = radii  # ping
    return nothing
end

function step!(src::Source, E::Float64, tnow::Float64)
    # pozícióléptetés
    src.act_p = src.act_p + src.RV * E  # p(n+1) = p(n) + RV * E
    # nincs új aktiválás: birth_times/positions előre generálva
    update_radii!(src, E, tnow)  # láthatóvá teszi azokat, ahol tnow >= birth
    return nothing
end

function run!(m::Model)
    # Szinkron futás: a főszál blokkol, amíg tart az animáció vagy be nem zárják az ablakot
    while isopen(m.fig.scene) && m.t[] < m.max_t
        tnow = m.t[]
        for src in m.sources
            step!(src, m.E, tnow)
        end
        m.t[] = tnow + m.E
        sleep(m.E)
    end
    return m
end

# ============================
# FŐ INDÍTÁS (scriptként futtatva)
# ============================
m = Model(; E=0.1, density=1.0, max_t=10.0)
src = Source(; pos=SVector(0.0,0.0,0.0), vel=SVector(0.0,0.0,0.0), start_t=0.0,
               color=:cyan, alpha = 0.1)
precompute_pulses!(src; E=m.E, max_t=m.max_t, density=Int(m.density))
add_source!(m, src)
display(m.fig)  # a window élettartama ne a run! életciklusához kötődjön
run!(m)
if isopen(m.fig.scene)
    wait(m.fig.scene)  # tartsd nyitva az ablakot, amíg a felhasználó be nem zárja
end