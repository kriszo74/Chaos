# Konfigurációs értékek és alapbeállítások.
# Később külső fájlból lesznek betöltve.
# Jelenleg placeholder, logika nélkül.

using TOML

load_config(path::AbstractString = "config.toml") = TOML.parsefile(path)

const CFG = load_config()

