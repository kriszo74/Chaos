# ---- gui.jl ----

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


# Egységes GUI setup – mindig aktív (nem kísérleti)
# Bal oldali keskeny panel; jobb oldalt a 3D jelenet két sort feszít ki.
function setup_gui!(fig, scene, src, running)
    gl = GridLayout()
    fig[1, 1] = gl
    colsize!(fig.layout, 1, Fixed(220))  # keskeny GUI-oszlop

    # Helyezés: jelenet jobbra, két sor magas
    fig[1:2, 2] = scene  # WHY: több függőleges hely a 3D-nek

    # --- Vezérlők ---
    sE = mk_slider!(fig, gl, 1, "E", 0.1:0.1:10.0; startvalue=E,
                    onchange = v -> (global E; E = v))
    sA = mk_slider!(fig, gl, 2, "alpha", 0.05:0.05:1.0; startvalue = src.alpha)
    connect!(src.plot[:alpha], lift(Float32, sA.value))  # WHY: alpha élő vezérlése a GUI-ból

    btnStart = Button(fig, label = "Start")
    gl[3, 1:3] = btnStart
    on(btnStart.clicks) do _
        global E; E = sE.value[]  # WHY: induláskor E a sliderből
        running[] = true  # WHY: induljon az animáció
    end

    
    return nothing
end
