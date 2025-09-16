# ---- gtk_ui.jl ----
# GTK4 alap UI-váz: felső eszköztár + (egyszerű) menü, bal oldali panel, alul automatikusan előbukkanó sáv
# Megjegyzés: tudatosan nem használ PopoverMenuBar/Gio.Menu modellt az első lépésben, hogy a függőségek minimálisak maradjanak.
# A menü most MenuButton + Popover-ből áll; később cserélhető valódi GMenu-s menüre.

using Gtk4
using GtkObservables
using Observables

# -- felső sáv: HeaderBar, menü gombok, ikon-gombok --
function _build_headerbar()
    hb  = GtkHeaderBar()

    # „Hagyományos” menük – egyszerűsített megvalósítás: MenuButton + Popover
    menubox = GtkBox(:h; spacing=8)
    for title in ("File", "Edit", "View", "Settings")
        mb = GtkMenuButton(label=title)
        pop = GtkPopover()
        vb  = GtkBox(:v; spacing=4, margin_top=6, margin_bottom=6, margin_start=6, margin_end=6)
        # Ide kerülhetnek a menüpontok (később akciókhoz kötve)
        for item in (title == "File" ? ("New", "Open…", "Save") : ("Action 1", "Action 2"))
            push!(vb, GtkButton(label=item))
        end
        set_gtk_property!(pop, :child, vb)
        set_gtk_property!(mb, :popover, pop)
        push!(menubox, mb)
    end
    set_gtk_property!(hb, :title_widget, menubox)

    # Ikonos gombok (jobb oldal)
    btn_new  = GtkButton(); set_gtk_property!(btn_new,  :icon_name, "document-new-symbolic");  set_gtk_property!(btn_new,  :tooltip_text, "New")
    btn_open = GtkButton(); set_gtk_property!(btn_open, :icon_name, "document-open-symbolic"); set_gtk_property!(btn_open, :tooltip_text, "Open…")
    btn_save = GtkButton(); set_gtk_property!(btn_save, :icon_name, "document-save-symbolic"); set_gtk_property!(btn_save, :tooltip_text, "Save")
    push!(hb, btn_new); push!(hb, btn_open); push!(hb, btn_save)

    return hb, (btn_new=btn_new, btn_open=btn_open, btn_save=btn_save)
end

# -- bal oldali paraméter panel (GtkObservables) --
function _build_sidepanel(world, rt)
    side = GtkBox(:v; spacing=8, margin_top=8, margin_start=8, margin_end=8)

    cb_pause, pause_obs = checkbox(false, label="Pause")
    sl_E,     E_obs     = slider(0.1:0.1:10.0; label="E", initial=getfield(world, :E))

    push!(side, cb_pause)
    push!(side, sl_E)

    # Kötések – egyszerű alap
    on(pause_obs) do v; rt.paused[] = v; end
    on(E_obs)     do v; world.E = v; end

    return side
end

# -- alsó automatikusan előbukkanó sáv (Revealer + ActionBar) --
function _build_bottom_bar()
    actionbar = GtkActionBar()
    push!(actionbar, GtkButton(label="▶"))  # Play/Pause helyfoglaló
    push!(actionbar, GtkButton(label="Step"))

    revealer  = GtkRevealer(; transition_type=GtkRevealerTransitionType.SLIDE_UP)
    set_gtk_property!(revealer, :child, actionbar)
    return revealer, actionbar
end

# -- fő UI összerakása egy Overlay-ben --
function build_gtk_ui(world, rt)
    win = GtkWindow("Időgeometria – GTK UI", 1000, 700)

    hb, _buttons = _build_headerbar()
    set_gtk_property!(win, :titlebar, hb)

    overlay = GtkOverlay()
    set_gtk_property!(win, :child, overlay)

    # középső tartalom: bal oldalon panel, jobb oldalon egyelőre üres
    content = GtkBox(:h)
    set_gtk_property!(overlay, :child, content)

    side = _build_sidepanel(world, rt)
    main = GtkBox(:v)  # ide később jöhet státusz / log / preview

    push!(content, side)
    push!(content, GtkSeparator(:vertical))
    push!(content, main)

    # alsó sáv + egérfigyelő a felfedéshez
    revealer, actionbar = _build_bottom_bar()
    set_gtk_property!(overlay, :overlay, revealer)
    set_gtk_property!(revealer, :halign, GtkAlign.FILL)
    set_gtk_property!(revealer, :valign, GtkAlign.END)

    ctrl = GtkEventControllerMotion()
    signal_connect(ctrl, "motion") do _, x::Cdouble, y::Cdouble
        alloc = allocation(overlay)
        reveal = y > alloc.height - 24.0
        set_gtk_property!(revealer, :reveal_child, reveal)
    end
    add_controller(overlay, ctrl)

    show(win)
    return win
end

# Belépési pont – külön futtatáshoz (opcionális)
if abspath(PROGRAM_FILE) == @__FILE__
    # Mock world/rt – csak UI kipróbálásához
    world = (; E = 3.0)
    rt = (; paused = Observable(false))
    build_gtk_ui(world, rt)
end
