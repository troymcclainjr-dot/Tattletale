# Old York Pantry commerce — 2026-11-01

The existing Old York Pantry now has a usable exterior service window. Its reusable catalog offers two bicycle colors ($45 each), two bandana colors ($30 each), granola ($6, up to 20 health), and water ($3, up to 10 health). Owned cosmetics can be equipped again for free. Ownership, equipped choices, and money survive save/load through the existing progression schema.

Walk to the marked counter and press **Interact** (default **E**, remappable in settings). Dismount first. Select a catalog item to buy or equip; **Escape** closes the catalog. The physical sign and proximity prompt follow the current Interact binding.

Food and water restore health immediately and charge only when recovery succeeds. They do not add inventory, hunger, thirst, or maintenance meters, and cannot bypass death, downed recovery, combat, or law restrictions. Bandana materials are isolated from skin and neighboring characters; bicycle paint applies to walking and mounted appearances. Default appearance restores the original materials.

Validation was executed serially by the root agent:

- Commerce/input smoke: **44 passed, 0 failed**, including transactions, durable ownership, invalid saves, recovery gates, wrong-side counter access, and semantic input rebinding.
- Full-city shopping/save/load: **35 passed, 0 failed**, including normal walking access, actual purchase controls, walking/rider cosmetics, unchanged skin, wallet persistence, and exact restored-player clearance.
- Actual imported-model and procedural-model cosmetics regression: **0 failures**, covering material isolation, persistent selection, and default restoration.
- Rendered pantry frontage, purchase panel, and cosmetic comparisons inspected. Local tracked changes pass `git diff --check`.

The full-city save fixture uses a private checkpoint rather than the player's save. Saving while pressed against the shelf may store a position 1–4 cm outward on the verified pantry apron; each candidate passes the full existing safety checks, and the live player is never moved by saving.

Scope is one exterior storefront and this modest six-item catalog. There are no new quests, interior access, food inventory, guns, ammunition, driving, or player combat changes. Engine regressions live in `godot/tests/city_commerce_smoke.gd`, `city_commerce_cosmetics.gd`, and `city_commerce_city_session.gd`; the full-city fixture requires `-- --offscreen-validation --session-run-id=<unique>`.
