# GUI réteg: vezérlők, preset-választás és forráspanel felépítése.
# A 3D jelenethez tartozó slider/menu események innen vezérlik a world állapotát.
# A panel újraépítés és a futásvezérlés (play/pause, seek) központi belépési pontjai itt vannak.

# mk_menu!: label + legördülő + onchange callback
function mk_menu!(fig, grid, row, label_txt, options; selected_index = nothing, onchange = nothing)
    grid[row, 1] = Label(fig, label_txt; color = :white, halign = :right, tellwidth = false)
    grid[row, 2:3] = menu = Menu(fig, options = options)
    isnothing(selected_index) || (menu.i_selected[] = selected_index::Int)
    isnothing(onchange) || on(menu.selection) do sel; onchange(sel); end
    return menu
end

# mk_slider!: label + slider + value label egy sorban
function mk_slider!(fig, grid, row, label_txt, range; startvalue, fmtdigits = 2, target = nothing, attr::Union{Nothing,Symbol} = nothing, transform = Float32, onchange::Union{Nothing,Function} = nothing)
    s = Slider(fig, range=range, startvalue=startvalue)
    grid[row, 1] = Label(fig, label_txt; color = :white, halign = :right, tellwidth = false)
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
function mk_button!(fig, grid, row, label; colspan = 3, onclick = nothing)
    grid[row, 1:colspan] = btn = Button(fig, label = label)
    isnothing(onclick) || on(btn.clicks) do _; onclick(btn); end
    return btn
end

const HUE30_PAIRS = sort_pairs(CFG["gui"]["hue"])
const FADE_RATIO_BREAKS_BY_PROFILE = Dict(name => Float64.(CFG["gui"]["FADE_RATIO_BREAKS"][name]) for name in CFG["gui"]["FADE_PROFILE_ORDER"])
const ALPHA_MIN_START_IX = maximum(length(v) for v in values(FADE_RATIO_BREAKS_BY_PROFILE))
const ALPHA_VALUES = Float32.(CFG["gui"]["ALPHA_VALUES"])

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
      rv_pitch = deg2rad(e["rv_pitch_deg"]), # RV irány eleváció [rad]
      fade_profile = get(e, "fade", "off"),
      fade_ratio_edges = FADE_RATIO_BREAKS_BY_PROFILE[get(e, "fade", "off")]) for e in find_entries_by_name(CFG["presets"]["table"], preset)]

