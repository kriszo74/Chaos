# ---- gui.jl ----

# mk_menu!: label + legördülő + onchange callback
function mk_menu!(fig, grid, row, label_txt, options; onchange=nothing, selected_index=nothing)
    menu = Menu(fig, options = options)
    grid[row, 1] = Label(fig, label_txt)
    grid[row, 2:3] = menu
    isnothing(selected_index) || (menu.i_selected[] = selected_index::Int)
    isnothing(onchange) || on(menu.selection) do sel; onchange(sel); end
    return menu
end

# mk_slider!: label + slider + value label egy sorban
function mk_slider!(fig, grid, row, label_txt, range; startvalue, fmtdigits=2, onchange=nothing, bind_to=nothing)
    s   = Slider(fig, range=range, startvalue=startvalue)
    val = Label(fig, lift(x -> string(round(x, digits=fmtdigits)), s.value))
    grid[row, 1] = Label(fig, label_txt)
    grid[row, 2] = s
    grid[row, 3] = val
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
const GUI_COL_W = 220
const PRESET_ORDER = ("Single", "Dual (2)", "Batch")

# adatvezérelt preset-tábla a forrásokhoz (pozíció, szín)
const PRESET_TABLE = Dict(
    "Single"   => [(0.0,  :cyan)],
    "Dual (2)" => [(-2.0, :cyan), (2.0, :magenta)],
    "Batch"    => [(-4.0, :cyan), (-2.0, :magenta), (0.0, :yellow), (2.0, :green), (4.0, :orange)],
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
        for (x, col) in PRESET_TABLE[preset]  # WHY: preset kötelező; invalid kulcs hibát dob
            add_source!(world, scene, Source(SVector(x,0.0,0.0), SVector(2.0,0.0,0.0), 0.0,
                               Point3d[], Observable(Float64[]), col, 0.2, nothing))
        end
    end

    row = 0
    for (i, s) in enumerate(world.sources)
        # color row
        menu = mk_menu!(fig, sources_gl, row += 1, "color $(i)", COLORS; selected_index = findfirst(==(string(s.color)), COLORS),
                        onchange = sel -> begin
                            c = Symbol(sel)
                            s.color = c
                            s.plot[:color][] = c
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
    gl = GridLayout()
    fig[1, 1] = gl
    colsize!(fig.layout, 1, Fixed(GUI_COL_W))  # keskeny GUI-oszlop

    # Helyezés: jelenet jobbra, két sor magas
    fig[1:2, 2] = scene  # WHY: több függőleges hely a 3D-nek
    
    # --- Vezérlők ---
    sE = mk_slider!(fig, gl, 1, "E", 0.1:0.1:10.0; startvalue=world.E,
                    onchange = v -> (world.E = v))

    sources_gl  = GridLayout()
    gl[3, 1]   = Label(fig, "Sources")
    gl[3, 2:3] = sources_gl

    presets = collect(PRESET_ORDER)
    preset_menu = mk_menu!(fig, gl, 2, "Preset", presets; selected_index = 1,
                           onchange = sel -> rebuild_sources_panel!(fig, scene, sources_gl, world, rt, sel))

    # Dinamikus Sources panel (később bővíthető további paraméterekkel)    
    rebuild_sources_panel!(fig, scene, sources_gl, world, rt, first(presets))

    # Gomb: Play/Pause egyetlen gombbal (címkeváltás)
    btnPlay = mk_button!(fig, gl, 4, "▶"; onclick = btn -> begin
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
