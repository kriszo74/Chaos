# Konfigurációs értékek és alapbeállítások.
# Később külső fájlból lesznek betöltve.
# Jelenleg placeholder, logika nélkül.

using TOML

function load_config!(; path::AbstractString = joinpath(@__DIR__, "..", "config.toml"))
    cfg = TOML.parsefile(path)
    alpha_values = Float32.(cfg["gui"]["ALPHA_VALUES"])
    fade_profiles = String.(cfg["gui"]["FADE_PROFILE_ORDER"])
    for tbl in cfg["presets"]["table"]
        for e in tbl["entries"]
            alpha = Float32(e["alpha"])
            @dbg_assert any(==(alpha), alpha_values) "Ismeretlen alpha a presets.table.entries-ben"
            fade = String(get(e, "fade", "off"))
            @dbg_assert any(==(fade), fade_profiles) "Ismeretlen fade a presets.table.entries-ben"
        end
    end
    return cfg
end

const CFG = load_config!()
const eps_tol = CFG["world"]["eps_tol"]

function find_entries_by_name(tables, name::AbstractString; key::AbstractString = "name")
    idx = findfirst(t -> t[key] == name, tables)
    isnothing(idx) && error("Hiányzó bejegyzés: $(key) = $name")
    return tables[idx]["entries"]
end

sort_pairs(tbl; by = last) = sort!(collect(tbl); by = by)
