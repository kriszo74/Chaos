# ---- main.jl ---- 
using GLMakie
using StaticArrays
using GeometryBasics
using Observables  # Observable támogatás

# Source: mozgás és megjelenítési adatok
mutable struct Source
    act_p::SVector{3, Float64}  # aktuális pozíció
    RV::SVector{3, Float64}     # sebesség vektor
    bas_t::Float64              # indulási idő
    positions::Vector{Point3d}   # pozíciók (Point3d)  # később megfontolandó: Observable
    radii::Observable{Vector{Float64}}       # sugarak (Float64)
    color::Symbol               # szín
    alpha::Float64              # áttetszőség
end

# add_source!: forrás hozzáadása és vizuális regisztráció
function add_source!(src::Source)
    N = Int(ceil((max_t - src.bas_t) * density))  # pozíciók és sugarak előkészítése
    p_base = src.act_p + src.RV * src.bas_t       # első impulzus pozíciója
    dp     = src.RV / density                     # két impulzus közti eltolás
    src.positions = [Point3d((p_base + dp * k)...) for k in 0:N-1]
    src.radii[] = fill(0.0, N)
    push!(sources, src)
    meshscatter!(scene, src.positions;
        marker = create_detailed_sphere(Point3f(0, 0, 0), 1f0), 
        markersize = src.radii,
        color = src.color,
        transparency = true,
        alpha = src.alpha)
    return src
end

# Sugárvektor frissítése adott t-nél; meglévő pufferbe ír, aktív [1:K], a többi 0.
function update_radii(radii::Vector{Float64}, bas_t::Float64, tnow::Float64, density::Float64)    # meglévő puffer (argumentum)
    dt_rel = (tnow - bas_t)     # eltelt idő a bázistól
    K = ceil(Int, dt_rel * density) # Aktív impulzusok száma az adott időpillanatban
    @inbounds begin
        for i in 1:K
            radii[i] = dt_rel - (i-1)/density  # eltelt idő az i. impulzus óta
        end
        N = length(radii)
        if K < N
            fill!(view(radii, K+1:N), 0.0)  # inaktív impulzusok sugara 0
        end
    end
    return radii
end

const DEBUG_MODE = get(ENV, "APP_DEBUG", "0") == "1"  # set APP_DEBUG=1 -> debug
@info "DEBUG_MODE" DEBUG_MODE

# világállandók (kezdeti beállítások)
E = 1
density = 1.0
max_t = 10.0

# jelenet beállítása
include("3dtools.jl")
fig, scene = setup_scene(; use_axis3=true)

# források hozzáadása tesztként
sources = Source[]
src = Source(SVector(0.0,0.0,0.0), SVector(2.0,0.0,0.0), 0.0, Point3d[], Observable(Float64[]), :cyan, 0.1)
add_source!(src)

display(fig)  # ablak megjelenítése

@async begin
    t = 0.0  # lokális t a ciklushoz
    target = 1/60                 # 60 Hz felső korlát
    dt = target                   # kezdeti dt (s)
    while isopen(fig.scene)
        tprev = time_ns()/1e9
        step = E * dt             # időlépés (s)
        t += step                 # frame-vezérelt idő
        if t > max_t
            break
        end

        for src in sources
            src.act_p = src.act_p + src.RV * step  # folyamatos idő szerinti elmozdulás
            src.radii[] = update_radii(src.radii[], src.bas_t, t, density)  # sugárfrissítés (visszatérő)
        end

        frame_used = (time_ns()/1e9) - tprev
        rem = target - frame_used
        if rem > 0
            sleep(rem)            # 60 Hz cap
        end

        @static if !DEBUG_MODE
            dt = max(target, frame_used)   # min. target, overrun-nál frame_used
        end
    end
end
