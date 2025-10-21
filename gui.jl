# ---- gui.jl ----

# --- GUI context: kĂ¶zponti Ăˇllapot/erĹ‘forrĂˇs-csomag ---
# KĂ¶zĂ¶sen hasznĂˇlt GUI/Render elemek csomagja; kĂ©sĹ‘bb fĂĽggvĂ©nyek kĂ¶zĂ¶tt adjuk Ăˇt.
mutable struct GuiCtx
    fig::Figure            # fĹ‘ ablak (Figure)
    scene::LScene          # 3D jelenet
    gl::GridLayout         # bal oldali vezĂ©rlĹ‘panel
    sources_gl::GridLayout # forrĂˇs-panelek rĂˇcsa
    atlas::Matrix{RGBAf}   # RR-szĂ­natlasz (3 x N)
    ncols::Int             # hue-blokkonkenti oszlopszam
    cols::Int              # atlasz teljes oszlopszama
    marker::GeometryBasics.Mesh            # UVâ€‘gĂ¶mb marker (GeometryBasics.Mesh)
end

# mk_menu!: label + legĂ¶rdĂĽlĹ‘ + onchange callback
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

# mk_button!: gomb + elhelyezĂ©s + opcionĂˇlis onclick
function mk_button!(fig, grid, row, label; colspan=3, onclick=nothing)
    grid[row, 1:colspan] = btn = Button(fig, label = label)
    isnothing(onclick) || on(btn.clicks) do _; onclick(btn); end

    return btn
end

## --- Dynamic preset helpers ---

# GUI konstansok (NFC)
# TODO: Minden konstans (GUI_COL_W, PRESET_ORDER, REF_NONE, PRESET_TABLE, stb.) kĂĽlsĹ‘ fĂˇjlbĂłl legyen betĂ¶ltve (pl. TOML/JSON). Ideiglenesen hardcode.
const GUI_COL_W = 220
const RR_MAX = 2.0
const RR_STEP = 0.1
# ĂšJ: egysĂ©ges sebessĂ©gskĂˇlĂˇzĂł (a fĹ‘ RV hossz). A tovĂˇbbi forrĂˇsoknĂˇl ebbĹ‘l kĂ©pzĂĽnk vektort.
const PRESET_ORDER = ("Single", "Dual (2)", "Batch")

# Refâ€‘vĂˇlasztĂł Ăˇllapot (globĂˇlis, egyszerĹ± tĂˇrolĂł)
const REF_NONE = 0
const ref_choice = Ref(Int[])

# adatvezĂ©relt preset-tĂˇbla a forrĂˇsokhoz (pozĂ­ciĂł, szĂ­n)
# PRESET specifikĂˇciĂł mezĹ‘k â€“ jelenleg csak betĂ¶ltjĂĽk Ĺ‘ket, a viselkedĂ©s vĂˇltozatlan (NFC)
#  color::Symbol          â€“ megjelenĂ­tĂ©si szĂ­n
#  RV::Float64            â€“ sebessĂ©g nagysĂˇga (skalĂˇr). Az 1. forrĂˇs vektora (RV,0,0), a tĂ¶bbinĂ©l szĂˇmolt irĂˇny.
#  RR::Float64            â€“ rotation rate (sajĂˇt idĹ‘tengely kĂ¶rĂĽli szĂ¶gsebessĂ©g) â€“ skalĂˇr.
#  ref::Union{Nothing,Int}â€“ hivatkozott forrĂˇs indexe (1â€‘alapĂş). Az elsĹ‘ forrĂˇsnĂˇl: ref = nothing.
#  distance::Float64      â€“ tĂˇvolsĂˇg a ref forrĂˇshoz
#  yaw_deg::Float64       â€“ azimut [Â°] a ref RV tengelyĂ©hez viszonyĂ­tva
#  pitch_deg::Float64     â€“ elevĂˇciĂł [Â°] a Î â‚€ sĂ­kjĂˇtĂłl felfelĂ© (+) / lefelĂ© (â’)
# TODO: PRESET_TABLE kĂĽlsĹ‘ fĂˇjlbĂłl (pl. presets.toml/presets.json) legyen beolvasva; ez csak Ăˇtmeneti definĂ­ciĂł.

const PRESET_TABLE = Dict(
    "Single" => [
        (color=:cyan,    RV=2.0, RR=0.0, ref=nothing, distance=0.0, yaw_deg=0.0, pitch_deg=0.0),
    ],
    "Dual (2)" => [
        (color=:cyan,    RV=2.0, RR=0.0, ref=nothing, distance=0.0, yaw_deg=0.0, pitch_deg=0.0),
        (color=:magenta, RV=2.0, RR=0.0, ref=1,       distance=2.0, yaw_deg=60.0, pitch_deg=0.0),
    ],
    "Batch" => [
        (color=:cyan,    RV=2.0, RR=0.0, ref=nothing, distance=0.0, yaw_deg=0.0,  pitch_deg=0.0),
        (color=:magenta, RV=2.0, RR=0.0, ref=1,       distance=2.0, yaw_deg=45.0, pitch_deg=15.0),
        (color=:yellow,  RV=2.0, RR=0.0, ref=1,       distance=3.5, yaw_deg=-30.0,pitch_deg=15.0),
        (color=:green,   RV=2.0, RR=0.0, ref=2,       distance=2.0, yaw_deg=90.0, pitch_deg=-10.0),
        (color=:orange,  RV=2.0, RR=0.0, ref=3,       distance=1.5, yaw_deg=-90.0,pitch_deg=5.0),
    ],
)

