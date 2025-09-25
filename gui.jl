# ---- gui.jl ----

# Namespace tisztítás a Makie prefixek csökkentésére
using Makie: set_close_to!, Outside

# mk_menu!: label + legördülő + onchange callback
function mk_menu!(fig, grid, row, label_txt, options; onchange=nothing, selected_index=nothing)
    menu = Menu(fig, options = options)
    grid[row, 1] = Label(fig, label_txt; color = :white, halign = :right, tellwidth = false) # 
    grid[row, 2:3] = menu
    isnothing(selected_index) || (menu.i_selected[] = selected_index::Int)
    isnothing(onchange) || on(menu.selection) do sel; onchange(sel); end
    return menu
end

# mk_slider!: label + slider + value label egy sorban
function mk_slider!(fig, grid, row, label_txt, range; startvalue, fmtdigits=2, onchange=nothing, bind_to=nothing)
    s   = Slider(fig, range=range, startvalue=startvalue)
    val = Label(fig, lift(x -> string(round(x, digits=fmtdigits)), s.value); color = :white, halign = :right, tellwidth = false) 
    grid[row, 1] = Label(fig, label_txt; color = :white, halign = :right, tellwidth = false) # 
    grid[row, 2] = s
    grid[row, 3] = val
    #colsize!(grid, 3, Fixed(20))  # slider/műszer oszlop
    isnothing(onchange) || on(s.value) do v; onchange(v); end    
    if !isnothing(bind_to)
        pl, attr = bind_to
        on(s.value) do v
            nt = NamedTuple{(attr,)}((Float32(v),))
            update!(pl; nt...)
        end
    end
return s
end  

# mk_button!: gomb + elhelyezés + opcionális onclick
function mk_button!(fig, grid, row, label; colspan=3, onclick=nothing)
    btn = Button(fig, label = label)
    grid[row, 1:colspan] = btn
    isnothing(onclick) || on(btn.clicks) do _; onclick(btn); end
    return btn
end

## --- Dynamic preset helpers ---

# GUI konstansok (NFC)
# TODO: Minden konstans (GUI_COL_W, PRESET_ORDER, REF_NONE, COLORS, PRESET_TABLE, stb.) külső fájlból legyen betöltve (pl. TOML/JSON). Ideiglenesen hardcode.
const GUI_COL_W = 220
# ÚJ: egységes sebességskálázó (a fő RV hossz). A további forrásoknál ebből képzünk vektort.
const PRESET_ORDER = ("Single", "Dual (2)", "Batch")

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
# TODO: PRESET_TABLE külső fájlból (pl. presets.toml/presets.json) legyen beolvasva; ez csak átmeneti definíció.
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
        (color=:magenta, RV=2.0, RR=0.0, ref=1,       distance=2.0, yaw_deg=45.0, pitch_deg=0.0),
        (color=:yellow,  RV=2.0, RR=0.0, ref=1,       distance=3.5, yaw_deg=-30.0,pitch_deg=15.0),
        (color=:green,   RV=2.0, RR=0.0, ref=2,       distance=2.0, yaw_deg=90.0, pitch_deg=-10.0),
        (color=:orange,  RV=2.0, RR=0.0, ref=3,       distance=1.5, yaw_deg=-90.0,pitch_deg=5.0),
    ],
)

const COLORS = ["cyan","magenta","yellow","green","orange","red","blue"]

