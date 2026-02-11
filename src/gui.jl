# --- GUI context: központi állapot/erőforrás-csomag ---
# Közösen használt GUI/Render elemek csomagja; később függvények között adjuk át.
mutable struct GuiCtx
    fig::Figure            # fő ablak (Figure)
    scene::LScene          # 3D jelenet
    gl::GridLayout         # bal oldali vezérlőpanel
    sources_gl::GridLayout # forrás-panelek rácsa
    atlas::Matrix{RGBAf}   # RR-színatlasz (3 x N)
    ncols::Int             # hue-blokkonkenti oszlopszam
    cols::Int              # atlasz teljes oszlopszama
    marker::GeometryBasics.Mesh  # UV‑gömb marker (GeometryBasics.Mesh)
end

# mk_menu!: label + legördülő + onchange callback
function mk_menu!(fig, grid, row, label_txt, options; onchange=nothing, selected_index=nothing)
    grid[row, 1] = Label(fig, label_txt; color = :white, halign = :right, tellwidth = false)
    grid[row, 2:3] = menu = Menu(fig, options = options)
    isnothing(selected_index) || (menu.i_selected[] = selected_index::Int)
    isnothing(onchange) || on(menu.selection) do sel; onchange(sel); end
    return menu
end

# mk_slider!: label + slider + value label egy sorban
function mk_slider!(fig, grid, row, label_txt, range; startvalue, fmtdigits=2, onchange::Union{Nothing,Function}=nothing, target=nothing, attr::Union{Nothing,Symbol}=nothing, transform = Float32)
    s   = Slider(fig, range=range, startvalue=startvalue)
    grid[row, 1] = Label(fig, label_txt; color = :white, halign = :right, tellwidth = false) # 
    grid[row, 2] = s
    grid[row, 3] = Label(fig, lift(x -> string(round(x, digits=fmtdigits)), s.value);
                         color = :white, halign = :right, tellwidth = false)
    isnothing(onchange) || on(s.value) do v; onchange(v); end

    if target !== nothing && attr !== nothing
        on(s.value) do v
            nt = NamedTuple{(attr,)}((transform(v),))
            update!(target; nt...)
        end
    end
    return s
end

# mk_button!: gomb + elhelyezés + opcionális onclick
function mk_button!(fig, grid, row, label; colspan=3, onclick=nothing)
    grid[row, 1:colspan] = btn = Button(fig, label = label)
    isnothing(onclick) || on(btn.clicks) do _; onclick(btn); end
    return btn
end

# Hue kiosztás configból: címkék és index lookup
const HUE30_LABELS = [string(Symbol(name), " (", deg, Char(176), ")") for (name, deg) in sort_pairs(CFG["gui"]["hue"])]
const HUE_NAME_TO_INDEX =  Dict(Symbol(name) => i for (i, (name, _)) in enumerate(sort_pairs(CFG["gui"]["hue"])))

preset_specs(preset::String) =
    [(color      = Symbol(e["color"]),  # megjelenítési szín
      alpha      = Float32(e["alpha"]), # átlátszóság
      RV         = abs(e["RV"]) < eps(Float64) ? eps(Float64) : e["RV"],     # sebesség nagysága (skalár). Az 1. forrás vektora (RV,0,0), a többinél számolt irányt.
      RR         = e["RR"],             # rotation rate (saját időtengely körüli szögsebesség) – skalár.
      ref        = e["ref"] == CFG["gui"]["REF_NONE"] ? nothing : e["ref"],  # hivatkozott forrás indexe (1‑alapú). Az első forrásnál: ref = nothing.
      distance   = e["distance"],       # távolság a ref forráshoz
      yaw    = deg2rad(e["yaw_deg"]),        # azimut [rad] a ref RV tengelyéhez viszonyítva
      pitch  = deg2rad(e["pitch_deg"]),      # eleváció [rad] a Π₀ síkjától felfelé (+) / lefelé (−)
      rv_yaw = deg2rad(e["rv_yaw_deg"]),     # RV irány azimut [rad]
      rv_pitch = deg2rad(e["rv_pitch_deg"])) for e in find_entries_by_name(CFG["presets"]["table"], preset)]

