# ---- main.jl ---- 
using GLMakie
using StaticArrays
using GeometryBasics
using Observables  # Observable támogatás

# Source: mozgás és megjelenítési adatok
# TODO (arch/perf roadmap):
# - Source karcsúsítása: positions, radii, plot → nézet/regiszter; color, alpha → handle-ről.
# - act_p → p0; pozíció számítása: p(t) = p0 + RV*(t - bas_t) (ne frissítsük minden frame-ben).
# - Több forrásnál: 1 instanced plot + attribútumtömbök (pos offset, radius, color, alpha).
# - Csak akkor lépjünk, ha mérhető perf-korlát jelentkezik.
mutable struct Source
    act_p::SVector{3, Float64}  # aktuális pozíció
    RV::SVector{3, Float64}     # sebesség vektor
    bas_t::Float64              # indulási idő
    positions::Vector{Point3d}   # pozíciók (Point3d)  # később megfontolandó: Observable
    radii::Observable{Vector{Float64}}       # sugarak (Float64)
    color::Symbol               # szín
    alpha::Float64              # áttetszőség
    plot::Any                 # plot handle
end

# add_source!: forrás hozzáadása és vizuális regisztráció
function add_source!(src::Source)
    N = Int(ceil((max_t - src.bas_t) * density))  # pozíciók és sugarak előkészítése
    p_base = src.act_p + src.RV * src.bas_t       # első impulzus pozíciója
    dp     = src.RV / density                     # két impulzus közti eltolás
    src.positions = [Point3d((p_base + dp * k)...) for k in 0:N-1]
    src.radii[] = fill(0.0, N)
    push!(sources, src)    
    ph = meshscatter!(scene, src.positions;
        marker = create_detailed_sphere(Point3f(0, 0, 0), 1f0), 
        markersize = src.radii,
        color = src.color,
        transparency = true,
        alpha = src.alpha)
    src.plot = ph  # GUI-kötésekhez
    return src
end

#TODO: később a GPU-n fusson (CUDA.jl)
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
E = 3
density = 1.0
max_t = 10.0

# jelenet beállítása
include("3dtools.jl")
fig, scene = setup_scene()

# források hozzáadása tesztként
sources = Source[]
src = Source(SVector(0.0,0.0,0.0), SVector(2.0,0.0,0.0), 0.0, Point3d[], Observable(Float64[]), :cyan, 0.1, nothing)
add_source!(src)

include("gui.jl")
setup_gui!(fig, scene, src)

#TODO: később egy függvény állítsa be zoom-ot és pozíciót a források és max_t alapján.
display(fig)  # ablak megjelenítése
zoom!(scene.scene, 1.5)  # csak display(fig) után működik.
#scale!(scene.scene, 0.8, 0.8, 0.8) # ez is csak display(fig) után működik.
#update_cam!-ot lenne a legjobb használni.

# ÚJ: gomb-indítású szimuláció külön feladatban
sim_task = Observable{Union{Nothing,Task}}(nothing)  # futó szimuláció task-ja
paused   = Observable(false)  # Pause jelző

function start_sim!(fig, scene, sources)
    # Dupla-indítás védelem
    if sim_task[] !== nothing && !istaskdone(sim_task[])
        @info "start_sim!: already running, reusing existing task"
        return sim_task[]
    end

    sim_task[] = @async begin
        t = 0.0
        target = 1/60
        dt = target
        while isopen(fig.scene)
            if paused[]; sleep(0.05); continue; end  # Pause alatt pihen
            tprev = time_ns()/1e9
            step = E * dt
            t += step
            if t > max_t
                break
            end
            for src in sources
                src.act_p = src.act_p + src.RV * step
                src.radii[] = update_radii(src.radii[], src.bas_t, t, density)
            end
            frame_used = (time_ns()/1e9) - tprev
            rem = target - frame_used
            if rem > 0
                sleep(rem)
            end
            @static if !DEBUG_MODE
                dt = max(target, frame_used)
            end
        end
    end
    return sim_task[]
end
