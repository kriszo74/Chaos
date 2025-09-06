# SZABÁLYOK:

- Teljesítmény-első: minimalizált allokáció, előallokált pufferek, Observable-k újrafelhasználása; nincs felesleges ellenőrzés vagy védelem.
- Egyszerűség: "The best part is no part"; a legkisebb működő megoldás előnyben, felesleges rétegek kerülése.
- Kódstílus: magyar kommentek, angol azonosítók; logikai blokk előtt 1 soros magyarázat; trükkös részeknél célzott inline komment; ne kommenteljünk minden sort.
- API stabilitás: nem követelmény; gyors, inkrementális változtatások rendben.
- Kommunikáció: egy kérdés, egy válasz; minden módosítás előtt rövid egyeztetés és jóváhagyás.
- Git: közvetlen `main`; kb. 3–5 óránként beszédes commit (miért + mi változott). A commit üzeneteket én fogalmazom, push csak jóváhagyás után.
- Tesztelés: egyelőre manuális; automata tesztek akkor kerülnek be, amikor a program bonyolultabb lesz.
- Teljesítménymérés: akkor optimalizálunk, ha lassúnak érzed a programot.
- Platform: Windows + GLMakie; később NVIDIA/CUDA, ha szükséges (TODO a kódban).
- Encoding: UTF-8; meglévő mojibake fokozatos javítása.
- Verzió: Julia 1.10+.


# PARANCSOK:

- `i`: új feladat javaslatának kérése (írj annyit, hogy "i").


# WORKFLOW:

- Feladat kijelölése: egyeztessünk a következő megoldandó feladatról. Te is javasolhatsz, én is. Mindig rákérdezek, van-e aktuális feladat. Ha azt írod "javasolj", kitalálok egyet. A feladat szövege bekerül a dokumentumba.
- Egyeztetés: megbeszéljük a megoldás lépéseit és hogy mit miért módosítunk.
- Bontsuk részfeladatokra: pl. változó definiálása, függvény megírása; régi kód törlése a végén. A részfeladatok is bekerülnek ide.
- Implementálás: minimális patch, célzott kommentek, felesleg kerülése. Módosítás csak jóváhagyás után.
- Ellenőrzés: manuális futtatás/ellenőrzés; gond esetén gyors iteráció.
- Commit: beszédes üzenet (miért + mi változott), kb. 3–5 óránként; push `main`-re.
- Iteráció: következő kis feladat kiválasztása.
- Naplózás: a "FELADATOK" és "AKTUÁLIS FELADAT" szakaszokban vezetjük.


# AKTUÁLIS FELADAT:

- Nincs kijelölt feladat. Írd: "i", ha új javaslatot kérsz.


# JEGYZETEK:

- Vázlat következő ötletekhez:
  - Cache-eljük a gömb marker mesh-t, hogy ne generáljuk újra.
  - Automatikus nézet/zoom beállító segédfüggvény a forrásokhoz.
  - Instanced renderelés több forráshoz, egyetlen meshscatter-rel.
  - UTF-8 javítás a forrásokban (kommentek, stringek) – folyamatban a feladatlistán.
- Tipp: Observable értékeknél inkább `x[] = ...` frissítés, ne új Observable-t hozzunk létre; így kevesebb allokáció.
- Tipp: a `transparency = true` költséges lehet; ha valahol nem kell átlátszóság, kapcsold ki.

# FELADATOK:

- Itt vezetjük a feladatokat és részfeladatokat. Új elemek a lista tetejére kerülnek. Rövid elfogadási kritériumok javasoltak.

- GUI és vezérlők
  - `rebuild_controls!`: preset váltáskor a vezérlők dinamikus újraépítése.
  - Alpha-kezelés: forrásonkénti csúszkák automatikus létrehozása és kötése a plothoz.
  - Play/Pause gomb felirat/ikon állapothelyes váltása, szimulációs állapot egységes kezelése.

- 3D jelenet és kamera
  - `Axis3` kiváltása `LScene`-re (deprekált elem elhagyása), konzisztens ortografikus kamera. [KÉSZ]
  - Automatikus nézet/limitek a források és `max_t` alapján; kezdeti zoom/pozíció beállító segédfüggvény.

- Teljesítmény és architektúra
  - Instanced renderelés: egyetlen `meshscatter!` attribútumokkal (pozíció, sugár, szín, alfa) több forrásra.
  - Pufferek: sugarak és pozíciók előallokálása; Observable-ök újrafelhasználása fölösleges új példányok nélkül.
  - Mozgásmodell: `Source` tisztítása (kezdeti `p0`, `RV`, `bas_t`), származtatott állapotok számítása futás közben.
  - GPU-kísérlet: sugarak frissítésének portolása CUDA.jl-re, ha a CPU-s megoldás szűk keresztmetszet.

- Kódminőség és karbantarthatóság
  - Forrásfájlok kódolásának javítása (UTF-8), kommentek tisztítása.
  - Rövid docstringek a főbb függvényekhez (`setup_scene`, `add_source!`, `update_radii`, `start_sim!`).

