1 ÁLTALÁNOS SZABÁLYOK

A) Csak sebészi módosítás engedélyezett:
- TÖRLÉS vagy PONTOS CSERE megengedett.
- Nincs újrafogalmazás, nincs tartalmi bővítés.
- A meglévő sorokat, bekezdéseket, struktúrát meg kell őrizni.
- Kövesd az .editorconfig kódolási/sorvég beállításait (UTF-8, CRLF).

B) Stíluspreferencia: Pragmatikus KISS + „move-fast” prototipizálás; minimalista util / UNIX-szerű „kis eszköz” szemlélet. A tömörség és egyszerűség elsődleges; a guardok és „keményítés” később, célzottan kerüljenek be.

C) Műveleti jelzők:
- ACK = módosítás engedélyezése;
- NOP = nincs módosítás, csak egyeztetés.

D) Parancsprotokoll (ACK/NOP + célzás):
- `ACK:PAR` = hajtsd végre a parancsot kérdés nélkül az irányelvek szerint.
- `ACK:KOM` = alkalmazd a kommentelési szabályokat; fésüld át és írd át.
- Opcionális szűkítés: `ACK:KOM source.jl` csak a megadott fájlra.
- További szűkítés: `ACK:KOM add_source!` csak a megadott azonosítóra.
- Tartomány: `ACK:KOM source.jl 31:41` csak a megadott sorokra.
- `NOP:...` = csak javasolj, ne módosíts.

2 KÓDOLÁSI SZABÁLYOK, PARANCSOK

A) KOM - Kommentelési szabályok: 
- magyarul kommentelj, ne tedd a prancskódot (KOM) a kommentbe.
- korábbi kommenteket is módosíthatod, átfogalmazhatod.
- legyen tömör (≤100 karakter);
- egy soros komment megengedett blokk-szintű szerkezetek (függvények, ciklusok stb.) felett, ha az a változtatás kontextusát segíti; 
- továbbá egy programutasítás sor végén elhelyezett rövid komment is megengedett.
- ne az épp aktuális átalakítást kommenteld, igyekezz inkább végleges kommentet adni.

B) Rövidzáras feltételek: egyszerű, egyutasításos esetekben használd az isnothing(x) || do_sg() / cond && action() mintát. Ha több utasítást kell feltételesen végrehajtani, használj if … end szerkezetet. Ne keverd === nothing-nel; az isnothing(x) a preferált.

C) INL - Egyszerhasználatos lokálisok kerülése: ahol olvasható, preferáld az inline konstrukciót (pl. add_source!(Source(...))).

D) Fail-fast elv: ne clampelj hívási pontokon; invariánsok ellenőrzése helper(ek)ben, debug módban @dbg_assert-tel (@static if DEBUG_MODE; @assert …; end). Release-ben 0 overhead.

E) Callback sorrend: az inicializáló állítások (pl. i_selected) után történjen a feliratkozás (on(...)).

F) Observable‑kötések: általános helper(ek)be szervezve, opcionális paraméterekkel (pl. mk_slider! → bind_to, transform).

G) GRD - Felesleges guardok kerülése: ha az értéktartományt a flow garantálja, ne tegyél @isdefined-et és ne clampelj; lásd 3 C).

H) LAN - Láncolt értékadás: használd rövid, mellékhatás‑mentes inicializálásoknál; pl. fig[1,1] = gl = GridLayout(). A kifejezés jobbra asszociatív, ezért ekvivalens a gl = GridLayout(); fig[1,1] = gl formával. Mellékhatásos vagy több lépcsős hívások láncolását kerüld, mert nehezíti a debuggolást.
