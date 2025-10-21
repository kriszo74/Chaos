using GLMakie
GLMakie.activate!(; focus_on_show=true, title="Chaos")
#GLMakie.activate!(; focus_on_show=true)  # kĂ©rjen fĂłkuszt megjelenĂ­tĂ©skor (display elĹ‘tt kell lennie)
#GLMakie.set_window_config!(; title = "Chaos") # ezek menjenek a setup_scene() -be.
using StaticArrays
using GeometryBasics
using Observables  # Observable tĂˇmogatĂˇs

# rendszer-paramĂ©terek
const DEBUG_MODE = get(ENV, "APP_DEBUG", "0") == "1"  # set APP_DEBUG=1 -> debug
@info "DEBUG_MODE" DEBUG_MODE

# Debug-only assert macro (0 overhead in release)
macro dbg_assert(cond, msg="")
    return :(@static if DEBUG_MODE
        @assert $(esc(cond)) $(esc(msg))
    end)
end
struct Runtime
    sim_task::Observable{Union{Nothing,Task}}
    paused::Observable{Bool}
    pause_ev::Base.Event
end

rt = Runtime(Observable{Union{Nothing,Task}}(nothing), Observable(false), Base.Event())

include("source.jl") # forrĂˇsâ€‘logika
mutable struct World # vilĂˇgĂˇllapot
    E::Float64
    density::Float64
    max_t::Float64
    t::Observable{Float64}
    sources::Vector{Source}
end

world = World(3.0, 1.0, 10.0, Observable(0.0), Source[]) # vilĂˇgĂˇllapot inicializĂˇlĂˇs

# jelenet beĂˇllĂ­tĂˇsa
include("3dtools.jl")
fig, scene = setup_scene()

include("gui.jl")
setup_gui!(fig, scene, world, rt)

# ĂšJ: gomb-indĂ­tĂˇsĂş szimulĂˇciĂł kĂĽlĂ¶n feladatban  # MOVED: init fent (GUI elĹ‘tt)
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

screen = display(fig)  # ablak megjelenĂ­tĂ©se (screen visszaadva)
zoom!(scene.scene, 1.5)  # csak display(fig) utĂˇn mĹ±kĂ¶dik.
isinteractive() || wait(screen) # F5 (nem interaktĂ­v) futĂˇsnĂˇl blokkoljunk az ablak bezĂˇrĂˇsĂˇig

