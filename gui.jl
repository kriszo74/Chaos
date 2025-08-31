# ---- gui.jl ----

# Egységes GUI setup – mindig aktív (nem kísérleti)
# Bal oldali keskeny panel; jobb oldalt a 3D jelenet két sort feszít ki.
function setup_gui!(fig, scene, src, running)
    gl = GridLayout()
    fig[1, 1] = gl
    colsize!(fig.layout, 1, Fixed(220))  # keskeny GUI-oszlop

    # Helyezés: jelenet jobbra, két sor magas
    fig[1:2, 2] = scene  # WHY: több függőleges hely a 3D-nek

    # --- Vezérlők ---
    labE = Label(fig, "E")
    sE = Slider(fig, range = 0.1:0.1:10.0, startvalue = E)
    valE = Label(fig, lift(x -> string(round(x, digits=2)), sE.value))
    gl[1, 1] = labE
    gl[1, 2] = sE
    gl[1, 3] = valE

    labA = Label(fig, "alpha")
    sA = Slider(fig, range = 0.05:0.05:1.0, startvalue = src.alpha)
    valA = Label(fig, lift(x -> string(round(x, digits=2)), sA.value))
    gl[2, 1] = labA
    gl[2, 2] = sA
    gl[2, 3] = valA

    btnStart = Button(fig, label = "Start")
    gl[3, 1:3] = btnStart
    on(btnStart.clicks) do _
        running[] = true  # WHY: induljon az animáció
    end

    # Élő E-frissítés külön szálon
    @async begin
        while isopen(fig.scene)
            global E  # WHY: modelltempó állítása futás közben
            E = sE.value[]
            sleep(0.05)  # ~20 Hz
        end
    end

    return nothing
end
