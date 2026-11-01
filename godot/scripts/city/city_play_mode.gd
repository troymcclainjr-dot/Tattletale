extends RefCounted
## Playable-feature policy for the nonviolent build. Pure compile-time
## constants and static queries: no state, no node, no input, no save data.
## Nothing here is exposed to players (no setting, command-line switch, console
## or debug hook); changing a flag means changing this file and rebuilding.
##
## The flags gate PLAYER-FACING capability only. Every backend system they
## touch (combat, driving, reputation) keeps its code, its signals and its
## saved state so a later build can turn a flag back on without migration.
##
## PLAYER_COMBAT false
##   The explorer cannot equip, aim, reload, punch, stomp or fire, and the
##   combat service never consumes player input (LMB/RMB/1-4/R fall through to
##   other services, e.g. basketball and camera orbit). Saved weapon ownership
##   and ammunition are kept verbatim, but a restored loadout is always
##   holstered to fists. NPC and police combat, incoming player damage,
##   knockdown, healing and law recovery are unaffected. Gun stores
##   (CLOSED_SHOP_KINDS) are physically shut, unadvertised and sell nothing;
##   weapon/ammo items cannot be bought anywhere. Coercive story options
##   (RETIRED_STORY_OPTIONS) are not offered and are refused if committed.
## PLAYER_DRIVING false
##   No car can be boarded (F falls through, e.g. to the bicycle). The starter
##   car still spawns as an ordinary parked car so the vehicle registry and
##   its saves stay valid, but it has no label, prompt or map marker.
## ALIGNMENT false
##   Snitch/Gangsta never change, are never shown, and never gate anything:
##   alignment requirements are pruned from content gates, and
##   offenses earn nothing. Stored values are preserved for compatibility.
##   Money, relationships, durable choices and errands are unaffected.

const PLAYER_COMBAT := false
const PLAYER_DRIVING := false
const ALIGNMENT := false

## Shop kinds (pen_lucy_shops.json "kind") closed while PLAYER_COMBAT is off.
const CLOSED_SHOP_KINDS := ["gun"]
## Progression item kinds that arm the player; unsellable while PLAYER_COMBAT is off.
const PLAYER_WEAPON_ITEM_KINDS := ["weapon", "ammo"]
## decision id -> option ids that are coercive or violent. Authored data stays
## intact; these are simply never offered or committed while PLAYER_COMBAT is
## off. Every decision must keep at least one non-retired option.
const RETIRED_STORY_OPTIONS := {"petals_call": ["intimidate"], "petals_final": ["intimidate_firm"]}
## progression dialogue_examples that only exist to discuss alignment.
const ALIGNMENT_DIALOGUE_EXAMPLES := ["lookout_reputation"]

static func player_combat_enabled() -> bool:
	return PLAYER_COMBAT

static func player_driving_enabled() -> bool:
	return PLAYER_DRIVING

static func alignment_enabled() -> bool:
	return ALIGNMENT

static func shop_kind_open(kind: String) -> bool:
	return PLAYER_COMBAT or not kind in CLOSED_SHOP_KINDS

static func item_kind_sellable(kind: String) -> bool:
	return PLAYER_COMBAT or not kind in PLAYER_WEAPON_ITEM_KINDS

static func story_option_allowed(decision: String, option: String) -> bool:
	return PLAYER_COMBAT or not option in RETIRED_STORY_OPTIONS.get(decision, [])

static func dialogue_example_allowed(id: String) -> bool:
	return ALIGNMENT or not id in ALIGNMENT_DIALOGUE_EXAMPLES

## Read-only summary for HUD, diagnostics and fixtures.
static func status() -> Dictionary:
	return {"player_combat": PLAYER_COMBAT, "player_driving": PLAYER_DRIVING, "alignment": ALIGNMENT,
		"closed_shop_kinds": [] if PLAYER_COMBAT else CLOSED_SHOP_KINDS.duplicate(),
		"retired_story_options": {} if PLAYER_COMBAT else RETIRED_STORY_OPTIONS.duplicate(true)}