# 
# ForrĂˇspanelek ĂşjraĂ©pĂ­tĂ©se Ă©s jelenet megtisztĂ­tĂˇsa
function rebuild_sources_panel!(gctx::GuiCtx, world::World, rt::Runtime, preset::String)
    rt.paused[] = true  # rebuild kĂ¶zben Ăˇlljunk meg
    empty!(gctx.scene)                          # teljes ĂşjraĂ©pĂ­tĂ©s
    foreach(delete!, contents(gctx.sources_gl))  
    trim!(gctx.sources_gl)                      # ĂĽres sor/oszlop levĂˇgĂˇsa

    empty!(world.sources)
    # EgysĂ©ges forrĂˇs-felĂ©pĂ­tĂ©s + azonnali UI Ă©pĂ­tĂ©s (1 ciklus)
    row = 0
    for (i, spec) in enumerate(PRESET_TABLE[preset])
        pos, RV_vec = calculate_coordinates(world, isnothing(spec.ref) ? nothing : world.sources[spec.ref], spec.RV, spec.distance, spec.yaw_deg, spec.pitch_deg)
        src = Source(pos, RV_vec, spec.RR, 0.0, Point3d[], Observable(Float64[]), gctx.atlas, 0.2, nothing)
        add_source!(world, gctx.scene, src)

        # aktuĂˇlis hue blokk index (1..12) a RR csĂşszkĂˇhoz
        cur_h_ix = Ref(1)
        cur_rr_offset = Ref(1 + round(Int, spec.RR / RR_STEP))  # 1-based offset within hue-block

        # hue row (DISCRETE 0..330Â° step 30Â°)
        let h_vals = collect(0:30:330),
            labels = [string(HUE30_NAMES[h], " (", h, "Â°)") for h in h_vals]
            mk_menu!(gctx.fig, gctx.sources_gl, row += 1, "hue $(i)", labels;
                     onchange = sel -> begin
                         ix = findfirst(==(sel), labels)
                         cur_h_ix[] = ix
                      abscol = (cur_h_ix[] - 1) * gctx.ncols + cur_rr_offset[]
                      update_source_uv!(abscol, src, gctx)
                     end)
        end

    # alpha row (ALWAYS)
        mk_slider!(gctx.fig, gctx.sources_gl, row += 1, "alpha $(i)", 0.05:0.05:1.0;
                   startvalue = src.alpha,
                   onchange = v -> (src.alpha = v),
                   target = src.plot, attr = :alpha)

        # RV (skĂˇlĂˇr) â€“ LIVE recompute
        mk_slider!(gctx.fig, gctx.sources_gl, row += 1, "RV $(i)", 0.1:0.1:10.0;
                   startvalue = sqrt(sum(abs2, src.RV)),
                   onchange = v -> update_source_RV(v, world.sources[i], world))
        
        # RR (skalĂˇr) â€“ atlasz oszlop vezĂ©rlĂ©se (uv_transform), ideiglenes bekĂ¶tĂ©s
        mk_slider!(gctx.fig, gctx.sources_gl, row += 1, "RR $(i)", 0.0:RR_STEP:RR_MAX;
                   startvalue = clamp(spec.RR, 0.0, 2.0),
                   onchange = v -> begin
                       cur_rr_offset[] = 1 + round(Int, v / RR_STEP)
                       abscol = (cur_h_ix[] - 1) * gctx.ncols + cur_rr_offset[]
                       update_source_RR(v, src, gctx, abscol)
                   end)


        # Csak referencia esetĂ©n: distance / yaw / pitch â€“ TODO: live update
        if spec.ref !== nothing
            mk_slider!(gctx.fig, gctx.sources_gl, row += 1, "distance $(i)", 0.1:0.1:10.0;
                       startvalue = spec.distance,
                       onchange = _ -> nothing)  # TODO
            mk_slider!(gctx.fig, gctx.sources_gl, row += 1, "yaw $(i) [Â°]", -180:5:180;
                       startvalue = spec.yaw_deg,
                       onchange = _ -> nothing)  # TODO
            mk_slider!(gctx.fig, gctx.sources_gl, row += 1, "pitch $(i) [Â°]", -90:5:90;
                       startvalue = spec.pitch_deg,
                       onchange = _ -> nothing)  # TODO
        end
    end
    colsize!(gctx.sources_gl, 1, Relative(0.35))
    colsize!(gctx.sources_gl, 2, Relative(0.5))
    colsize!(gctx.sources_gl, 3, Relative(0.15))
end


