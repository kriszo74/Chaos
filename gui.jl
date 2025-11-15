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

## --- Dynamic preset helpers ---

# GUI konstansok (NFC)
# TODO: Minden konstans (GUI_COL_W, PRESET_ORDER, REF_NONE, PRESET_TABLE, stb.) külső fájlból legyen betöltve (pl. TOML/JSON). Ideiglenesen hardcode.
const GUI_COL_W = 220
const RR_MAX = 2.0
const RR_STEP = 0.1
# ÚJ: egységes sebességskálázó (a fő RV hossz). A további forrásoknál ebből képzünk vektort.
const PRESET_ORDER = ("Single", "Dual (2)", "Batch")
const HUE30_LABELS = [string(HUE30_NAMES[h], " (", h, Char(176), ")") for h in 0:30:330]

# Ref‑választó állapot (globális, egyszerű tároló)
const REF_NONE = 0
const ref_choice = Ref(Int[])

# adatvezérelt preset-tábla a forrásokhoz (pozíció, szín)
# PRESET specifikáció mezők – jelenleg csak betöltjük őket, a viselkedés változatlan (NFC)
#  color::Symbol          – megjelenítési szín
#  RV::Float64            – sebesség nagysága (skalár). Az 1. forrás vektora (RV,0,0), a többinél számolt irány.
#  RR::Float64            – rotation rate (saját időtengely körüli szögsebesség) – skalár.
#  ref::Union{Nothing,Int}– hivatkozott forrás indexe (1‑alapú). Az első forrásnál: ref = nothing.
#  distance::Float64      – távolság a ref forráshoz
#  yaw_deg::Float64       – azimut [°] a ref RV tengelyéhez viszonyítva
#  pitch_deg::Float64     – eleváció [°] a Π₀ síkjától felfelé (+) / lefelé (−)
#  rv_yaw_deg::Float64    – RV irány azimut [°]
#  rv_pitch_deg::Float64  – RV irány eleváció [°]
# TODO: PRESET_TABLE külső fájlból (pl. presets.toml/presets.json) legyen beolvasva; ez csak átmeneti definíció.

const PRESET_TABLE = Dict(
    "Single" => [
        (color=:cyan,    RV=2.0, RR=2.0, ref=nothing, distance=0.0, yaw_deg=0.0,  pitch_deg=0.0,  rv_yaw_deg=0.0,  rv_pitch_deg=0.0),
    ],
    "Dual (2)" => [
        (color=:cyan,    RV=2.0, RR=0.0, ref=nothing, distance=0.0, yaw_deg=0.0,  pitch_deg=0.0,  rv_yaw_deg=0.0,  rv_pitch_deg=0.0),
        (color=:magenta, RV=2.0, RR=0.0, ref=1,       distance=2.0, yaw_deg=60.0, pitch_deg=90.0,  rv_yaw_deg=30.0,  rv_pitch_deg=120.0),
    ],
    "Batch" => [
        (color=:cyan,    RV=2.0, RR=0.0, ref=nothing, distance=0.0, yaw_deg=0.0,   pitch_deg=0.0,  rv_yaw_deg=0.0,  rv_pitch_deg=0.0),
        (color=:magenta, RV=2.0, RR=0.0, ref=1,       distance=2.0, yaw_deg=45.0,  pitch_deg=15.0, rv_yaw_deg=0.0,  rv_pitch_deg=0.0),
        (color=:yellow,  RV=2.0, RR=0.0, ref=1,       distance=3.5, yaw_deg=-30.0, pitch_deg=15.0, rv_yaw_deg=0.0,  rv_pitch_deg=0.0),
        (color=:green,   RV=2.0, RR=0.0, ref=2,       distance=2.0, yaw_deg=90.0,  pitch_deg=-10.0,rv_yaw_deg=0.0,  rv_pitch_deg=0.0),
        (color=:orange,  RV=2.0, RR=0.0, ref=3,       distance=1.5, yaw_deg=-90.0, pitch_deg=5.0,  rv_yaw_deg=0.0,  rv_pitch_deg=0.0),
    ],
)

