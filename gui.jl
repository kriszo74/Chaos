# ---- gui.jl ----

# mk_menu!: label + legördülő + onchange callback
function mk_menu!(fig, grid, row, label_txt, options; onchange=nothing)
    lab = Label(fig, label_txt)
    menu = Menu(fig, options = options)
    grid[row, 1] = lab
    grid[row, 2:3] = menu
    if onchange !== nothing
        on(menu.selection) do sel; onchange(sel); end  # WHY: eseménykötés a segédfüggvényben
    end
    return menu
end

## --- Dynamic preset helpers ---
function rebuild_alpha_controls!(fig, alpha_gl, sources)
    try
        empty!(alpha_gl)
    catch
    end
    row = 1
    colors = ["cyan","magenta","yellow","green","orange","red","blue"]
    for (i, s) in enumerate(sources)
        # color row (simple menu for now)
        c_label = "color $(i)"
        menu = mk_menu!(fig, alpha_gl, row, c_label, colors;
                        onchange = sel -> begin
                            c = Symbol(sel)
                            try s.color = c catch end
                            try s.plot[:color][] = c catch end
                        end)
        try
            idx = findfirst(==(string(s.color)), colors)
            if idx !== nothing
                menu.i_selected[] = idx
            end
        catch
        end
        row += 1
        # alpha row
        a_label = "alpha $(i)"
        sl = mk_slider!(fig, alpha_gl, row, a_label, 0.05:0.05:1.0; startvalue = s.alpha,
                        onchange = v -> (s.alpha = v))
        try
            connect!(s.plot[:alpha], lift(Float32, sl.value))
        catch
        end
        row += 1
    end
    return nothing
end

function on_preset_change(fig, gl, scene, src, preset::String, alpha_gl)
    @info "preset_changed" preset
    reset_to_preset!(fig, scene, preset, alpha_gl)
    return nothing
end

function clear_scene_plots!(scene)
    try
        empty!(scene)
    catch
        try
            empty!(scene.scene)
        catch
        end
    end
    return nothing
end

function build_sources_for_preset(preset::String)
    srcs = Source[]
    if preset == "Single"
        push!(srcs, Source(SVector(0.0,0.0,0.0), SVector(2.0,0.0,0.0), 0.0, Point3d[], Observable(Float64[]), :cyan, 0.2, nothing))
    elseif preset == "Dual (2)"
        push!(srcs, Source(SVector(-2.0,0.0,0.0), SVector(2.0,0.0,0.0), 0.0, Point3d[], Observable(Float64[]), :cyan, 0.2, nothing))
        push!(srcs, Source(SVector( 2.0,0.0,0.0), SVector(2.0,0.0,0.0), 0.0, Point3d[], Observable(Float64[]), :magenta, 0.2, nothing))
    else
        for i in 1:5
            x = -4.0 + 2.0*(i-1)
            col = (:cyan, :magenta, :yellow, :green, :orange)[i]
            push!(srcs, Source(SVector(x,0.0,0.0), SVector(2.0,0.0,0.0), 0.0, Point3d[], Observable(Float64[]), col, 0.2, nothing))
        end
    end
    return srcs
end

function reset_to_preset!(fig, scene, preset::String, alpha_gl)
    try
        paused[] = true
    catch
    end
    clear_scene_plots!(scene)
    try
        empty!(sources)
    catch
    end
    for s in build_sources_for_preset(preset)
        add_source!(s)
    end
    rebuild_alpha_controls!(fig, alpha_gl, sources)
    return nothing
end

# mk_slider!: label + slider + value label egy sorban
function mk_slider!(fig, grid, row, label_txt, range; startvalue, fmtdigits=2, onchange=nothing)
    lab = Label(fig, label_txt)
    s   = Slider(fig, range=range, startvalue=startvalue)
    val = Label(fig, lift(x -> string(round(x, digits=fmtdigits)), s.value))
    grid[row, 1] = lab; grid[row, 2] = s; grid[row, 3] = val  # WHY: egy sorban
    if onchange !== nothing
        on(s.value) do v; onchange(v); end  # WHY: eseménykötés a segédfüggvényben
    end
    return s
end

# mk_button!: gomb + elhelyezés + opcionális onclick
function mk_button!(fig, grid, row, label; colspan=3, onclick=nothing)
    btn = Button(fig, label = label)
    grid[row, 1:colspan] = btn
    if onclick !== nothing
        on(btn.clicks) do _; onclick(btn); end
    end
    return btn
end

# Segédfüggvény: preset alapú vezérlők-újraépítés (stub)
function rebuild_controls!(fig, gl, scene, src, preset::String)
    @info "preset_changed" preset  # TODO: később itt építjük át a vezérlőket/forrásokat
    return nothing
end

# Egységes GUI setup – mindig aktív (nem kísérleti)
# Bal oldali keskeny panel; jobb oldalt a 3D jelenet két sort feszít ki.
function setup_gui!(fig, scene, src, running=nothing)  # running: elhanyagolva, kompat. hívásokhoz
    gl = GridLayout()
    fig[1, 1] = gl
    colsize!(fig.layout, 1, Fixed(220))  # keskeny GUI-oszlop

    # Helyezés: jelenet jobbra, két sor magas
    fig[1:2, 2] = scene  # WHY: több függőleges hely a 3D-nek
    
    # --- Vezérlők ---
    sE = mk_slider!(fig, gl, 1, "E", 0.1:0.1:10.0; startvalue=E,
                    onchange = v -> (global E; E = v))

    presets = ["Single", "Dual (2)", "Batch"]
    preset_menu = mk_menu!(fig, gl, 2, "Preset", presets;
                           onchange = sel -> on_preset_change(fig, gl, scene, src, sel, alpha_gl))

    # Dinamikus Sources panel (később bővíthető további paraméterekkel)
    alpha_lab = Label(fig, "Sources")
    alpha_gl  = GridLayout()
    gl[3, 1]   = alpha_lab
    gl[3, 2:3] = alpha_gl
    rebuild_alpha_controls!(fig, alpha_gl, sources)

    # sA = mk_slider!(fig, gl, 5, "alpha", 0.05:0.05:1.0; startvalue = src.alpha)
    #connect!(src.plot[:alpha], lift(Float32, sA.value))  # WHY: alpha célú vezérlése a GUI-ból

    # Gomb: Play/Pause egyetlen gombbal (címkeváltás)
    btnPlay = mk_button!(fig, gl, 4, "▶"; onclick = btn -> begin
    if sim_task[] === nothing || istaskdone(sim_task[])
    sim_task[] = start_sim!(fig, scene, sources)
    paused[] = false
    @async begin                      # futás vége után vissza Play-re
        try
            wait(sim_task[])
        catch
        end
        btn.label[] = "▶"             # ikon visszaállítása
    end
    else
        paused[] = !paused[]              # toggle pause
    end
    btn.label[] = paused[] ? "▶" : "❚❚"
    end)
    return nothing
end
