using GLMakie
using StaticArrays
using GeometryBasics
using Observables  # Observable támogatás

# Source: mozgás és megjelenítési adatok
mutable struct Source
    act_p::SVector{3, Float64}  # aktuális pozíció
    RV::SVector{3, Float64}     # sebesség vektor
    bas_t::Float64              # indulási idő
    positions::Vector{Point3d}  # pozíciók (Point3d)  # később megfontolandó: Observable
    radii::Observable{Vector{Float64}}       # sugarak (Float64)
    color::Symbol               # szín
    alpha::Float64              # áttetszőség
    plot::Any                   # plot handle
end

# World & Runtime: állapot
mutable struct World
    E::Float64
    density::Float64
    max_t::Float64
    sources::Vector{Source}
end

struct Runtime
    sim_task::Observable{Union{Nothing,Task}}
    paused::Observable{Bool}
end


# add_source!: forrás hozzáadása és vizuális regisztráció
function add_source!(world::World, scene, src::Source)
    N = Int(ceil((world.max_t - src.bas_t) * world.density))  # pozíciók és sugarak előkészítése
    p_base = src.act_p + src.RV * src.bas_t       # első impulzus pozíciója
    dp     = src.RV / world.density                     # két impulzus közti eltolás
    src.positions = [Point3d((p_base + dp * k)...) for k in 0:N-1]
    src.radii[] = fill(0.0, N)
    push!(world.sources, src)    
    ph = meshscatter!(scene, src.positions;
        marker = create_detailed_sphere(Point3f(0, 0, 0), 1f0), 
        markersize = src.radii,
        color = src.color,
        transparency = true,
        alpha = src.alpha)
    src.plot = ph  # GUI-kötésekhez
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

# jelenet beállítása
include("3dtools.jl")
fig, scene = setup_scene()

# világállapot (World/Runtime) inicializálás
world = World(3.0, 1.0, 10.0, Source[]) # világállapot
rt = Runtime(Observable{Union{Nothing,Task}}(nothing), Observable(false))
include("gui.jl")
setup_gui!(fig, scene, world, rt)

display(fig)  # ablak megjelenítése
zoom!(scene.scene, 1.5)  # csak display(fig) után működik.

# ÚJ: gomb-indítású szimuláció külön feladatban  # MOVED: init fent (GUI előtt)
function start_sim!(fig, scene, world::World, rt::Runtime)
    # Dupla-indítás védelem
    if rt.sim_task[] !== nothing && !istaskdone(rt.sim_task[])
        @info "start_sim!: already running, reusing existing task"
        return rt.sim_task[]
    end

    rt.sim_task[] = @async begin
        t = 0.0
        target = 1/60
        dt = target
        while isopen(fig.scene)
            if rt.paused[]; sleep(0.05); continue; end  # Pause alatt pihen
            tprev = time_ns()/1e9
            step = world.E * dt
            t += step
            if t > world.max_t
                break
            end
            for src in world.sources
                src.act_p = src.act_p + src.RV * step
                src.radii[] = update_radii(src.radii[], src.bas_t, t, world.density)
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
    return rt.sim_task[]
end