# EgysĂ©ges GUI setup: bal oldalt keskeny panel, jobb oldalt 3D (2 sor).
# GUI fĹ‘panel felĂ©pĂ­tĂ©se (bal vezĂ©rlĹ‘k + jobb 3D jelenet)

function setup_gui!(fig, scene, world::World, rt::Runtime)
    gctx = GuiCtx(fig, scene, GridLayout(), GridLayout(), rr_texture_from_hue(Float32(RR_MAX), Float32(RR_STEP))..., create_detailed_sphere_fast(Point3f(0, 0, 0), 1f0))
    fig[1, 1] = gctx.gl = GridLayout() # Setting panel
    gctx.gl.alignmode = Outside(10) # kĂĽlsĹ‘ padding
    colsize!(fig.layout, 1, Fixed(GUI_COL_W))  # keskeny GUI-oszlop

    gctx.gl[3, 1]   = Label(fig, "Sources"; color = :white)
    gctx.gl[4, 1:3] = gctx.sources_gl = GridLayout() # Sources panel
    gctx.sources_gl.alignmode = Outside(0) # kĂĽlsĹ‘ padding

    fig[1:2, 2] = scene  # jelenet: helyezĂ©s jobbra, kĂ©t sor magas
    
    # --- VezĂ©rlĹ‘k ---
    sE = mk_slider!(fig, gctx.gl, 1, "E", 0.1:0.1:10.0; startvalue=world.E,
                    onchange = v -> (world.E = v))

    # AktuĂˇlis preset Ă©s t Ăˇllapot a GUI-ban
    presets = collect(PRESET_ORDER)
    current_preset = Ref(first(presets))
    # Preset vĂˇlasztĂł (fent tartjuk, mint eddig)
    preset_menu = mk_menu!(fig, gctx.gl, 2, "Preset", presets; selected_index = 1,
                           onchange = sel -> begin
                               current_preset[] = sel
                               rebuild_sources_panel!(gctx, world, rt, sel)
                               # Re-apply aktuĂˇlis t a friss jelenetre â€“ kĂ¶zvetlen frissĂ­tĂ©s
                               apply_time!(world)
                           end)

    # Dinamikus Sources panel

    rebuild_sources_panel!(gctx, world, rt, first(presets))

    # GlobĂˇlis csĂşszkĂˇk (density, max_t) Ă©s az idĹ‘-csĂşszka (t)
    sDensity = mk_slider!(fig, gctx.gl, 6, "density", 0.5:0.5:20.0;
                          startvalue = world.density,
                          onchange = v -> begin
                              world.density = v
                              rebuild_sources_panel!(gctx, world, rt, current_preset[])
                              apply_time!(world)
                          end)

    # t-idĹ‘ csĂşszka: scrub elĹ‘re-hĂˇtra (automatikus pause)
    disable_sT_onchange = Ref(false) # guard: kĂĽlĂ¶nbsĂ©g emberi vs. programozott slider-mozgatĂˇs kĂ¶zĂ¶tt
    sT = mk_slider!(fig, gctx.gl, 8, "t", 0.0:0.01:world.max_t;
                    startvalue = world.t[],
                    onchange = v -> begin
                        disable_sT_onchange[] && return # ha programbĂłl toljuk a csĂşszkĂˇt (play alatt), NE ĂˇllĂ­tsunk pauzĂ©t
                        rt.paused[] = true
                        world.t[] = v
                        apply_time!(world)
                    end)
    
    on(world.t) do tv
        if !rt.paused[]
            disable_sT_onchange[] = true # ha a futĂł animĂˇciĂł frissĂ­ti rt.t-t, a slider is kĂ¶vesse, de ne triggerelje az onchange-et
            set_close_to!(sT, tv)
            disable_sT_onchange[] = false
        end
    end

    sMaxT = mk_slider!(fig, gctx.gl, 7, "max_t", 1.0:0.5:60.0;
                       startvalue = world.max_t,
                       onchange = v -> begin
                           world.max_t = v
                            rebuild_sources_panel!(gctx, world, rt, current_preset[])
                           # FrissĂ­tsĂĽk a t csĂşszka tartomĂˇnyĂˇt Ă©s clampeljĂĽk az Ă©rtĂ©kĂ©t
                           sT.range[] = 0.0:0.01:world.max_t
                           world.t[] = clamp(world.t[], 0.0, world.max_t)
                           apply_time!(world)
                       end)

    # Gomb: Play/Pause egyetlen gombbal (cĂ­mkevĂˇltĂˇs)
    btnPlay = mk_button!(fig, gctx.gl, 5, "â–¶"; onclick = btn -> begin
        if isnothing(rt.sim_task[]) || istaskdone(rt.sim_task[])
            rt.sim_task[] = start_sim!(fig, scene, world, rt)
            rt.paused[] = false
        else
            rt.paused[] = !rt.paused[]
        end
    end)
        
    on(rt.paused) do p
        if p
            btnPlay.label[] = "â–¶"
            Base.reset(rt.pause_ev)
        else
            btnPlay.label[] = "âťšâťš"
            notify(rt.pause_ev)
        end
    end
end
