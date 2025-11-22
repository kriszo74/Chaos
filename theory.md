# Időgeometria modell jegyzet
- Forrás: idogeometria.hu (pl. /tuz-es-viz/, /idosuruseg-tetszologes-ponton/, /category/multtersuruseg/).
- Cél: a hullámtéri kölcsönhatás és az idősűrűség képlet (ρ = 1/(E - cosθ·RV)) következetes használata a kódban.

## Kódbeli entitások
- Source: act_p, RV, positions[k], radii[k]; hullámfront gömbök positions[k] középponttal, radii[k] sugárral.
- Időtengely: aktuális p = positions[i], következő p_next = positions[i+1] (ha nincs, RV irány a fallback).
- World: E, density, t; hullámtér frissítés update_radii! → apply_wave_hit!.

## Idősűrűség és taszítás
- cosθ = clamp( dot(hit_dir, axis_dir), -1, 1 ), ahol hit_dir = normalize(tgt.act_p - p), axis_dir az időtengely egységvektora.
- |v| = E - cosθ·|RV|, ρ = 1/|v| (idősűrűség reciproka a taszítási vektor hossza).
- Modellezett RV-tartomány: 0.1–5 praktikus érték között (elméletben 0..∞).

## Jelenlegi RV-frissítés (apply_wave_hit!)
- Ha tgt a gömbön belül van: hit_dir → új irány, v_mag = clamp(E - cosθ·|RV|, 0, 5).
- RV = hit_dir * v_mag (tiszta taszítás); ha vonzás kell, irányt lehet negálni vagy súlyozni (1-α)*RV + α*(-hit_dir).
- Null irány/axis esetén kihagyjuk a frissítést (megőrizzük a stabilitást).

## Nyitott ágak / TODO-k
- Vonzó mód implementálása (kapcsoló vagy paraméter).
- Idősűrűség visszacsatolása a sugár növekedésére vagy alpha/RR változtatására.
- RV clamp stratégia finomítása (pl. dinamikus limit E vagy density függvényében).
- Időtengely pontosítása: RV-ből származtatott offset vs. diszkrét positions[i+1].