# Forráspanelek újraépítése és jelenet megtisztítása
function rebuild_sources_panel!(gctx::GuiCtx, world::World, rt::Runtime, preset::String)
    rt.paused[] = true      # rebuild közben álljunk meg
    empty!(gctx.scene)      # teljes újraépítés
    foreach(delete!, contents(gctx.sources_gl))  # forráspanel elemeinek törlése
    trim!(gctx.sources_gl)  # üres sor/oszlop levágása
    empty!(world.sources)   # forráslista ürítése

    # Egységes forrás-felépítés + azonnali UI építés (1 ciklus)
    row = 0
    for (i, spec) in enumerate(PRESET_TABLE[preset])
        dist_ref  = Ref(spec.distance)        # relatív távolság állapota (Ref)
        yaw_ref   = Ref(spec.yaw_deg)         # relatív azimut állapota (Ref)
        pitch_ref = Ref(spec.pitch_deg)       # relatív eleváció állapota (Ref)
        rv_yaw_ref   = Ref(spec.rv_yaw_deg)   # RV azimut [°] (Ref)
        rv_pitch_ref = Ref(spec.rv_pitch_deg) # RV eleváció [°] (Ref)
        cur_h_ix = Ref(1) # hue-blokk indexe (1..12) #TODO: alapszín meghatározása
        cur_rr_offset = Ref(1 + round(Int, spec.RR / RR_STEP))  # RR oszlop offset (1..ncols)

        src = add_source!(world, gctx, spec; abscol=(cur_h_ix[] - 1) * gctx.ncols + cur_rr_offset[])

        # hue row (DISCRETE 0..330° step 30°)
        mk_menu!(gctx.fig, gctx.sources_gl, row += 1, "hue $(i)", HUE30_LABELS;
                    onchange = sel -> begin
                    cur_h_ix[] = ix = findfirst(==(sel), HUE30_LABELS)
                    update_source_uv!((cur_h_ix[] - 1) * gctx.ncols + cur_rr_offset[], src, gctx)
                    end)

        # alpha row (ALWAYS)
        mk_slider!(gctx.fig, gctx.sources_gl, row += 1, "alpha $(i)", 0.05:0.05:1.0;
                   startvalue = src.alpha,
                   onchange = v -> (src.alpha = v),
                   target = src.plot, attr = :alpha)

        # RV (skálár) – LIVE recompute
        mk_slider!(gctx.fig, gctx.sources_gl, row += 1, "RV $(i)", 0.1:0.1:10.0;
                   startvalue = sqrt(sum(abs2, src.RV)),
                   onchange = v -> rescale_RV_vec(v, world.sources[i], world))
        
        # RR (skalár) – atlasz oszlop vezérlése (uv_transform), ideiglenes bekötés
        mk_slider!(gctx.fig, gctx.sources_gl, row += 1, "RR $(i)", 0.0:RR_STEP:RR_MAX; startvalue = spec.RR,
                   onchange = v -> begin
                       cur_rr_offset[] = 1 + round(Int, v / RR_STEP)
                       update_source_RR(v, src, gctx, (cur_h_ix[] - 1) * gctx.ncols + cur_rr_offset[])
                   end)

        # Csak referencia esetén: distance / yaw / pitch – live update Reffel
        if spec.ref !== nothing
            mk_slider!(gctx.fig, gctx.sources_gl, row += 1, "distance $(i)", 0.1:0.1:10.0;
                       startvalue = spec.distance,
                       onchange = v -> begin
                           dist_ref[] = v
                           compute_spherical_position!(dist_ref[], world.sources[i], world, world.sources[spec.ref], yaw_ref[], pitch_ref[])
                           apply_pose!(world.sources[i], world)
                       end)
            mk_slider!(gctx.fig, gctx.sources_gl, row += 1, "yaw $(i) [°]", -180:5:180;
                       startvalue = spec.yaw_deg,
                       onchange = v -> begin
                           yaw_ref[] = v
                           compute_spherical_position!(dist_ref[], src, world, world.sources[spec.ref], yaw_ref[], pitch_ref[])
                           apply_pose!(src, world)
                       end)
            mk_slider!(gctx.fig, gctx.sources_gl, row += 1, "pitch $(i) [°]", -90:5:90;
                       startvalue = spec.pitch_deg,
                       onchange = v -> begin
                           pitch_ref[] = v
                           compute_spherical_position!(dist_ref[], src, world, world.sources[spec.ref], yaw_ref[], pitch_ref[])
                           apply_pose!(src, world)
                       end)

            # RV irány – kézi yaw/pitch (pozíció nem változik)
            mk_slider!(gctx.fig, gctx.sources_gl, row += 1, "RV yaw $(i) [°]", -180:5:180;
                       startvalue = spec.rv_yaw_deg,
                       onchange = v -> begin
                           rv_yaw_ref[] = v
                           compute_RV_direction!(rv_yaw_ref[], rv_pitch_ref[], src, world, world.sources[spec.ref])
                           apply_pose!(src, world)
                       end)
                       
            mk_slider!(gctx.fig, gctx.sources_gl, row += 1, "RV pitch $(i) [°]", -90:5:90;
                       startvalue = spec.rv_pitch_deg,
                       onchange = v -> begin
                           rv_pitch_ref[] = v
                           compute_RV_direction!(rv_yaw_ref[], rv_pitch_ref[], src, world, world.sources[spec.ref])
                           apply_pose!(src, world)
                       end)
        end
    end
    colsize!(gctx.sources_gl, 1, Relative(0.35))
    colsize!(gctx.sources_gl, 2, Relative(0.5))
    colsize!(gctx.sources_gl, 3, Relative(0.15))
