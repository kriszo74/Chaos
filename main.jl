using GLMakie
using LinearAlgebra
using StaticArrays
using GeometryBasics
using Colors
using Observables  # Observable támogatás
using Infiltrator

# rendszer-paraméterek
const DEBUG_MODE = get(ENV, "APP_DEBUG", "0") == "1"  # set APP_DEBUG=1 -> debug
@info "DEBUG_MODE" DEBUG_MODE

# Debug-only assert macro (0 overhead in release)
macro dbg_assert(cond, msg="")
    return :(@static if DEBUG_MODE
        @assert $(esc(cond)) $(esc(msg))
    end)
end

include("config.jl")    # kofig betöltése

struct Runtime
    sim_task::Observable{Union{Nothing,Task}}
    paused::Observable{Bool}
    pause_ev::Base.Event
end

rt = Runtime(Observable{Union{Nothing,Task}}(nothing), Observable(false), Base.Event())

include("source.jl") # forrás‑logika
mutable struct World # világállapot
    E::Float64
    density::Float64
    max_t::Float64
    t::Observable{Float64}
    sources::Vector{Source}
end

world = World(3.0, 1.0, 10.0, Observable(0.0), Source[]) # világállapot inicializálás

# jelenet beállítása
include("3dtools.jl")
fig, scene = setup_scene()

include("gui.jl")
setup_gui!(fig, scene, world, rt)

# ÚJ: gomb-indítású szimuláció külön feladatban  # MOVED: init fent (GUI előtt)
function start_sim!(fig, scene, world::World, rt::Runtime)
    rt.sim_task[] = @async begin
        dt = target = 1/60
        while isopen(fig.scene)
            while rt.paused[]; wait(rt.pause_ev); end
            tprev = time_ns()/1e9
            world.t[] += step = world.E * dt
            world.t[] > world.max_t && break
            for src in world.sources
                src.act_p = src.act_p + src.RV * step
                src.radii[] = update_radii!(src, world)
                apply_wave_hit!(src, world)
            end
            frame_used = (time_ns()/1e9) - tprev
            rem = target - frame_used
            rem > 0 ? sleep(rem) : @info "LAG!" #TODO: VSync, G‑Sync/Freesync -et alkalmazni, hogy látszólag se legyen LAG.
            @static if !DEBUG_MODE; dt = max(target, frame_used); end
        end
        rt.paused[] = true
        world.t[] = 0.0
    end
end

screen = display(fig)  # ablak megjelenítése (screen visszaadva)
zoom!(scene.scene, 1.5)  # csak display(fig) után működik.
isinteractive() || wait(screen) # F5 (nem interaktív) futásnál blokkoljunk az ablak bezárásáig

