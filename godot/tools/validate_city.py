"""Serialized, isolated city integration gates; errors cannot masquerade as passes."""
from pathlib import Path
import argparse, hashlib, json, os, subprocess, sys, time
ROOT = Path(__file__).resolve().parents[2]
CASES = {
    'narrative': ('city_narrative_smoke.gd', False, []),
    'story-input': ('city_story_input_smoke.gd', False, []),
    'world-persistence': ('city_world_persistence_smoke.gd', False, []),
    'vehicle-authority': ('city_vehicle_authority_smoke.gd', False, []),
    'police-cruisers': ('city_police_cruisers_smoke.gd', False, []),
    'progression': ('city_progression_smoke.gd', False, []),
    'law': ('city_law_smoke.gd', False, []),
    'driving': ('city_driving_smoke.gd', False, []),
    'driving-level': ('city_driving_level_smoke.gd', False, []),
    'driving-access': ('city_driving_access_smoke.gd', False, []),
    'car-map': ('city_car_map_smoke.gd', False, []),
    'sandbox-world': ('city_sandbox_world_smoke.gd', False, []),
    'sandbox-render': ('city_sandbox_render.gd', True, []),
    'combat-sandbox': ('city_combat_sandbox_smoke.gd', False, []),
    'combat-law': ('city_combat_law_ownership_smoke.gd', False, []),
    'shops': ('city_shops_smoke.gd', False, []),
    'shops-render': ('city_shops_render.gd', True, []),
    'alleys': ('city_alley_surface_smoke.gd', False, []),
    'npc-render-lod': ('city_npc_render_lod_smoke.gd', False, []),
    'vehicle-render-lod': ('city_vehicle_render_lod_smoke.gd', False, []),
    'material-palette': ('city_material_palette_smoke.gd', False, []),
    'civic-palette-render': ('city_civic_palette_render.gd', True, []),
    'vehicle-tint-render': ('city_vehicle_tint_render.gd', True, []),
    'npc-lod-render': ('city_npc_render_lod_visual.gd', True, []),
    'route-cache': ('city_route_distance_cache_smoke.gd', False, []),
    'crowd-idle': ('city_crowd_idle_smoke.gd', False, []),
    'catalog-combat': ('city_catalog_combat_smoke.gd', False, []),
    'vehicle-precision': ('city_vehicle_precision_smoke.gd', False, []),
    'vehicle-jump': ('city_vehicle_jump_smoke.gd', False, []),
    'street': ('city_street_smoke.gd', False, []),
    'ui': ('city_ui_smoke.gd', False, []),
    'life': ('city_life_smoke.gd', False, []),
    'settings-layout': ('city_settings_layout_runner.gd', False, []),
    'input-case': ('city_input_case_smoke.gd', False, []),
    'legacy-people': ('city_modular_legacy_runner.gd', False, []),
    'ui-render': ('city_current_ui_render.gd', True, []),
    'car-showroom': ('city_car_showroom.gd', True, []),
    'catalog-integration': ('city_car_catalog_integration_smoke.gd', False, []),
    'cars': ('city_cars_smoke.gd', False, []),
    'case-ledger': ('city_case_ledger_runner.gd', False, []),
    'car-catalog': ('city_car_catalog_smoke.gd', False, []),
    'melee-audio': ('city_melee_audio_smoke.gd', False, []),
    'traffic-budget': ('city_traffic_damage_budget_smoke.gd', False, []),
    'combat': ('city_combat_smoke.gd', False, []),
    'phone': ('city_player_phone_smoke.gd', False, []),
    'phone-render': ('city_player_phone_smoke.gd', True, ['--phone-render']),
    'tires': ('city_tire_handling_smoke.gd', False, []),
    'damage': ('city_vehicle_damage_smoke.gd', False, []),
    'people': ('city_modular_people.tscn', True, ['--roster-visual']),
    'reliability': ('city_release_reliability_smoke.gd', False, []),
    'save': ('city_world_save_smoke.gd', False, []),
    'traffic': ('city_traffic_network_smoke.gd', False, []),
    'movement': ('city_movement_smoke.gd', False, []),
    'expansion': ('city_expansion_smoke.gd', False, []),
    'residents': ('city_residents_smoke.gd', False, []),
    'recovery': ('city_resident_recovery_smoke.gd', False, []),
    'day-night': ('city_day_night_smoke.gd', False, []),
    'parks': ('city_park_neighborhood_smoke.gd', False, []),
    'backlots': ('city_backlot_details_smoke.gd', False, []),
    'inspector': ('city_inspector_smoke.gd', False, []),
    'world': ('city_alive_world_smoke.gd', False, []),
}
# Vehicle hull/jump sweeps and street/life fixtures cover physical integration,
# while UI exercises real modal/input/persistence behavior (not only captures).
TIMEOUTS = {'driving-level': 480, 'driving': 240, 'sandbox-world': 360, 'sandbox-render': 300, 'input-case': 360, 'life': 300, 'vehicle-precision': 240,
            'vehicle-jump': 240, 'street': 240, 'ui': 240, 'settings-layout': 30,
            'story-input': 420, 'world-persistence': 900, 'vehicle-authority': 360, 'police-cruisers': 360}

