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
    t::Observable{Float64}
    pause_ev::Base.Event
end
rt = Runtime(Observable{Union{Nothing,Task}}(nothing), Observable(false), Observable(0.0), Base.Event())

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
    rt.sim_task[] = @async begin
        target = 1/60
        dt = target
        while isopen(fig.scene)
            while rt.paused[]
                wait(rt.pause_ev)
            end  # Pause alatt blokkol
            tprev = time_ns()/1e9
            step = world.E * dt
            rt.t[] += step
            rt.t[] > world.max_t && break
            for src in world.sources
                src.act_p = src.act_p + src.RV * step
                src.radii[] = update_radii(src.radii[], src.bas_t, rt.t[], world.density)
            end
            frame_used = (time_ns()/1e9) - tprev
            rem = target - frame_used
            rem > 0 && sleep(rem)
            @static if !DEBUG_MODE; dt = max(target, frame_used); end
        end
        rt.paused[] = true
    end
    return rt.sim_task[]
end
