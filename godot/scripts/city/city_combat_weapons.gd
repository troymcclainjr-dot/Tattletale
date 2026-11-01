extends RefCounted
## Shared inventory and handling definitions. Automatic fire uses the same
## collision-tested bullet path as the pistol; only cadence/reload/handling vary.
const PROFILES := {
	"pistol": {"label": "Pistol", "magazine": 12, "interval": 0.24, "reload": 1.45, "damage": 46.0, "range": 90.0, "automatic": false},
	"uzi": {"label": "Uzi", "magazine": 30, "interval": 0.09, "reload": 1.9, "damage": 30.0, "range": 65.0, "automatic": true},
	"ak47": {"label": "AK47", "magazine": 30, "interval": 0.14, "reload": 2.3, "damage": 58.0, "range": 120.0, "automatic": true}
}
const MAX_RESERVE := 9999
static func profile(id: String) -> Dictionary:
	return PROFILES.get(id, PROFILES.pistol)
