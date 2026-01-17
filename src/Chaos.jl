module Chaos

    using GLMakie
    using LinearAlgebra
    using StaticArrays
    using GeometryBasics
    using Colors
    using Observables  # Observable támogatás
    #using Infiltrator
    
    # rendszer-paraméterek
    const DEBUG_MODE = get(ENV, "APP_DEBUG", "0") == "1" || get(ENV, "INFILTRATE_ON", "1") == "1" # set APP_DEBUG=1 -> debug
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

    include("source.jl") # forrás‑logika
    mutable struct World # világállapot
        E::Float64
        density::Float64
        max_t::Float64
        t::Observable{Float64}
        sources::Vector{Source}
    end

    include("3dtools.jl")
    include("gui.jl")

    # ÚJ: gomb-indítású szimuláció külön feladatban  # MOVED: init fent (GUI előtt)
    function start_sim!(fig, world::World, rt::Runtime)
        dt = target = 1/60
        while isopen(fig.scene)
            while rt.paused[]; wait(rt.pause_ev); end
            tprev = time_ns()/1e9
            world.t[] += step = world.E * dt
            world.t[] > world.max_t + eps_tol && break #TODO: t_limit = world.max_t + eps_tol -t betenni max_t állításhoz (word-be vagy rt-be), hogy ne kelljen újra és újra számolni itt.
            step_world!(world; step)
            frame_used = (time_ns()/1e9) - tprev
            rem = target - frame_used
            rem > 0 ? sleep(rem) : @info "LAG!" #TODO: VSync, G‑Sync/Freesync -et alkalmazni, hogy látszólag se legyen LAG.
            @static if !DEBUG_MODE; dt = max(target, frame_used); end
        end
        rt.paused[] = true
        world.t[] = world.max_t
    end

    function julia_main()::Cint
        #TODO: nyomozni:  build kozben lefut a GUI, es a Makie font‑ot probal betolteni. A font fajl nem talalhato, ezert a build elhasal.
        ccall(:jl_generating_output, Cint, ()) != 0 && return 0
        
        rt = Runtime(Observable{Union{Nothing,Task}}(nothing), Observable(false), Base.Event())
        world = World(3.0, 1.0, 10.0, Observable(0.0), Source[])
        fig, scene = setup_scene()  # jelenet beállítása
        setup_gui!(fig, scene, world, rt)
        screen = display(fig)  # ablak megjelenítése (screen visszaadva)
        zoom!(scene.scene, 1.5)  # csak display(fig) után működik.
        isinteractive() || wait(screen) # F5 (nem interaktív) futásnál blokkoljunk az ablak bezárásáig
        return 0
    end
end
