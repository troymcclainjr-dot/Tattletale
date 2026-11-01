# Authoring neighborhood cases

Cases are JSON files under `godot/assets/data/cases/`. The engine
(`scripts/city/city_case_engine.gd`) runs them through the same paths as the six
original cases: the case marker, yellow route, HUD objective, conversations,
ledger, phone Cases app, checkpoints and the existing case reward. Nothing in a
case file can hurt anyone: the verbs are talking, looking, carrying, photographing,
following at a distance, getting clear and reporting.

## What exists today

| | Status |
|---|---|
| `parcel_report.json` | **Full content.** The original "The opened parcel" case, migrated: same id, title, 150 points, 4 stages, contacts, clue, placement and lines. Adds a phone-photo alternative at the scene, a recorded witness interview and an evidence-gated report. Playable now; the original authored steps in `city_missions.gd` remain as the fallback if the file fails validation. |
| `templates/*.json` (7) | **Authoring scaffolds**, not content. Each copies the shape of an original case; every text is `[draft] …` until a case overrides it. |
| `examples/rapid_authoring.example.json` | **Example**, never loaded (not in `index.json`). Validated by the test suite so it stays correct. |
| New story cases | **None.** No new specific cases were written. |

The other five original cases still run from `city_missions.gd` unchanged; each
has a matching template if they are migrated later.

## Five-minute case

1. Copy `examples/rapid_authoring.example.json` to `cases/<id>.json`.
2. Set a new `id` (lowercase, stable forever), `title`, `reward.points`, the
   template `params` (who, which prop, how far along the walk).
3. Override the texts by id (see "Templates"). Leave `"status": "draft"` while any
   `[draft]` text remains: drafts validate but are never offered to players.
4. Add the file to `"cases"` in `index.json`.
5. Run the case tests (below). The library report lists every error and every
   `[draft]` placeholder still in place; remove `status` (defaults to `ready`)
   when the text is final.

## File layout

```
assets/data/cases/
  index.json             load list: "templates": [...], "cases": [...] (relative paths)
  case_schema.json       editor aid (JSON Schema); the validator is city_case_schema.gd
  templates/<id>.json    {"schema": 1, "template": "<id>", "about", "params", "case": {...}}
  <case>.json            one case
  examples/              not loaded
```

Keys that start with `_` are notes and ignored everywhere.

## Template merge

A case with `"template": "<id>"` starts from that template's `case` object:

* objects merge key by key; a `null` value deletes the template's key;
* arrays of objects with `"id"` merge by id (template order kept, new ids appended):
  `stages`, each stage's `objectives`, interview `topics`;
* any other value replaces the template's;
* `{param}` inside template text is filled from the case's `params`; a value that is
  exactly `"{param}"` keeps the param's type (numbers for distances and counts).
  A missing param rejects the case.

## Fields

### Case

| field | type | notes |
|---|---|---|
| `schema` | 1 | required |
| `id` | `^[a-z][a-z0-9_]{1,47}$` | stable: saves, rewards and the ledger key on it. Never reuse. Story/errand ids are reserved. |
| `version` | int ≥ 1 | raise when stages/objectives change (see Saves) |
| `title`, `summary` | text | title shows on the HUD and ledger |
| `status` | `ready` \| `draft` | draft = validates, never offered, not in the ledger |
| `legacy_slot` | bool | only to migrate one of the six original ids; must keep title, reward and stage count |
| `reward.points` | int 0..10000 | community points, paid once (see Rewards) |
| `discovery` | object | how it starts |
| `participants` | object | roles → people |
| `props` | object | clue objects placed along the walk |
| `evidence` | object | evidence ids the objectives grant and reports require |
| `stages` | array 1..12 | in order; each has 1..6 objectives |
| `outcomes` | object | how it can end; default `{"resolved": {"rewarded": true}}` |
| `completion.outcome` | id | outcome when the last stage completes (default `resolved`) |
| `incident` | object | `{"templates": [...], "radius": m}` for incident-triggered cases |

### discovery

`trigger`: `offer` (a giver offers it; default), `incident` (starts when the
player is within `incident.radius` of a live incident of a listed template and no
case is active), `none` (started by code). `givers`: participant roles who offer
it. `requires_completed`: case ids that must be resolved first (`locked_reason`
explains it in the ledger). `pitch`, `accept`, `decline`: offer conversation
(defaults reproduce the original "Could you help with something on the block?").
`start_notice`: notice on start.

### participants

```json
"officer": {"actors": ["@police"], "label": "Officer", "bind": "step", "stand_in_line": "…"}
```

* `actors`: candidates in order; the first one present (alive, not in custody, not
  fighting, somewhere reachable) takes the role. `@police`, `@street`,
  `@organizer`, `@carrier` expand to the narrative's stand-in lists.
  `incident:offender|victim|witness` come from the bound incident.
