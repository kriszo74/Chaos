# %% START ID=MAIN_IMPORTS, v1
using GLMakie
GLMakie.activate!(; focus_on_show=true)  # kérjen fókuszt megjelenítéskor (display előtt kell lennie)
using StaticArrays
using GeometryBasics
using Observables  # Observable támogatás
# %% END ID=MAIN_IMPORTS

# %% START ID=MAIN_RUNTIME_DEF, v1
# rendszer-paraméterek
const DEBUG_MODE = get(ENV, "APP_DEBUG", "0") == "1"  # set APP_DEBUG=1 -> debug
@info "DEBUG_MODE" DEBUG_MODE
struct Runtime
    sim_task::Observable{Union{Nothing,Task}}
    paused::Observable{Bool}
    pause_ev::Base.Event
end
# %% END ID=MAIN_RUNTIME_DEF

# %% START ID=MAIN_RUNTIME_INIT, v1
rt = Runtime(Observable{Union{Nothing,Task}}(nothing), Observable(false), Base.Event())
# %% END ID=MAIN_RUNTIME_INIT

# %% START ID=MAIN_WORLD_DEF, v1
include("source.jl") # forrás‑logika
mutable struct World # világállapot
    E::Float64
    density::Float64
    max_t::Float64
    t::Observable{Float64}
    sources::Vector{Source}
end
# %% END ID=MAIN_WORLD_DEF

# %% START ID=MAIN_WORLD_INIT, v1
world = World(3.0, 1.0, 10.0, Observable(0.0), Source[]) # világállapot inicializálás
# %% END ID=MAIN_WORLD_INIT

# jelenet beállítása
# %% START ID=MAIN_SCENE_SETUP, v1
include("3dtools.jl")
fig, scene = setup_scene()
# %% END ID=MAIN_SCENE_SETUP

# %% START ID=MAIN_GUI_SETUP, v1
include("gui.jl")
setup_gui!(fig, scene, world, rt)
# %% END ID=MAIN_GUI_SETUP

# ÚJ: gomb-indítású szimuláció külön feladatban  # MOVED: init fent (GUI előtt)
# %% START ID=MAIN_START_SIM, v1
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
                src.radii[] = update_radii(src.radii[], src.bas_t, world.t[], world.density)
            end
            frame_used = (time_ns()/1e9) - tprev
            rem = target - frame_used
            rem > 0 && sleep(rem)
            @static if !DEBUG_MODE; dt = max(target, frame_used); end
        end
        rt.paused[] = true
        world.t[] = 0.0
    end
end
# %% END ID=MAIN_START_SIM

# %% START ID=MAIN_TAIL, v1
screen = display(fig)  # ablak megjelenítése (screen visszaadva)
zoom!(scene.scene, 1.5)  # csak display(fig) után működik.
isinteractive() || wait(screen) # F5 (nem interaktív) futásnál blokkoljunk az ablak bezárásáig
# %% END ID=MAIN_TAIL