# Forráspanelek újraépítése és jelenet megtisztítása
function rebuild_sources_panel!(gctx::GuiCtx, world::World, rt::Runtime; preset = first(CFG["presets"]["order"]))
    rt.paused[] = true      # rebuild közben álljunk meg
    foreach(delete!, contents(gctx.sources_gl))  # forráspanel elemeinek törlése
    trim!(gctx.sources_gl)  # üres sor/oszlop levágása
    empty!(world.sources)   # forráslista ürítése
    empty!(world.positions_all)
    world.radii_all[] = Float64[]
    world.uv_all[] = SOURCE_UV_T[]
    world.plot[:positions][] = world.positions_all

    # Egységes forrás-felépítés + azonnali UI építés (1 ciklus)
    row = 0
    for (i, spec) in enumerate(preset_specs(preset))
        cur_h_ix = Ref(HUE_NAME_TO_INDEX[spec.color])  # hue-blokk indexe (1..12)
        cur_rr_offset = Ref(1 + round(Int, spec.RR / CFG["gui"]["RR_STEP"]))    # RR oszlop offset (1..ncols)
        cur_alpha_ix = Ref(findfirst(==(spec.alpha), Float32.(CFG["gui"]["ALPHA_VALUES"]))) 
        abscol() = (cur_h_ix[] - 1) * gctx.ncols + (cur_rr_offset[] - 1) * length(CFG["gui"]["ALPHA_VALUES"]) + cur_alpha_ix[]
        src = add_source!(world, gctx, spec; abscol=abscol())

        # hue row (DISCRETE 0..330° step 30°)
        mk_menu!(gctx.fig, gctx.sources_gl, row += 1, "hue $(i)", HUE30_LABELS;
                    selected_index = cur_h_ix[],
                    onchange = sel -> begin
                        cur_h_ix[] = ix = findfirst(==(sel), HUE30_LABELS)
                        apply_source_uv!(abscol(), src, gctx, world)
                    end)

        # alpha row (ALWAYS)
        mk_slider!(gctx.fig, gctx.sources_gl, row += 1, "alpha $(i)", Float32.(CFG["gui"]["ALPHA_VALUES"]);
                   startvalue = spec.alpha,
                   onchange = v -> begin
                       cur_alpha_ix[] = findfirst(==(v), Float32.(CFG["gui"]["ALPHA_VALUES"]))
                       apply_source_uv!(abscol(), src, gctx, world)
                   end)

        # RV (skálár) – LIVE recompute
        mk_slider!(gctx.fig, gctx.sources_gl, row += 1, "RV $(i)", 0.0:0.1:10.0;
                   startvalue = src.RV_mag,
                   onchange = v -> apply_RV_rescale!(v < eps(Float64) ? eps(Float64) : v, world.sources[i], world))
        
        # RR (skalár) – atlasz oszlop vezérlése (uv_transform), ideiglenes bekötés
        mk_slider!(gctx.fig, gctx.sources_gl, row += 1, "RR $(i)", 0.0:CFG["gui"]["RR_STEP"]:CFG["gui"]["RR_MAX"]; 
                    startvalue = spec.RR,
                    onchange = v -> begin
                        cur_rr_offset[] = 1 + round(Int, v / CFG["gui"]["RR_STEP"])
                        apply_source_RR!(v, src, world, gctx, abscol())
                    end)

        # Csak referencia esetén: distance / yaw / pitch – live update Reffel
        if spec.ref !== nothing
            spec_ref = Ref(spec)              # forrás paraméterei (Ref)

            # Ref távolság csúszka: sugár frissítése ref forráshoz képest
            mk_slider!(gctx.fig, gctx.sources_gl, row += 1, "distance $(i)", 0.1:0.1:10.0;
                       startvalue = spec.distance,
                       onchange = v -> begin
                           spec_ref[] = (; spec_ref[]..., distance = v)
                           apply_spherical_position!(spec_ref[], src, world)
                       end)

            # Ref azimut csúszka: pálya síkbeli elforgatása ref körül
            mk_slider!(gctx.fig, gctx.sources_gl, row += 1, "yaw $(i) [°]", -180:5:180;
                       startvalue = rad2deg(spec.yaw),
                       onchange = v -> begin
                           spec_ref[] = (; spec_ref[]..., yaw = deg2rad(v))
                           apply_spherical_position!(spec_ref[], src, world)
                       end)

            # Ref pitch csúszka: eleváció módosítása refhez képest
            mk_slider!(gctx.fig, gctx.sources_gl, row += 1, "pitch $(i) [°]", -90:5:90;
                       startvalue = rad2deg(spec.pitch),
                       onchange = v -> begin
                           spec_ref[] = (; spec_ref[]..., pitch = deg2rad(v))
                           apply_spherical_position!(spec_ref[], src, world)
                       end)

            # RV irány – kézi yaw/pitch (pozíció nem változik)
            mk_slider!(gctx.fig, gctx.sources_gl, row += 1, "RV yaw $(i) [°]", -180:5:180;
                       startvalue = rad2deg(spec.rv_yaw),
                       onchange = v -> begin
                           spec_ref[] = (; spec_ref[]..., rv_yaw = deg2rad(v))
                           apply_RV_direction!(spec_ref[], src, world)
                       end)
            
            # Ref RV pitch: irány döntése helyváltoztatás nélkül
            mk_slider!(gctx.fig, gctx.sources_gl, row += 1, "RV pitch $(i) [°]", -90:5:90;
                       startvalue = rad2deg(spec.rv_pitch),
                       onchange = v -> begin
                           spec_ref[] = (; spec_ref[]..., rv_pitch = deg2rad(v))
                           apply_RV_direction!(spec_ref[], src, world)
                       end)
        end
    end
    colsize!(gctx.sources_gl, 1, Relative(0.4))
    colsize!(gctx.sources_gl, 2, Relative(0.45))
    colsize!(gctx.sources_gl, 3, Relative(0.15))
