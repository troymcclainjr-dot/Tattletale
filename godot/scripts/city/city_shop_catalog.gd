extends RefCounted
## Reusable nonviolent stock. Progression owns money, ownership and equipped
## selections; this pure catalog never mutates a player or an account.
const SHOP_KIND := "corner_store"
const SHOP_ID := "old_york_pantry"
const CATEGORIES := {"bike": "Bicycle colors", "clothing": "Clothing", "food": "Food & drinks"}
const ITEMS := {
	"bike_teal": {"label": "Harbor teal bicycle", "category": "bike", "price": 45,
		"description": "A teal frame finish. Applied immediately; switch owned colors free.",
		"slot": "bike_color", "color": "238f91", "recovery": 0},
	"bike_sunshine": {"label": "Sunshine bicycle", "category": "bike", "price": 45,
		"description": "A warm yellow frame finish. Applied immediately; switch owned colors free.",
		"slot": "bike_color", "color": "e6b949", "recovery": 0},
	"bandana_ocean": {"label": "Ocean blue bandana", "category": "clothing", "price": 30,
		"description": "An ocean blue bandana color. Wear it now; switch owned bandanas free.",
		"slot": "bandana_color", "color": "467dba", "recovery": 0},
	"bandana_clay": {"label": "Terracotta bandana", "category": "clothing", "price": 30,
		"description": "A terracotta bandana color. Wear it now; switch owned bandanas free.",
		"slot": "bandana_color", "color": "b96548", "recovery": 0},
	"snack_granola": {"label": "Granola snack", "category": "food", "price": 6,
		"description": "Eat at the counter to recover up to 20 health. Only sold when hurt.",
		"slot": "", "color": "", "recovery": 20},
	"drink_water": {"label": "Bottled water", "category": "food", "price": 3,
		"description": "Drink at the counter to recover up to 10 health. Only sold when hurt.",
		"slot": "", "color": "", "recovery": 10},
}

static func definition(id: String) -> Dictionary:
	if not ITEMS.has(id):
		return {}
	var result: Dictionary = ITEMS[id].duplicate(true)
	result.id = id
	return result

static func item_ids() -> Array:
	return ITEMS.keys()

static func category_label(category: String) -> String:
	return str(CATEGORIES.get(category, category.capitalize()))

static func is_cosmetic(id: String) -> bool:
	return ITEMS.has(id) and not str(ITEMS[id].slot).is_empty()

## Compatible with progression's strict authored-item schema. Effect metadata
## remains here instead of weakening that schema or arming a goods item.
static func authored_items() -> Dictionary:
	var result := {}
	for id in ITEMS:
		var item: Dictionary = ITEMS[id]
		result[id] = {"kind": "goods", "label": item.label, "description": item.description,
			"price": item.price, "quantity": 1, "max": 1}
	return result

static func authored_shop() -> Dictionary:
	return {"label": "Neighborhood goods", "clerk_role": "clerk", "items": item_ids()}
