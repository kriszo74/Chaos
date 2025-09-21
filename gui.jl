# ---- gui.jl ----

# mk_menu!: label + legördülő + onchange callback
function mk_menu!(fig, grid, row, label_txt, options; onchange=nothing, selected_index=nothing)
    menu = Menu(fig, options = options)
    grid[row, 1] = Label(fig, label_txt; color = :white, halign = :right, tellwidth = false)
    grid[row, 2:3] = menu
    isnothing(selected_index) || (menu.i_selected[] = selected_index::Int)
    isnothing(onchange) || on(menu.selection) do sel; onchange(sel); end
    return menu
end

# mk_slider!: label + slider + value label egy sorban
function mk_slider!(fig, grid, row, label_txt, range; startvalue, fmtdigits=2, onchange=nothing, bind_to=nothing)
    s   = Slider(fig, range=range, startvalue=startvalue)
    val = Label(fig, lift(x -> string(round(x, digits=fmtdigits)), s.value); color = :white) 
    grid[row, 1] = Label(fig, label_txt; color = :white, halign = :right, tellwidth = false)
    grid[row, 2] = s
    grid[row, 3] = val
    colsize!(grid, 3, Fixed(20))  # slider/műszer oszlop
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
const PRESET_ORDER = ("Single", "Dual (2)", "Batch")

# Ref‑választó állapot (globális, egyszerű tároló)
const REF_NONE = 0
const ref_choice = Ref(Int[])

# adatvezérelt preset-tábla a forrásokhoz (pozíció, szín)
# PRESET specifikáció mezők – jelenleg csak betöltjük őket, a viselkedés változatlan (NFC)
#  x::Float64             – kezdeti X-eltolás (gyors helyfoglaláshoz a mostani nézetben)
#  color::Symbol          – megjelenítési szín
#  RV::SVector{3,Float64} – relatív sebességvektor
#  RR::Float64            – rotation rate (a forrás saját időtengelye körüli szögsebesség)
#  ref::Union{Nothing,Int}– hivatkozott forrás indexe (1-alapú) a relatív d/yaw/pitch értelmezéséhez; ha nincs: nothing
#  distance::Float64      – távolság a ref forráshoz
#  yaw_deg::Float64       – azimut [°] a ref RV tengelye körül, a Π₀ síkban mért irányszöghöz viszonyítva (lásd lejjebb)
#  pitch_deg::Float64     – eleváció [°] a Π₀ síkjától felfelé (+) / lefelé (−)
# TODO: PRESET_TABLE külső fájlból (pl. presets.toml/presets.json) legyen beolvasva; ez csak átmeneti definíció.
const PRESET_TABLE = Dict(
    "Single" => [
        (x=0.0,  color=:cyan,    RV=SVector(2.0,0.0,0.0), RR=0.0, ref=nothing, distance=0.0, yaw_deg=0.0, pitch_deg=0.0),
    ],
    "Dual (2)" => [
        (x=-2.0, color=:cyan,    RV=SVector(2.0,0.0,0.0), RR=0.0, ref=1, distance=2.0, yaw_deg=60.0, pitch_deg=0.0),
        (x= 2.0, color=:magenta, RV=SVector(2.0,0.0,0.0), RR=0.0, ref=1, distance=2.0, yaw_deg=60.0, pitch_deg=0.0),
    ],
    "Batch" => [
        (x=-4.0, color=:cyan,    RV=SVector(2.0,0.0,0.0), RR=0.0, ref=nothing, distance=0.0, yaw_deg=0.0, pitch_deg=0.0),
        (x=-2.0, color=:magenta, RV=SVector(2.0,0.0,0.0), RR=0.0, ref=nothing, distance=0.0, yaw_deg=0.0, pitch_deg=0.0),
        (x= 0.0, color=:yellow,  RV=SVector(2.0,0.0,0.0), RR=0.0, ref=nothing, distance=0.0, yaw_deg=0.0, pitch_deg=0.0),
        (x= 2.0, color=:green,   RV=SVector(2.0,0.0,0.0), RR=0.0, ref=nothing, distance=0.0, yaw_deg=0.0, pitch_deg=0.0),
        (x= 4.0, color=:orange,  RV=SVector(2.0,0.0,0.0), RR=0.0, ref=nothing, distance=0.0, yaw_deg=0.0, pitch_deg=0.0),
    ],
)

const COLORS = ["cyan","magenta","yellow","green","orange","red","blue"]

