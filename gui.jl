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
                           onchange = sel -> rebuild_controls!(fig, gl, scene, src, sel))

    # Dinamikus alpha alrész (később tölthető forrásonkénti csúszkákkal)
    alpha_lab = Label(fig, "Alphas")
    alpha_gl  = GridLayout()
    gl[3, 1]   = alpha_lab
    gl[3, 2:3] = alpha_gl

    sA = mk_slider!(fig, gl, 5, "alpha", 0.05:0.05:1.0; startvalue = src.alpha)
    connect!(src.plot[:alpha], lift(Float32, sA.value))  # WHY: alpha célú vezérlése a GUI-ból

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

