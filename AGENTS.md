1 ÁLTALÁNOS SZABÁLYOK

A) Csak sebészi módosítás engedélyezett:
- TÖRLÉS vagy PONTOS CSERE megengedett.
- Nincs újrafogalmazás, nincs tartalmi bővítés.
- A meglévő sorokat, bekezdéseket, struktúrát meg kell őrizni.

2 KOMMENTELÉS

D) Egy soros komment megengedett blokk-szintű szerkezetek (függvények, ciklusok stb.) felett, ha az a változtatás kontextusát segíti; továbbá egy programutasítás sor végén elhelyezett rövid komment is megengedett, de soha sem az utasítás sor előtt. Legyen tömör (≤100 karakter). Ne az épp aktuális átalakítást kommenteld, igyekezz inkább végleges kommentet adni.

3 STÍLUSPREFERENCIA

A) Pragmatikus KISS + „move-fast” prototipizálás; minimalista util / UNIX-szerű „kis eszköz” szemlélet. A tömörség és egyszerűség elsődleges; a guardok és „keményítés” később, célzottan kerüljenek be.

4 KÓDOLÁSI PREFERENCIÁK

A) Rövidzáras feltételek: egyszerű, egyutasításos esetekben használd az isnothing(x) || do_sg() / cond && action() mintát. Ha több utasítást kell feltételesen végrehajtani, használj if … end szerkezetet. Ne keverd === nothing-nel; az isnothing(x) a preferált.

B) Egyszerhasználatos lokálisok kerülése: ahol olvasható, preferáld az inline konstrukciót (pl. add_source!(Source(...))).

C) Fail‑fast elv: inkább dobjunk hibát, mint csendben visszaessünk (pl. direkt dict‑indexelés, ::Int assert).

D) Callback sorrend: az inicializáló állítások (pl. i_selected) után történjen a feliratkozás (on(...)).

E) Observable‑kötések: általános helper(ek)be szervezve, opcionális paraméterekkel (pl. mk_slider! → bind_to, transform).

F) Felesleges guardok kerülése: ha egy érték létezése garantált (pl. inicializálási sorrend miatt), ne használjunk @isdefined‑et.

G) Láncolt értékadás: használd rövid, mellékhatás‑mentes inicializálásoknál; pl. fig[1,1] = gl = GridLayout(). A kifejezés jobbra asszociatív, ezért ekvivalens a gl = GridLayout(); fig[1,1] = gl formával. Mellékhatásos vagy több lépcsős hívások láncolását kerüld, mert nehezíti a debuggolást.