end

# Egységes GUI setup: bal oldalt keskeny panel, jobb oldalt 3D (2 sor).
function setup_gui!(fig, scene, world::World, rt::Runtime)
    gctx = GuiCtx(fig, scene, GridLayout(), GridLayout(), rr_texture_from_hue(Float32(CFG["gui"]["RR_MAX"]), Float32(CFG["gui"]["RR_STEP"]); alphas=Float32.(CFG["gui"]["ALPHA_VALUES"]))..., create_detailed_sphere_fast(Point3f(0, 0, 0), 1f0))
    fig[1, 1] = gctx.gl = GridLayout() # Setting panel
    gctx.gl.alignmode = Outside(10) # külső padding
    colsize!(fig.layout, 1, Fixed(CFG["gui"]["GUI_COL_W"]))  # keskeny GUI-oszlop

    gctx.gl[3, 1]   = Label(fig, "Sources"; color = :white)
    gctx.gl[4, 1:3] = gctx.sources_gl = GridLayout() # Sources panel
    gctx.sources_gl.alignmode = Outside(0) # külső padding

    fig[1:2, 2] = scene  # jelenet: helyezés jobbra, két sor magas
    world.plot = meshscatter!(
        scene,
        world.positions_all;
        marker       = create_detailed_sphere_fast(Point3f(0, 0, 0), 1f0),
        markersize   = world.radii_all,
        color        = rr_texture_from_hue(Float32(CFG["gui"]["RR_MAX"]), Float32(CFG["gui"]["RR_STEP"]); alphas=Float32.(CFG["gui"]["ALPHA_VALUES"]))[1],
        uv_transform = world.uv_all,
        rotation     = Vec3f(0.0, pi/4, 0.0), #TODO: mesh módosítása, hogy ne kelljen alaprotáció.
        transparency = true,
        interpolate  = true,
        shading      = true) 

    # --- Vezérlők ---
    mk_slider!(fig, gctx.gl, 1, "E", 0.1:0.1:10.0; startvalue=world.E,
               onchange = v -> (world.E = v))

    function apply_preset!(sel)
        rebuild_sources_panel!(gctx, world, rt; preset = sel)
        seek_world_time!(world)
    end

    # Preset választó
    mk_menu!(fig, gctx.gl, 2, "Preset", CFG["presets"]["order"]; selected_index = 1,
             onchange = apply_preset!)
           
    # Globális csúszkák (density, max_t) és az idő-csúszka (t)
    mk_slider!(fig, gctx.gl, 6, "density", CFG["gui"]["DENSITY_VALUES"];
               startvalue = world.density,
               onchange = v -> begin
                   world.density = v
                   update_sampling!(world)
                   seek_world_time!(world)
               end)

    # t-idő csúszka: scrub előre-hátra (automatikus pause)
    disable_sT_onchange = Ref(false) # guard: különbség emberi vs. programozott slider-mozgatás között
    sT = mk_slider!(fig, gctx.gl, 8, "t", 0.0:0.01:world.max_t;
                    startvalue = world.t[],
                    onchange = v -> begin
                        disable_sT_onchange[] && return # ha programból toljuk a csúszkát (play alatt), NE állítsunk pauzét
                        rt.paused[] = true
                        world.t[] = v
                        seek_world_time!(world)
                    end)
    
    on(world.t) do tv
        if !rt.paused[]
            disable_sT_onchange[] = true # ha a futó animáció frissíti rt.t-t, a slider is kövesse, de ne triggerelje az onchange-et
            set_close_to!(sT, tv)
            disable_sT_onchange[] = false
        end
    end

    mk_slider!(fig, gctx.gl, 7, "max_t", 10.0:10.0:600.0;
               startvalue = world.max_t,
               onchange = v -> begin
                   world.max_t = v
                   update_sampling!(world)
                   
                   sT.range[] = 0.0:0.01:world.max_t # Frissítsük a t csúszka tartományát
                   seek_world_time!(world)
               end)

    # Gomb: Play/Pause egyetlen gombbal (címkeváltás)
    btnPlay = mk_button!(fig, gctx.gl, 5, "▶"; onclick = btn -> begin
        if isnothing(rt.sim_task[]) || istaskdone(rt.sim_task[])
            seek_world_time!(world, 0.0)
            rt.sim_task[] = @async start_sim!(fig, world, rt)
            rt.paused[] = false
        else
            rt.paused[] = !rt.paused[]
        end
    end)
        
    on(rt.paused) do p
        if p
            btnPlay.label[] = "▶"
            Base.reset(rt.pause_ev)
        else
            btnPlay.label[] = "❚❚"
            notify(rt.pause_ev)
        end
    end

    return apply_preset! # preset alkalmazó visszaadása
end
