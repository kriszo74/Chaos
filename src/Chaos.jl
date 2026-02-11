module Chaos

    using GLMakie
    using LinearAlgebra
    using StaticArrays
    using GeometryBasics
    using Colors
    using Observables  # Observable támogatás
    using Infiltrator
    
    # rendszer-paraméterek
    const DEBUG_MODE = get(ENV, "APP_DEBUG", "0") == "1" || get(ENV, "INFILTRATE_ON", "1") == "1" # set APP_DEBUG=1 -> debug

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
        positions_all::Vector{Point3d}
        radii_all::Observable{Vector{Float64}}
        uv_all::Observable{Vector{SOURCE_UV_T}}
        plot::Any
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
        @info "DEBUG_MODE = $DEBUG_MODE"

        rt = Runtime(Observable{Union{Nothing,Task}}(nothing), Observable(false), Base.Event())
        fig, scene = setup_scene()  # jelenet beállítása
        #TODO: a betöltendő konfigokra legyen ellenőrzés, pl. density csak pozitív egész szám lehet.
        world = World(
            Float64(CFG["world"]["E"]), 
            Float64(CFG["world"]["density"]),
            Float64(CFG["world"]["max_t"]),
            Observable(0.0),
            Source[],
            Point3d[],
            Observable(Float64[]),
            Observable(SOURCE_UV_T[]),
            nothing)

        apply_preset! = setup_gui!(fig, scene, world, rt)
        screen = display(fig)  # ablak megjelenítése (screen visszaadva)
        apply_preset!(CFG["presets"]["order"][1])
        zoom!(scene.scene, 15)  # csak display(fig) után működik. #TODO: compute_initial_zoom(world, preset) helper létrehozása, hogy a nagyítás illeszkedjen a szimuláció végállapotához. 
        isinteractive() || wait(screen) # F5 (nem interaktív) futásnál blokkoljunk az ablak bezárásáig
        return 0
    end
end