# Forráspanelek újraépítése és jelenet megtisztítása
function rebuild_sources_panel!(preset::String, ncols::Int, cols::Int, fig, sources_gl, rt::Runtime, world::World)
    rt.paused[] = true            # rebuild közben álljunk meg
    foreach(delete!, contents(sources_gl))  # forráspanel elemeinek törlése
    trim!(sources_gl)             # üres sor/oszlop levágása
    clear_sources_buffers!(world) # world pufferek resetelése
    empty!(world.sources)         # forráslista ürítése

    # Egységes forrás-felépítés + azonnali UI építés (1 ciklus)
    row = 0
    for (i, spec) in enumerate(preset_specs(preset))
        cur_h_ix = Ref(findfirst(==(string(spec.color)), first.(HUE30_PAIRS)))  # hue-blokk indexe (1..12)
        cur_rr_offset = Ref(1 + round(Int, spec.RR / CFG["gui"]["RR_STEP"]))    # RR oszlop offset (1..ncols)
        cur_alpha_ix = Ref(max(findfirst(==(spec.alpha), ALPHA_VALUES), ALPHA_MIN_START_IX))
        cur_fade_ix = Ref(findfirst(==(spec.fade_profile), CFG["gui"]["FADE_PROFILE_ORDER"]))
        sel_col() = (cur_h_ix[] - 1) * ncols + (cur_rr_offset[] - 1) * length(CFG["gui"]["ALPHA_VALUES"]) + cur_alpha_ix[]
        src = add_source!(sel_col(), cols, spec, world)

        # hue row (DISCRETE 0..330° step 30°)
        hue = mk_menu!(fig, sources_gl, row += 1, "hue $(i)", [string(Symbol(name), " (", deg, Char(176), ")") for (name, deg) in HUE30_PAIRS];
                    selected_index = cur_h_ix[],
                    onchange = sel -> begin
                        cur_h_ix[] = findfirst(==(sel), hue.options[])
                        apply_source_visuals!(sel_col(), cols, src, world; source_ix = i, marker_color = RGBf(parse(Colorant, first(HUE30_PAIRS[cur_h_ix[]]))))
                    end)

        # alpha row (ALWAYS)
        mk_slider!(fig, sources_gl, row += 1, "alpha $(i)", ALPHA_VALUES[ALPHA_MIN_START_IX:end];
                   startvalue = ALPHA_VALUES[cur_alpha_ix[]],
                   onchange = v -> begin
                       cur_alpha_ix[] = max(findfirst(==(v), ALPHA_VALUES), ALPHA_MIN_START_IX)
                       apply_source_visuals!(sel_col(), cols, src, world)
                   end)

        # alpha halványulási profil (DISCRETE)
        mk_menu!(fig, sources_gl, row += 1, "fade $(i)", CFG["gui"]["FADE_PROFILE_ORDER"];
                    selected_index = cur_fade_ix[],
                    onchange = sel -> begin
                        cur_fade_ix[] = findfirst(==(sel), CFG["gui"]["FADE_PROFILE_ORDER"])
                        apply_source_visuals!(sel_col(), cols, src, world; fade_breaks = FADE_RATIO_BREAKS_BY_PROFILE[CFG["gui"]["FADE_PROFILE_ORDER"][cur_fade_ix[]]])
                    end)

        # RV (skálár) – LIVE recompute
        mk_slider!(fig, sources_gl, row += 1, "RV $(i)", 0.0:0.1:10.0;
                   startvalue = src.RV_mag,
                   onchange = v -> apply_RV_rescale!(v < eps(Float64) ? eps(Float64) : v, world.sources[i], world))
        
        # RR (skalár) – atlasz oszlop vezérlése (uv_transform), ideiglenes bekötés
        mk_slider!(fig, sources_gl, row += 1, "RR $(i)", 0.0:CFG["gui"]["RR_STEP"]:CFG["gui"]["RR_MAX"]; 
                    startvalue = spec.RR,
                    onchange = v -> begin
                        cur_rr_offset[] = 1 + round(Int, v / CFG["gui"]["RR_STEP"])
                        apply_source_RR!(v, sel_col(), cols, src, world)
                    end)

        # Csak referencia esetén: distance / yaw / pitch – live update Reffel
        if spec.ref !== nothing
            spec_ref = Ref(spec)              # forrás paraméterei (Ref)

            # Ref távolság csúszka: sugár frissítése ref forráshoz képest
            mk_slider!(fig, sources_gl, row += 1, "distance $(i)", 0.1:0.1:10.0;
                       startvalue = spec.distance,
                       onchange = v -> begin
                           spec_ref[] = (; spec_ref[]..., distance = v)
                           apply_spherical_position!(spec_ref[], src, world)
                       end)

            # Ref azimut csúszka: pálya síkbeli elforgatása ref körül
            mk_slider!(fig, sources_gl, row += 1, "yaw $(i) [°]", -180:5:180;
                       startvalue = rad2deg(spec.yaw),
                       onchange = v -> begin
                           spec_ref[] = (; spec_ref[]..., yaw = deg2rad(v))
                           apply_spherical_position!(spec_ref[], src, world)
                       end)

            # Ref pitch csúszka: eleváció módosítása refhez képest
            mk_slider!(fig, sources_gl, row += 1, "pitch $(i) [°]", -90:5:90;
                       startvalue = rad2deg(spec.pitch),
                       onchange = v -> begin
                           spec_ref[] = (; spec_ref[]..., pitch = deg2rad(v))
                           apply_spherical_position!(spec_ref[], src, world)
                       end)

            # RV irány – kézi yaw/pitch (pozíció nem változik)
            mk_slider!(fig, sources_gl, row += 1, "RV yaw $(i) [°]", -180:5:180;
                       startvalue = rad2deg(spec.rv_yaw),
                       onchange = v -> begin
                           spec_ref[] = (; spec_ref[]..., rv_yaw = deg2rad(v))
                           apply_RV_direction!(spec_ref[], src, world)
                       end)
            
            # Ref RV pitch: irány döntése helyváltoztatás nélkül
            mk_slider!(fig, sources_gl, row += 1, "RV pitch $(i) [°]", -90:5:90;
                       startvalue = rad2deg(spec.rv_pitch),
                       onchange = v -> begin
                           spec_ref[] = (; spec_ref[]..., rv_pitch = deg2rad(v))
                           apply_RV_direction!(spec_ref[], src, world)
                       end)
        end
    end
    sync_source_markers!(world) # Markerpozíciók egyszeri rebuild utáni frissítése.
    notify(world.source_colors) # Markerszínek egyszeri rebuild utáni frissítése.
    colsize!(sources_gl, 1, Relative(0.4))
    colsize!(sources_gl, 2, Relative(0.45))
    colsize!(sources_gl, 3, Relative(0.15))