function rebuild_sources_panel!(fig, scene, sources_gl, world::World, rt::Runtime, preset::String; start_d::Float64=2.0, start_theta_deg::Float64=60.0)
    rt.paused[] = true  # WHY: rebuild közben álljunk meg
    empty!(scene)                          # WHY: teljes újraépítés
    foreach(delete!, contents(sources_gl))  # blokk eltávolítása
    trim!(sources_gl)                      # üres sor/oszlop levágása

    empty!(world.sources)

    # Egységes forrás-felépítés + azonnali UI építés (1 ciklus)
    row = 0
    for (i, spec) in enumerate(PRESET_TABLE[preset])
        pos, RV_vec = calculate_coordinates(world, spec.ref, spec.RV, spec.distance, spec.yaw_deg, spec.pitch_deg)
        src = Source(pos, RV_vec, spec.RR, 0.0, Point3d[], Observable(Float64[]), spec.color, 0.2, nothing)
        add_source!(world, scene, src)

        # color row (ALWAYS)
        mk_menu!(fig, sources_gl, row += 1, "color $(i)", COLORS;
                 selected_index = findfirst(==(string(src.color)), COLORS),
                 onchange = sel -> begin
                     c = Symbol(sel)
                     src.color = c
                     src.plot[:color][] = c
                 end)

        # alpha row (ALWAYS)
        mk_slider!(fig, sources_gl, row += 1, "alpha $(i)", 0.05:0.05:1.0;
                   startvalue = src.alpha,
                   onchange = v -> (src.alpha = v),
                   bind_to = (src.plot, :alpha))

        # RV (skálár) – egyelőre csak UI; live recompute = TODO
        mk_slider!(fig, sources_gl, row += 1, "RV $(i)", 0.1:0.1:10.0;
                   startvalue = sqrt(sum(abs2, src.RV)),
                   onchange = _ -> nothing)  # TODO: live újraszámítás calculate_coordinates-szal

        # RR (skalár, c-hez mérhető) – egyelőre csak UI
        mk_slider!(fig, sources_gl, row += 1, "RR $(i)", -5.0:0.1:5.0;
                   startvalue = spec.RR,
                   onchange = _ -> nothing)  # TODO: kölcsönhatásoknál vektorrá emelni

        # Csak referencia esetén: distance / yaw / pitch – TODO: live update
        if spec.ref !== nothing
            mk_slider!(fig, sources_gl, row += 1, "distance $(i)", 0.1:0.1:10.0;
                       startvalue = spec.distance,
                       onchange = _ -> nothing)  # TODO
            mk_slider!(fig, sources_gl, row += 1, "yaw $(i) [°]", -180:5:180;
                       startvalue = spec.yaw_deg,
                       onchange = _ -> nothing)  # TODO
            mk_slider!(fig, sources_gl, row += 1, "pitch $(i) [°]", -90:5:90;
                       startvalue = spec.pitch_deg,
                       onchange = _ -> nothing)  # TODO
        end
    end
    colsize!(sources_gl, 1, Relative(0.35))
    colsize!(sources_gl, 2, Relative(0.5))
    colsize!(sources_gl, 3, Relative(0.15))
end

