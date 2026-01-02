# Konfigurációs értékek és alapbeállítások.
# Később külső fájlból lesznek betöltve.
# Jelenleg placeholder, logika nélkül.

using TOML

function load_config!(path::AbstractString = joinpath(@__DIR__, "..", "config.toml"))
    cfg = TOML.parsefile(path)
    alpha_values = Float32.(cfg["gui"]["ALPHA_VALUES"])
    for tbl in cfg["presets"]["table"]
        for e in tbl["entries"]
            alpha = Float32(e["alpha"])
            @dbg_assert any(==(alpha), alpha_values) "Ismeretlen alpha a presets.table.entries-ben"
        end
    end
    return cfg
end

const CFG = load_config!()

function find_entries_by_name(tables, name::AbstractString; key::AbstractString = "name")
    idx = findfirst(t -> t[key] == name, tables)
    isnothing(idx) && error("Hiányzó bejegyzés: $(key) = $name")
    return tables[idx]["entries"]
end

sort_pairs(tbl; by = last) = sort!(collect(tbl); by = by)