end

# Egységes GUI setup: bal oldalt keskeny panel, jobb oldalt 3D (2 sor).
function setup_gui!(fig, scene, rt::Runtime, world::World)
    fig[1, 1] = gl = GridLayout() # Setting panel
    gl.alignmode = Outside(10) # külső padding
    colsize!(fig.layout, 1, Fixed(CFG["gui"]["GUI_COL_W"]))  # keskeny GUI-oszlop

    gl[3, 1]   = Label(fig, "Sources"; color = :white)
    gl[4, 1:3] = sources_gl = GridLayout() # Sources panel
    sources_gl.alignmode = Outside(0) # külső padding

    fig[1:2, 2] = scene  # jelenet: helyezés jobbra, két sor magas
    atlas, ncols, cols = rr_texture_from_hue(Float32(CFG["gui"]["RR_MAX"]), Float32(CFG["gui"]["RR_STEP"]), Float32.(CFG["gui"]["ALPHA_VALUES"]))
    world.plot = meshscatter!(
        scene,
        world.positions_all;
        marker       = create_detailed_sphere(Point3f(0, 0, 0), 1f0),
        markersize   = world.radii_all,
        color        = atlas,
        uv_transform = world.uv_all,
        rotation     = Vec3f(0.0, pi/4, 0.0), #TODO: mesh módosítása, hogy ne kelljen alaprotáció.
        transparency = true,
        interpolate  = true,
        shading      = true) 
    world.source_plot = meshscatter!(
        scene,
        world.source_positions;
        marker       = create_detailed_sphere(Point3f(0, 0, 0), 1f0; res = 24),
        markersize   = 0.08,
        color        = world.source_colors,
        transparency = false,
        shading      = true)

    # --- Vezérlők ---
    mk_slider!(fig, gl, 1, "E", 0.1:0.1:10.0; startvalue = world.E,
               onchange = v -> (world.E = v))

    function apply_preset!(sel)
        rebuild_sources_panel!(sel, ncols, cols, fig, sources_gl, rt, world)
        seek_world_time!(world, recompute = false)
    end

    # Preset választó
    mk_menu!(fig, gl, 2, "Preset", CFG["presets"]["order"]; selected_index = 1,
             onchange = apply_preset!)
           
    # Globális csúszkák (density, max_t) és az idő-csúszka (t)
    mk_slider!(fig, gl, 6, "density", CFG["gui"]["DENSITY_VALUES"];
               startvalue = world.density,
               onchange = v -> begin
                   world.density = v
                   update_sampling!(world)
               end)

    # t-idő csúszka: scrub előre-hátra (automatikus pause)
    disable_sT_onchange = Ref(false) # guard: különbség emberi vs. programozott slider-mozgatás között
    sT = mk_slider!(fig, gl, 8, "t", 0.0:0.01:world.max_t;
                    startvalue = world.t[],
                    onchange = v -> begin
                        disable_sT_onchange[] && return # ha programból toljuk a csúszkát (play alatt), NE állítsunk pauzét
                        rt.paused[] = true
                        world.t[] = v
                        seek_world_time!(world; recompute = false)
                    end)
    
    on(world.t) do tv
        if !rt.paused[]
            disable_sT_onchange[] = true # ha a futó animáció frissíti rt.t-t, a slider is kövesse, de ne triggerelje az onchange-et
            set_close_to!(sT, tv)
            disable_sT_onchange[] = false
        end
    end

    mk_slider!(fig, gl, 7, "max_t", 10.0:10.0:600.0;
               startvalue = world.max_t,
               onchange = v -> begin
                   world.max_t = v
                   sT.range[] = 0.0:0.01:world.max_t # Frissítsük a t csúszka tartományát
                   update_sampling!(world)
    end)

    # Gomb: Play/Pause egyetlen gombbal (címkeváltás)
    btnPlay = mk_button!(fig, gl, 5, "▶"; onclick = btn -> begin
        if isnothing(rt.sim_task[]) || istaskdone(rt.sim_task[])
            world.t[] + eps_tol >= world.max_t && seek_world_time!(world; target_t = 0.0)
            rt.sim_task[] = @async start_sim!(fig, rt, world)
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
