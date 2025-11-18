# Konfigurációs értékek és alapbeállítások.
# Később külső fájlból lesznek betöltve.
# Jelenleg placeholder, logika nélkül.

using TOML

load_config(path::AbstractString = "config.toml") = TOML.parsefile(path)

const CFG = load_config()

function find_entries_by_name(tables, name::AbstractString; key::AbstractString = "name")
    idx = findfirst(t -> t[key] == name, tables)
    isnothing(idx) && error("Hiányzó bejegyzés: $(key) = $name")
    return tables[idx]["entries"]
end