end

# Egységes GUI setup: bal oldalt keskeny panel, jobb oldalt 3D (2 sor).
function setup_gui!(fig, scene, world::World, rt::Runtime)
    gctx = GuiCtx(fig, scene, GridLayout(), GridLayout(), rr_texture_from_hue(Float32(RR_MAX), Float32(RR_STEP))..., create_detailed_sphere_fast(Point3f(0, 0, 0), 1f0))
    fig[1, 1] = gctx.gl = GridLayout() # Setting panel
    gctx.gl.alignmode = Outside(10) # külső padding
    colsize!(fig.layout, 1, Fixed(GUI_COL_W))  # keskeny GUI-oszlop

    gctx.gl[3, 1]   = Label(fig, "Sources"; color = :white)
    gctx.gl[4, 1:3] = gctx.sources_gl = GridLayout() # Sources panel
    gctx.sources_gl.alignmode = Outside(0) # külső padding

    fig[1:2, 2] = scene  # jelenet: helyezés jobbra, két sor magas
    
    # --- Vezérlők ---
    sE = mk_slider!(fig, gctx.gl, 1, "E", 0.1:0.1:10.0; startvalue=world.E,
                    onchange = v -> (world.E = v))

    # Aktuális preset és t állapot a GUI-ban
    presets = collect(PRESET_ORDER) #TODO: setup_gui! ne kezeljen PRESET-et. rebuild_sources_panel! kezelje, ha null-t kap.
    current_preset = Ref(first(presets))
    # Preset választó (fent tartjuk, mint eddig)
    preset_menu = mk_menu!(fig, gctx.gl, 2, "Preset", presets; selected_index = 1,
                           onchange = sel -> begin
                               current_preset[] = sel
                               rebuild_sources_panel!(gctx, world, rt, sel)
                               # Re-apply aktuális t a friss jelenetre – közvetlen frissítés
                               apply_time!(world)
                           end)

    rebuild_sources_panel!(gctx, world, rt, first(presets)) # Dinamikus Sources panel

    # Globális csúszkák (density, max_t) és az idő-csúszka (t)
    sDensity = mk_slider!(fig, gctx.gl, 6, "density", 0.5:0.5:20.0;
                          startvalue = world.density,
                          onchange = v -> begin
                              world.density = v
                              rebuild_sources_panel!(gctx, world, rt, current_preset[])
                              apply_time!(world)
                          end)

    # t-idő csúszka: scrub előre-hátra (automatikus pause)
    disable_sT_onchange = Ref(false) # guard: különbség emberi vs. programozott slider-mozgatás között
    sT = mk_slider!(fig, gctx.gl, 8, "t", 0.0:0.01:world.max_t;
                    startvalue = world.t[],
                    onchange = v -> begin
                        disable_sT_onchange[] && return # ha programból toljuk a csúszkát (play alatt), NE állítsunk pauzét
                        rt.paused[] = true
                        world.t[] = v
                        apply_time!(world)
                    end)
    
    on(world.t) do tv
        if !rt.paused[]
            disable_sT_onchange[] = true # ha a futó animáció frissíti rt.t-t, a slider is kövesse, de ne triggerelje az onchange-et
            set_close_to!(sT, tv)
            disable_sT_onchange[] = false
        end
    end

    sMaxT = mk_slider!(fig, gctx.gl, 7, "max_t", 1.0:0.5:60.0;
                       startvalue = world.max_t,
                       onchange = v -> begin
                           world.max_t = v
                            rebuild_sources_panel!(gctx, world, rt, current_preset[])
                           # Frissítsük a t csúszka tartományát és clampeljük az értékét
                           sT.range[] = 0.0:0.01:world.max_t
                           world.t[] = clamp(world.t[], 0.0, world.max_t)
                           apply_time!(world)
                       end)

    # Gomb: Play/Pause egyetlen gombbal (címkeváltás)
    btnPlay = mk_button!(fig, gctx.gl, 5, "▶"; onclick = btn -> begin
        if isnothing(rt.sim_task[]) || istaskdone(rt.sim_task[])
            rt.sim_task[] = start_sim!(fig, scene, world, rt)
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
end
