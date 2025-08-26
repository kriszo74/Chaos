# ---- main.jl ---- 
using GLMakie
using StaticArrays
using GeometryBasics
using Observables  # Observable támogatás

const DEBUG_MODE = get(ENV, "APP_DEBUG", "0") == "1"  # set APP_DEBUG=1 -> debug
@info "DEBUG_MODE" DEBUG_MODE

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
        tk = t0 + k / density  # dt_emit helyett
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
    K = ceil(Int, (tnow - src.bas_t) * density)  # Aktív impulzusok száma az adott időpillanatban
    @inbounds begin
        for i in 1:K
            radii[i] = (tnow - birth[i])  # eltelt idő az i. impulzus óta
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
max_t = 10.0

sources = Source[]
src = Source(SVector(0.0,0.0,0.0), SVector(0.0,0.0,0.0), 0.0,
             Point3d[], Observable(Float64[]), Float64[], 
             :cyan, 0.1)
precompute_pulses!(src)
add_source!(src)
display(fig)  # ablak megjelenítése
let t = 0.0  # lokális t a ciklushoz
    target = 1/60                 # 60 Hz felső korlát
    tprev = time_ns()/1e9         # előző frame időbélyeg (s)
    while isopen(fig.scene) && t < max_t
        tnow_real = time_ns()/1e9

        @static if DEBUG_MODE
            dt = 1/60                 # debug: fix 60 Hz
        else
            dt = tnow_real - tprev    # eltelt valós idő (s)
        end

        tprev = tnow_real

        t += E * dt               # E mint sebességszorzó (frame-vezérelt idő)
        tnow = t

        for src in sources
            src.act_p = src.act_p + src.RV * (E * dt)  # folyamatos idő szerinti elmozdulás
            update_radii!(src, tnow)
        end

        frame_used = (time_ns()/1e9) - tnow_real
        rem = target - frame_used
        if rem > 0
            sleep(rem)            # 60 Hz cap
        end
    end
end
if isopen(fig.scene)
    wait(fig.scene)  # nyitva marad, amíg be nem zárod
end