def source_hashes():
    """Runtime source and test provenance, excluding generated import/cache files."""
    paths = set((ROOT/'godot/scripts').rglob('*.gd'))
    for suffix in ('*.gd', '*.tscn'):
        paths.update((ROOT/'godot/tests').rglob(suffix))
    asset_suffixes = {'.json', '.gdshader', '.glb', '.ttf', '.otf', '.wav',
                      '.ogg', '.png', '.jpg', '.svg', '.tres', '.txt'}
    paths.update(p for p in (ROOT/'godot/assets').rglob('*')
                 if p.is_file() and p.suffix.lower() in asset_suffixes)
    paths.update((ROOT/'godot/scenes').rglob('*.tscn'))
    paths.update([ROOT/'godot/project.godot', ROOT/'godot/export_presets.cfg',
                  Path(__file__).resolve(), ROOT/'godot/tools/godot_run.py',
                  ROOT/'godot/tools/godot_preview.py'])
    return {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in sorted(paths) if p.is_file()}


def changed_sources(before, after):
    return {path: {'before': before.get(path), 'after': after.get(path)}
            for path in sorted(before.keys() | after.keys())
            if before.get(path) != after.get(path)}


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--only',nargs='+',choices=CASES,default=list(CASES))
    parser.add_argument('--output',default='artifacts/alive-next/validation')
    args=parser.parse_args()
    out=(ROOT/args.output).resolve(); out.mkdir(parents=True,exist_ok=True)
    env=os.environ.copy(); env['APPDATA']=str(ROOT/'.work/test-profile'); env['PYTHONUTF8']='1'
    records=[]
    hashes=source_hashes()
    for name in args.only:
        entry,graphical,flags=CASES[name]
        command=[sys.executable,str(ROOT/'godot/tools/godot_run.py'),'--timeout',str(TIMEOUTS.get(name, 240 if graphical else 180)),'--']
        if not graphical: command+=['--headless']
        command+=['--log-file',str(out/(name+'-engine.log'))]
        if entry.endswith('.gd'): command+=['--script']
        command+=['res://tests/'+entry,'--','--offscreen-validation']+flags
        print('START '+name,flush=True); started=time.monotonic()
        result=subprocess.run(command,cwd=ROOT,env=env,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,encoding='utf8',errors='replace')
        (out/(name+'-run.log')).write_text(result.stdout,encoding='utf8')
        bad=[line for line in result.stdout.splitlines() if any(x in line for x in ['SCRIPT ERROR:','SHADER ERROR:','ERROR:','FAIL '])]
        record={'name':name,'passed':result.returncode==0 and not bad,'exit':result.returncode,'seconds':round(time.monotonic()-started,2),'errors':bad[:12],'command':command}
        records.append(record); print(json.dumps(record),flush=True)
        (out/'summary.json').write_text(json.dumps({'cases':records,'requested_cases':args.only,
            'source_sha256':hashes,'complete':False,'frozen_tree':None},indent=2),encoding='utf8')
    ending=source_hashes()
    changed=changed_sources(hashes,ending)
    summary={'cases':records,'requested_cases':args.only,'source_sha256':hashes,
             'ending_source_sha256':ending,'complete':True,'frozen_tree':not changed,
             'changed_sources':changed,'passed':not changed and all(r['passed'] for r in records)}
    (out/'summary.json').write_text(json.dumps(summary,indent=2),encoding='utf8')
    if changed:
        print('FAIL source tree changed during validation: '+', '.join(changed),flush=True)
    return int(not summary['passed'])
if __name__=='__main__': sys.exit(main())
