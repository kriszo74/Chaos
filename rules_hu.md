prompt (emlékeztető magamnak, ezt hagyd figyelmen kívül): 1. Ügynök mód: Olvasd be rules_hu.md-t és az összes .jl file-t a github csatlakozón keresztül! 2. Vászon: Tedd ki őket külön-külön vászonra változtatás nélkül!

1 WORKFLOW

A) Töltsd be ezt a szabályzatot (rules_hu.md) egy vászonra változatlanul, utána rögtön main.jl-t és addig meg se állj, amíg az összes kódvászon létre nem jött (egy fájl = egy vászon).

B) Fő feladat meghatározása: ha minden vászon létrejött, akkor kérdezd meg, hogy mi a feladat.

C) Amíg a feladat pontosítása szükséges, maximum három célzott, rövid kérdést tehetsz fel. Ha marad bizonytalanság, a következő körben ismét legfeljebb három kérdés következik, egészen addig, amíg minden kérdés tisztázottá nem válik.

D) Írd le röviden, mit módosítasz és miért.

E) Változtatás‑típus címke: minden lépésnél tüntesd fel: \[NFC] (no functional change) / \[refactor] / \[perf] / \[bugfix] / \[behavior]. Commit‑üzenetben is használd.

F) Jelezd, ha futtatni vagy tesztelni kellene, és milyen eredményt vársz.

G) Hiba esetén: bármilyen fordítási vagy futási hiba észlelésekor AZONNAL kapcsold be az ügynök módot, és nézz utána a hiba okának a hivatalos dokumentációban / release note-okban. A megoldási javaslatot rövid forrásmegjelöléssel add meg, majd kérj jóváhagyást a patchre.

H) Minden módosítás előtt kérj jóváhagyást: igen (vagy i). Jóváhagyás nélkül ne írj a kódhoz.

I) Kérdés vagy döntési pont esetén a lehetséges következő lépéseket mindig sorszámozva add meg (1., 2., 3.), rövid cím + 1–2 sor indoklással. Példa: 1) azonnali végrehajtás; 2) több lépéses módszer; 3) elhalasztás mérésig.

J) Vászonváltás jelzése: Csak akkor kérj váltást, ha a következő lépésben azon a vásznon tényleges szerkesztést akarsz végezni. A váltást a válasz végén jelezd: Váltás: \<vászon neve>. Váltás az opcióknál: döntési felsorolásnál minden opció végén szerepeljen: Váltás: \<vászon neve>. Ha a célvászon még nem létezik (pl. code/main.jl), ne váltást kérj, helyette hozd létre, amint megkapod a tartalmát.

K) Feladatlista: csak az aktuális fejlesztés közben felmerülő, el ne felejtendő teendőket jegyezzük fel TODO komment formájában. Emiatt viszont ne kérj vászonváltást, inkább a válasz végén egy másolható chat‑buborékban listázd (GYORSTASK).

L) IO‑min ritmus: Egy üzenet = (A) 1 patch‑javaslat + (B) 2–3 kérdés a következő feladathoz. Patch csak igen (vagy i) után végrehajtandó.

M) Patch sablon: \[változtatás‑típus], cél vászon, rövid Miért, rövid Diff (csak érintett rész), Elvárt, Teszt/javaslat, és a kérdés: „Végrehajthatom azonnal?”

N) Commit‑politika: Conventional Commits stílus, egysoros első sor (lehetőleg). kb. 4-5 órai munka befejeztével megy a commit. Ha úgy látod, javasolj commitot.

O) Száljelölések (# ): A beszélgetés elején szereplő „#2”, „#3” stb. jelöléseket teljesen ignoráljuk.

P) Parancsadás formátuma: : \<utasítás>. A hivatkozott pont tartalmát alkalmazd.
Példa: „1N: adj commit üzenetet” → az 1. fejezet N) pontja szerint járj el.

2 MÓDOSÍTÁSI SZABÁLYOK

A) Egyszerre csak egy logikai változtatást hajts végre a kódban (új változó, új függvény, kis refaktor stb.).

B) Csak a lépéshez tartozó sorokhoz nyúlj. A többi sort ne módosítsd, ne nevezd át, ne rendezd át és ne formázd. Tilos automatikus formázót, import‑rendezést vagy linter „auto‑fixet” futtatni az egész fájlra.

C) Ha a módosítás nem csökkenti a fájlméretet / összetettséget vagy nem hoz kimutatható hasznot, halaszd egy TODO-ba.

D) Egy soros komment megengedett blokk-szintű szerkezetek (függvények, ciklusok stb.) felett, ha az a változtatás kontextusát segíti; továbbá egy programutasítás sor végén elhelyezett rövid komment is megengedett, de soha sem az utasítás sor előtt. Legyen tömör (≤100 karakter). Ne az épp aktuális átalakítást kommenteld, igyekezz inkább végleges kommentet adni.

3 STÍLUSPREFERENCIA

A) Pragmatikus KISS + „move-fast” prototipizálás; minimalista util / UNIX-szerű „kis eszköz” szemlélet. A tömörség és egyszerűség elsődleges; a guardok és „keményítés” később, célzottan kerüljenek be.

4 KÓDOLÁSI PREFERENCIÁK (Ha parancsként kapod, először chatbuborékokban add vissza az esetleges módosításokat)

A) Rövidzáras feltételek: egyszerű, egyutasításos esetekben használd az isnothing(x) || do\_sg() / cond && action() mintát. Ha több utasítást kell feltételesen végrehajtani, használj if … end szerkezetet. Ne keverd === nothing-nel; az isnothing(x) a preferált.

B) Egyszerhasználatos lokálisok kerülése: ahol olvasható, preferáld az inline konstrukciót (pl. add\_source!(Source(...))).

C) Fail‑fast elv: inkább dobjunk hibát, mint csendben visszaessünk (pl. direkt dict‑indexelés, ::Int assert).

D) Callback sorrend: az inicializáló állítások (pl. i\_selected) után történjen a feliratkozás (on(...)).

E) Observable‑kötések: általános helper(ek)be szervezve, opcionális paraméterekkel (pl. mk\_slider! → bind\_to, transform).

F) Felesleges guardok kerülése: ha egy érték létezése garantált (pl. inicializálási sorrend miatt), ne használjunk @isdefined‑et.

G) Láncolt értékadás: használd rövid, mellékhatás‑mentes inicializálásoknál; pl. fig\[1,1] = gl = GridLayout(). A kifejezés jobbra asszociatív, ezért ekvivalens a gl = GridLayout(); fig\[1,1] = gl formával. Mellékhatásos vagy több lépcsős hívások láncolását kerüld, mert nehezíti a debuggolást.

5 FORMÁZÁS

A) Karakterkódolás: UTF‑8 (BOM nélkül).

B) Sorvégek: CRLF.

C) Záró újsor: kötelező (insert\_final\_newline = true).

D) Behúzás: szóköz, 4 karakter (indent\_style = space, indent\_size = 4).

E) Felesleges záró szóközök vágása: igen (trim\_trailing\_whitespace = true).

F) dupla sortörések törlése