function rebuild_sources_panel!(fig, scene, sources_gl, world::World, rt::Runtime, preset::String; start_d::Float64=2.0, start_theta_deg::Float64=60.0)
    rt.paused[] = true  # WHY: rebuild közben álljunk meg
    empty!(scene)                          # WHY: teljes újraépítés
    foreach(delete!, contents(sources_gl))  # blokk eltávolítása
    trim!(sources_gl)                # üres sor/oszlop levágása

    empty!(world.sources)
    if preset == "Dual (2)"
        # Inicializálás analitikusan d,θ alapján (Π₀ síkban)
        p1  = SVector(0.0, 0.0, 0.0)
        RV1 = SVector(2.0, 0.0, 0.0)
        p2  = p2_from_dθ(p1, RV1, start_d, start_theta_deg)
        add_source!(world, scene, Source(p1, RV1, 0.0, Point3d[], Observable(Float64[]), :cyan,    0.2, nothing))
        add_source!(world, scene, Source(p2, RV1, 0.0, Point3d[], Observable(Float64[]), :magenta, 0.2, nothing))
    else
        for spec in PRESET_TABLE[preset]  # NOTE: viselkedés változatlan, csak a séma bővült
            add_source!(world, scene, Source(
                SVector(spec.x, 0.0, 0.0), spec.RV, 0.0,
                Point3d[], Observable(Float64[]), spec.color, 0.2, nothing))
        end
    end

    # Ref választó alapállapot: minden újraépítéskor üres (—)
    ref_choice[] = fill(REF_NONE, length(world.sources))

    row = 0
    for (i, s) in enumerate(world.sources)
        # color row
        menu = mk_menu!(fig, sources_gl, row += 1, "color $(i)", COLORS; selected_index = findfirst(==(string(s.color)), COLORS),
                        onchange = sel -> begin
                            c = Symbol(sel)
                            s.color = c
                            s.plot[:color][] = c
                        end)

        # ref row – csak a felette lévő források választhatók
        ref_opts = i == 1 ? ["—"] : vcat(["—"], string.(1:i-1))
        mk_menu!(fig, sources_gl, row += 1, "ref $(i)", ref_opts;
                 selected_index = 1,
                 onchange = sel -> begin
                     val = sel == "—" ? REF_NONE : parse(Int, sel)
                     v = copy(ref_choice[])
                     if length(v) >= i
                         v[i] = val
                         ref_choice[] = v
                     end
                 end)

        # alpha row
        sl = mk_slider!(fig, sources_gl, row += 1, "alpha $(i)", 0.05:0.05:1.0;
                        startvalue = s.alpha,
                        onchange = v -> (s.alpha = v), bind_to = (s.plot, :alpha))
    end
    # Dual (2) extra vezérlők: d és θ a 2. forráshoz
    if preset == "Dual (2)"
        sD = mk_slider!(fig, sources_gl, row += 1, "d (src2)", 0.1:0.1:10.0; startvalue = start_d)
        sT = mk_slider!(fig, sources_gl, row += 1, "θ (src2) [°]", 0:5:360; startvalue = round(Int, start_theta_deg))
        # on(sD.value) do v
        #     rebuild_sources_panel!(fig, scene, sources_gl, world, rt, preset; start_d = v, start_theta_deg = sT.value[])
        # end
        # on(sT.value) do v
        #     rebuild_sources_panel!(fig, scene, sources_gl, world, rt, preset; start_d = sD.value[], start_theta_deg = v)
        # end
    end
end

# Egységes GUI setup: bal oldalt keskeny panel, jobb oldalt 3D (2 sor).
function setup_gui!(fig, scene, world::World, rt::Runtime)
    fig[1, 1] = gl = GridLayout() # Setting panel
    gl.alignmode = Makie.Outside(10) # külső padding
    colsize!(fig.layout, 1, Fixed(GUI_COL_W))  # keskeny GUI-oszlop

    gl[3, 1]   = Label(fig, "Sources"; color = :white)
    gl[4, 1:3] = sources_gl = GridLayout() # Sources panel
    sources_gl.alignmode = Makie.Outside(0) # külső padding

    fig[1:2, 2] = scene  # jelenet: helyezés jobbra, két sor magas
    
    # --- Vezérlők ---
    sE = mk_slider!(fig, gl, 1, "E", 0.1:0.1:10.0; startvalue=world.E,
                    onchange = v -> (world.E = v))

    presets = collect(PRESET_ORDER)
    preset_menu = mk_menu!(fig, gl, 2, "Preset", presets; selected_index = 1,
                           onchange = sel -> rebuild_sources_panel!(fig, scene, sources_gl, world, rt, sel))

    # Dinamikus Sources panel (később bővíthető további paraméterekkel)    
    rebuild_sources_panel!(fig, scene, sources_gl, world, rt, first(presets))

    # Gomb: Play/Pause egyetlen gombbal (címkeváltás)
    btnPlay = mk_button!(fig, gl, 5, "▶"; onclick = btn -> begin
        if rt.sim_task[] === nothing || istaskdone(rt.sim_task[])
            rt.sim_task[] = start_sim!(fig, scene, world, rt)
            rt.paused[] = false
            @async begin                      # futás vége után vissza Play-re
                try
                    wait(rt.sim_task[])
                catch
                end
                btn.label[] = "▶"             # ikon visszaállítása
            end
        else
            rt.paused[] = !rt.paused[]              # toggle pause
        end
        btn.label[] = rt.paused[] ? "▶" : "❚❚"
    end)
end