* `bind`: `case` (default) keeps the first person who acted in the role for the
  rest of the case (a witness's account is theirs); `step` lets anyone listed take
  each step (any officer can take a report).
* `label`: ledger name ("Required contact Officer has died.").
* `speaker`: conversation name for the first candidate; others use their own names.
* `stand_in_line`: first line when someone other than the first candidate answers.

Unavailable people: absent → the step waits (HUD says "… is not around right
now"); in custody → the attempt pauses without a reward and can be taken again
later; every existing candidate dead → the attempt ends without a reward
("Case closed without a reward: a required contact has died."). An "any" stage is
blocked only when all of its alternatives are.

### props

```json
"scene": {"builder": "parcel", "title": "OPENED PARCEL", "placement": {"route_metres": 55.0, "radius": 0.42},
          "solid": false, "photo_height": 0.2, "photo_radius": 0.3, "tag_height": 0.95}
```

Builders are the original clue models: `satchel`, `parcel`, `dumped_bags`,
`tool_caddy`, `torn_notice`, `lantern`, `checkpoint`, `crate`, `marker`. Placement
searches the authored walk near `route_metres` with the original capsule,
pavement and stair checks; a case never starts (or restores) half placed. Props are
passable unless `solid`. Each prop is a phone photo subject
`case:<case_id>:<prop_id>`.

### evidence

`{"<id>": {"kind": "observation|photo|testimony|item|report", "label": "…"}}`.
Objectives `grants` evidence; reports `requires_evidence`. Each piece is recorded
once with where it came from (objective, source, minute, witness, photo id,
measured distance) and emitted once as `missions.evidence_recorded`.

### stages

`{"id", "objective": "HUD text", "complete": "all"|"any", "objectives": [...]}`.
`all` needs every non-optional objective; `any` completes with the first one done
(alternatives such as "inspect it or photograph it").

### objectives (common fields)

`id` (unique in the case), `verb`, `objective` (text), `prompt` (`"E  …"`, E verbs),
`dialogue`, `speaker`, `grants`, `requires_evidence` (`"a|b"` = either),
`requires` (objective ids first), `optional`, `ends_case` (outcome id),
`notice`, `hide_props` (`["prop:x"]` removed when done).

### verbs

| verb | fields | player does | from |
|---|---|---|---|
| `talk` | `target` role | E, confirm the reply | every original case |
| `examine` | `target` prop, `hide_after` | E at the prop | inspect/record steps |
| `collect` | `target` prop | E; the prop is carried | satchel, caddy, crimes "follow the money" |
| `deliver` | `target` role, `item` prop | E while carrying it | returns |
| `interview` | `target` role, `greeting`, `topics[{id, ask, answer, required, after}]`, `farewell` | asks each required topic in conversation | witness steps |
| `report` | `target` role, `requires_evidence`, `greeting`, `missing`, `dialogue`, `incident` | files with an officer | crimes "call it in" |
| `photo` | `subject`, `max_distance`, `min_distance`, `min_centrality`, `count`, `min_interval_minutes`, `require_tags`, `time_window{from,to}`, `area{near,radius}` | takes a phone photo | crimes "spy"/mail photos |
| `visit` | `location`, `radius`, `dwell` | stands there | confirm-the-site steps |
| `follow` | `subject`, `min_distance`, `max_distance`, `seconds`, `unseen`, `view_range`, `view_cone`, `lose_after`, `on_fail` | keeps them in view without being noticed | crimes mail tail |
| `flee` | `from`, `distance`, `within`, `on_timeout` | gets clear of a place/person | leave a scene |
| `await_incident` | `states` | waits for the police outcome | incident follow-up |

References: a participant role (`owner` or `participant:owner`), `prop:<id>`,
`actor:<id>`, `incident:<offender|victim|witness|location>`, places
`route:<metres>` and `pos:x,y,z`.

**Trusted interviews.** Each question is a conversation reply carrying a hook
(`case_interview`, case, stage, objective, topic, witness). It counts only for the
role's actual person, in range with clear line of sight, at the current stage, for
an existing topic whose `after` topics were asked. A bare E press, a reply from
another stage, another witness or out of range records nothing; asking again
records nothing new.

**Reports.** The officer offers "file" only when every `requires_evidence` entry is
held; otherwise the `missing` line (or a generated list) is shown. With
`"incident": true` the report goes to `incidents.report_incident(id, "player",
{"channel": "case"})` and its answer is final (a refusal such as `not_witnessed`
leaves the case unchanged).

**Photos.** Evidence comes only from the phone's `photo_captured` context, never
from a gallery file. A photo counts when the phone listed the subject with line
of sight at shutter time *and* the live world agrees: the subject is still where
it was tested, inside the frame of the recorded pose, within the distance band and
framing (`min_centrality`), with a clear static line from the lens (a wall right
in front of the subject still blocks it), within `time_window`/`area`, not before
the case started and not stale. Each photo id is evaluated once (the replay ring
is saved). `count` > 1 needs separate photos `min_interval_minutes` apart.

### outcomes

`{"<id>": {"rewarded": bool, "terminal": bool, "banner": "…", "notice": "…"}}`.
A rewarded outcome is final: the case joins `completed_ids`, its points are added
once and paid once. An unrewarded `terminal` outcome closes the case for good
(ledger "closed"); any other unrewarded outcome just ends the attempt (retry
later). `follow.on_fail`, `flee.on_timeout` and `ends_case` may name an outcome.

## Rewards and money

Points go to the community score; money is paid once through the existing
`progression.reward_case(id, progression.case_money(id, points))` at the
configured rate (`pen_lucy_progression.json` `cases.money_per_point`, overrides,
the case's reputation action). There are no new purchases and no second payout
path: a replayed hook, a reloaded checkpoint or a duplicate reward call pays nothing.

## Saves

The missions checkpoint keeps `active_id`, `stage`, `completed_ids`, `score` and
adds `case_engine`: the active case's objective progress, bound people, evidence,
carried props, the closed/record ledgers and the photo replay ring. It is
canonical: snapshot → JSON → restore → snapshot is identical, and restoring twice
is the same as once.

* Never rename an `id`, evidence id or objective id that shipped; add new ones.
* Raise `version` when stages change. A saved record from an older version
  resumes from its saved stage; if its progress no longer fits the new layout,
  earlier stages count as done and their evidence is re-created as migrated.
* Never remove stages from a shipped case: the checkpoint stores the stage index,
  and a saved stage past the new end is refused as invalid progress.
* A checkpoint from before a case was data-driven resumes at its stage with the
  earlier stages' evidence re-created (`"source": "migrated"`).
* A checkpoint from a newer build (`case_engine.version` or a case `version`
  above this build's) is refused instead of overwritten.

## Validation

`missions.case_library_report()` returns loaded cases, drafts, templates, errors and
warnings. Errors reject the whole file (other files still load); warnings mark
incomplete authoring: `[draft]` placeholders and default prompts.

Tests (root runs engines):

```
python godot/tools/godot_run.py --timeout 180 -- --headless --script res://tests/city_case_engine_smoke.gd
```

They load every template and the example, refuse a list of broken cases, play the
parcel case through conversations and photos, and check saves, migration,
stand-ins and the incident bridge.

## Compact example

```json
{
  "schema": 1, "id": "example_lost_tools", "version": 1, "status": "draft",
  "template": "return_property_with_pointer",
  "title": "Example: the borrowed tools",
  "reward": {"points": 120},
  "params": {"owner": "gardener", "owner_label": "Gardener", "pointer": "ambient_mailman", "pointer_label": "Mail carrier",
             "item_builder": "tool_caddy", "item_title": "GARDEN TOOL CADDY", "route_metres": 88.0, "item_radius": 0.32},
  "discovery": {"requires_completed": ["lost_satchel"]},
  "evidence": {"pointer_account": {"label": "Where the mail carrier saw the caddy"}, "item_found": {"label": "The green tool caddy"}},
  "stages": [
    {"id": "brief", "objectives": [{"id": "brief_owner", "objective": "Ask the gardener what is missing", "prompt": "E  Ask about the tools",
      "dialogue": "Our tool caddy is gone. Could you ask around before anyone gets blamed?"}]},
    {"id": "ask", "objectives": [{"id": "ask_pointer", "objective": "Ask the mail carrier where it went", "prompt": "E  Ask the mail carrier",
      "greeting": "Morning. Something on your mind?",
      "topics": [{"id": "where", "ask": "Did you see a green tool caddy?", "answer": "A volunteer set one down farther along Old York."}]}]},
    {"id": "recover", "objectives": [{"id": "pick_up", "objective": "Recover the caddy along Old York", "prompt": "E  Pick up the caddy",
      "dialogue": "The caddy still holds the hand tools."}]},
    {"id": "return", "objectives": [{"id": "hand_back", "objective": "Return the caddy", "prompt": "E  Return the tools",
      "dialogue": "Everything's here. Glad we asked first."}]}
  ],
  "outcomes": {"resolved": {"rewarded": true, "banner": "TOOLS RETURNED"}}
}
```

The template supplies the verbs, roles, props and evidence wiring; the case
supplies who, where, the words and the reward.

## Templates

| template | shape | original source |
|---|---|---|
| `report_with_witness` | brief → inspect *or* photograph the scene → witness interview → evidence-gated report | parcel_report, porch_light, torn_notice; crimes-core "call it in" |
| `return_property` | brief → pick up → hand back | lost_satchel; crimes-stage1 "follow the money" |
| `return_property_with_pointer` | brief → witness says where → pick up → hand back | missing_tools |
| `photograph_and_report` | tip → photograph the subject (count/time) → report | crimes-stage1 gary/lawn, crimes-stage2 mama/cops |
| `tail_and_photograph` | tip → follow unseen + two photos → report | crimes-stage1 mail |
| `report_and_confirm` | brief → record → report (problem cleared) → confirm the spot | dumping |
| `incident_report` | (incident-triggered, draft) photo of the offender *or* witness → report via incidents → wait for the police outcome | city_incidents templates from crimes-stage1 |
