# Canonization Fix Report

## Résumé
- Les ingrédients détectés conservent désormais leur `canonicalId` et affichent le libellé canonique provenant de Supabase dans l’UI.
- Les ajouts au panier fusionnent avec le catalogue quand un identifiant est disponible (agrégation, case à cocher, catégories).
- L’index local fournit au LLM un top 5 enrichi (nom + canonicalName) pour améliorer le mappage et le debug.

## Détails techniques
- `DetectedRow` transporte `canonicalId`; QuickImport applique le seuil 0.8, normalise sans dégrader la casse et trace les erreurs de décodage LLM.
- `AppState` gère les `ManualItem` liés au catalogue (stockage de l’id, fusion des quantités, affichage via `preferredName`, clés de checklist alignées).
- `CatalogIndex` revoit la normalisation, les heuristiques (exact/prefix/contains + simple ratio) et journalise les 5 meilleurs candidats.
- `Canonicalizer` et `OpenAIClient` véhiculent `{id, name, canonicalName}` vers le LLM et appliquent la valeur canonique issue du catalogue.
- Log de chargement catalogue uniformisé (`[AppState] ingredients loaded: <count>`).

## Tests
- `xcodebuild -project MealPlanneriOS.xcodeproj -scheme MealPlanneriOS -destination 'platform=iOS Simulator,name=iPhone 16' clean build`
