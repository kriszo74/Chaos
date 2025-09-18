prompt (emlékeztető magamnak, ezt hagyd figyelmen kívül): Olvasd el rules_hu.md-t a github csatlakozón keresztül. További szabályok a WORKFLOW-ben leírtak szerint.

WORKFLOW

* Töltsd be ezt a szabályzatot (rules_hu.md) egy vászonra változatlanul, utána rögtön main.jl-t és addig meg se állj, amíg az összes kódvászon létre nem jött (egy fájl = egy vászon).

* Fő feladat meghatározása: ha minden vászon létrejött, akkor kérdezd meg, hogy mi a feladat.

* Amíg a feladat pontosítása szükséges, maximum három célzott, rövid kérdést tehetsz fel. Ha marad bizonytalanság, a következő körben ismét legfeljebb három kérdés következik, egészen addig, amíg minden kérdés tisztázottá nem válik.

* Írd le röviden, mit módosítasz és miért.

* Változtatás‑típus címke: minden lépésnél tüntesd fel: \[NFC] (no functional change) / \[refactor] / \[perf] / \[bugfix] / \[behavior]. Commit‑üzenetben is használd.

* Jelezd, ha futtatni vagy tesztelni kellene, és milyen eredményt vársz.

* Minden módosítás előtt kérj jóváhagyást: igen (vagy i). Jóváhagyás nélkül ne írj a kódhoz.

* Kérdés vagy döntési pont esetén a lehetséges következő lépéseket mindig sorszámozva add meg (1., 2., 3.), rövid cím + 1–2 sor indoklással. Példa: 1) azonnali végrehajtás; 2) több lépéses módszer; 3) elhalasztás mérésig.

* Vászonváltás jelzése: Csak akkor kérj váltást, ha a következő lépésben azon a vásznon tényleges szerkesztést akarsz végezni. A váltást a válasz végén jelezd: Váltás: \<vászon>. Váltás az opcióknál: döntési felsorolásnál minden opció végén szerepeljen: Váltás: \<vászon>. Ha a célvászon még nem létezik (pl. code/main.jl), ne váltást kérj, helyette hozd létre, amint megkapod a tartalmát.

* Feladatlista: csak az aktuális fejlesztés közben felmerülő, el ne felejtendő teendőket jegyezzük fel TODO komment formájában. Emiatt viszont ne kérj vászonváltást, inkább a válasz végén egy másolható chat‑buborékban listázd (GYORSTASK).

* IO‑min ritmus: Egy üzenet = (A) 1 patch‑javaslat + (B) 2–3 kérdés a következő feladathoz. Patch csak igen (vagy i) után végrehajtandó.

* Patch sablon: \[változtatás‑típus], cél vászon, rövid Miért, rövid Diff (csak érintett rész), Elvárt, Teszt/javaslat, és a kérdés: „Végrehajthatom azonnal?”

* Commit‑politika: Conventional Commits stílus, egysoros első sor (lehetőleg). kb. 4-5 órai munka befejeztével megy a commit. Ha úgy látod, javasolj commitot.

MÓDOSÍTÁSI SZABÁLYOK

* Egyszerre csak egy logikai változtatást hajts végre a kódban (új változó, új függvény, kis refaktor stb.).

* Csak a lépéshez tartozó sorokhoz nyúlj. A többi sort ne módosítsd, ne nevezd át, ne rendezd át és ne formázd. Tilos automatikus formázót, import‑rendezést vagy linter „auto‑fixet” futtatni az egész fájlra.

* Ha a módosítás nem csökkenti a fájlméretet / összetettséget vagy nem hoz kimutatható hasznot, halaszd egy TODO-ba.

* Egy soros komment megengedett blokk-szintű szerkezetek (függvények, ciklusok stb.) felett, ha az a változtatás kontextusát segíti; továbbá egy programutasítás sor végém  elhelyezett rövid komment is megengedett, de soha sem az utasítás sor előtt. Legyen tömör (≤100 karakter). Ne az épp aktuális átalakítást kommenteld, igyekezz inkább végleges kommentet adni.

STÍLUSPERFERENCIA

Pragmatikus KISS + „move-fast” prototipizálás; minimalista util / UNIX-szerű „kis eszköz” szemlélet. A tömörség és egyszerűség elsődleges; a guardok és „keményítés” később, célzottan kerüljenek be.

KÓDOLÁSI PREFERENCIÁK

* Rövidzáras feltételek: használd egységesen az isnothing(x) || do\_sg() mintát (ne keverd === nothing-nel).

* Egyszerhasználatos lokálisok kerülése: ahol olvasható, preferáld az inline konstrukciót (pl. add\_source!(Source(...))).

* Fail‑fast elv: inkább dobjunk hibát, mint csendben visszaessünk (pl. direkt dict‑indexelés, ::Int assert).

* Callback sorrend: az inicializáló állítások (pl. i\_selected) után történjen a feliratkozás (on(...)).

* Observable‑kötések: általános helper(ek)be szervezve, opcionális paraméterekkel (pl. mk\_slider! → bind\_to, transform).

* Felesleges guardok kerülése: ha egy érték létezése garantált (pl. inicializálási sorrend miatt), ne használjunk @isdefined‑et.

FORMÁZÁS

* Karakterkódolás: UTF‑8 (BOM nélkül).

* Sorvégek: CRLF.

* Záró újsor: kötelező (insert\_final\_newline = true).

* Behúzás: szóköz, 4 karakter (indent\_style = space, indent\_size = 4).

* Felesleges záró szóközök vágása: igen (trim\_trailing\_whitespace = true).

* Folyamatosan figyeld a dupla sortöréseket és szüntesd meg.