# Egységes GUI setup: bal oldalt keskeny panel, jobb oldalt 3D (2 sor).
function setup_gui!(fig, scene, world::World, rt::Runtime)
    fig[1, 1] = gl = GridLayout() # Setting panel
    gl.alignmode = Outside(10) # külső padding
    colsize!(fig.layout, 1, Fixed(GUI_COL_W))  # keskeny GUI-oszlop

    gl[3, 1]   = Label(fig, "Sources"; color = :white)
    gl[4, 1:3] = sources_gl = GridLayout() # Sources panel
    sources_gl.alignmode = Outside(0) # külső padding

    fig[1:2, 2] = scene  # jelenet: helyezés jobbra, két sor magas
    
    # --- Vezérlők ---
    sE = mk_slider!(fig, gl, 1, "E", 0.1:0.1:10.0; startvalue=world.E,
                    onchange = v -> (world.E = v))

    # Aktuális preset és t állapot a GUI-ban
    presets = collect(PRESET_ORDER)
    current_preset = Ref(first(presets))
    current_t = Ref(0.0)

    # Preset választó (fent tartjuk, mint eddig)
    preset_menu = mk_menu!(fig, gl, 2, "Preset", presets; selected_index = 1,
                           onchange = sel -> begin
                               current_preset[] = sel
                               rebuild_sources_panel!(fig, scene, sources_gl, world, rt, sel)
                               # Re-apply aktuális t a friss jelenetre – közvetlen frissítés
                               tval = current_t[]
                               try
                                   tval = rt.t[]
                               catch
                               end
                               for src in world.sources
                                   src.radii[] = update_radii(src.radii[], src.bas_t, tval, world.density)
                               end
                           end)

    # Dinamikus Sources panel
    gl[3, 1]   = Label(fig, "Sources"; color = :white)
    gl[4, 1:3] = sources_gl = GridLayout() # Sources panel
    sources_gl.alignmode = Outside(0)

    rebuild_sources_panel!(fig, scene, sources_gl, world, rt, first(presets))

    # helper: apply current t to radii (play/scrub kompatibilis)
    local function _apply_current_t!()
        tval = current_t[]
        try
            tval = rt.t[]
        catch
        end
        for src in world.sources
            src.radii[] = update_radii(src.radii[], src.bas_t, tval, world.density)
        end
    end

    _apply_current_t!()

    # Globális csúszkák (density, max_t) és az idő-csúszka (t)
    sDensity = mk_slider!(fig, gl, 6, "density", 0.5:0.5:20.0;
                          startvalue = world.density,
                          onchange = v -> begin
                              world.density = v
                              rebuild_sources_panel!(fig, scene, sources_gl, world, rt, current_preset[])
                              _apply_current_t!()
                          end)

    # t-idő csúszka: scrub előre-hátra (automatikus pause)
    # guard: különbség emberi vs. programozott slider-mozgatás között
    sT_guard = Ref(false)
    sT = mk_slider!(fig, gl, 8, "t", 0.0:0.01:world.max_t;
                    startvalue = current_t[],
                    onchange = v -> begin
                        # ha programból toljuk a csúszkát (play alatt), NE állítsunk pauzét
                        sT_guard[] && return
                        rt.paused[] = true
                        current_t[] = v
                        for src in world.sources
                            src.radii[] = update_radii(src.radii[], src.bas_t, v, world.density)
                        end
                    end)

    # ha a futó animáció frissíti rt.t-t, a slider is kövesse, de ne triggerelje az onchange-et
    try
        on(rt.t) do tv
            sT_guard[] = true
            # kerekítsük a 0.01-es lépésre, és tartsuk a tartományban
            local v = round(tv, digits = 2)
            v = clamp(v, first(sT.range[]), last(sT.range[]))
            # A dokumentáció szerint programból a set_close_to! ajánlott a vizuális frissítéshez
            set_close_to!(sT, v)
            current_t[] = v
            sT_guard[] = false
        end
    catch
    end

    sMaxT = mk_slider!(fig, gl, 7, "max_t", 1.0:0.5:60.0;
                       startvalue = world.max_t,
                       onchange = v -> begin
                           world.max_t = v
                           rebuild_sources_panel!(fig, scene, sources_gl, world, rt, current_preset[])
                           # Frissítsük a t csúszka tartományát és clampeljük az értékét
                           try
                               sT.range[] = 0.0:0.01:world.max_t
                           catch
                           end
                           current_t[] = min(current_t[], world.max_t)
                           _apply_current_t!()
                       end)

    # Gomb: Play/Pause egyetlen gombbal (címkeváltás)
    btnPlay = mk_button!(fig, gl, 5, "▶"; onclick = btn -> begin
        if rt.sim_task[] === nothing || istaskdone(rt.sim_task[])
            rt.sim_task[] = start_sim!(fig, scene, world, rt)
            rt.paused[] = false
            @async begin
                try
                    wait(rt.sim_task[])
                catch
                end
                btn.label[] = "▶"
            end
        else
            rt.paused[] = !rt.paused[]
        end
        btn.label[] = rt.paused[] ? "▶" : "❚❚"
    end)
end
