using GLMakie
using StaticArrays
using GeometryBasics
using Observables  # Observable támogatás

# rendszer-paraméterek
const DEBUG_MODE = get(ENV, "APP_DEBUG", "0") == "1"  # set APP_DEBUG=1 -> debug
@info "DEBUG_MODE" DEBUG_MODE
struct Runtime
    sim_task::Observable{Union{Nothing,Task}}
    paused::Observable{Bool}
end
rt = Runtime(Observable{Union{Nothing,Task}}(nothing), Observable(false))

include("source.jl") # forrás‑logika
mutable struct World # világállapot
    E::Float64
    density::Float64
    max_t::Float64
    sources::Vector{Source}
end
world = World(3.0, 1.0, 10.0, Source[]) # világállapot inicializálás

# jelenet beállítása
include("3dtools.jl")
fig, scene = setup_scene()

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