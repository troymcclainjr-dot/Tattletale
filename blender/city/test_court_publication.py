"""Validate a prepared court publication against the current recipe and ground.

Run with --data PATH --previous PATH --ground-cache PATH before publication.
"""
import argparse
import hashlib
import json
from pathlib import Path
import numpy as np
from shapely.geometry import Polygon
from update_courts import GroundSampler
from park_courts import civic_clearance_space


def audit(data,previous,ground_cache):
    payload=json.loads((data/'pen_lucy_courts.json').read_text())
    old=json.loads((previous/'pen_lucy_courts.json').read_text())
    originals={c['id']:c for c in old['courts']}
    records=payload['courts']
    assert {c['id'] for c in records}==set(originals)-{'park_court_17'},'Court identities changed'
    chosen=next(c for c in records if c['id']=='park_court_13')
    assert chosen['kind']=='full' and len(chosen['hoops'])==2,'Requested court 13 remains a half'
    height=GroundSampler(np.load(ground_cache)['tri'])
    civic_space=civic_clearance_space(previous if (previous/'pen_lucy_civic_build.json').exists() else None)
    samples_checked=0;minimum=float('inf');changed=[]
    for c in records:
        assert len(c['hoops'])==(2 if c['kind']=='full' else 1),c['id']
        assert c['road_building_overlap_m2']==0 and c['max_fill_m']<=.8 and c['max_apron_slope_deg']<4,c['id']
        across=np.asarray(c['across']);along=np.asarray(c['along']);center=np.asarray(c['position'])
        for hoop in c['hoops']:
            delta=np.asarray(hoop['position'])-center
            assert abs(delta@across)<.0001,c['id']+' hoop on long side'
            assert abs(abs(delta@along)-(c['length_m']/2+.72))<.0001,c['id']+' hoop end position'
        if c['kind']=='full':
            h0,h1=[np.asarray(h['position'])-center for h in c['hoops']]
            assert (h0@along)*(h1@along)<0,c['id']+' hoops not opposed'
        if originals[c['id']]['kind']=='full':
            assert c==originals[c['id']],'Existing full court moved'
        if c==originals[c['id']]:continue
        changed.append(c['id'])
        footprint=Polygon([(x,-z) for x,z in c['footprint']])
        assert footprint.intersection(civic_space).area<1e-6,c['id']+' overlaps reserved civic grounds'
        tri=np.asarray(c['mesh']['vertices']).reshape(-1,3,3)[:c['floor_triangles']]+center
        points=np.concatenate([tri.reshape(-1,3),tri.mean(axis=1),(tri[:,0]+tri[:,1])/2,(tri[:,1]+tri[:,2])/2,(tri[:,0]+tri[:,2])/2])
        clearance=points[:,1]-height(points[:,0],-points[:,2])-.10
        assert clearance.min()>=.00199,c['id']+' unsupported slab/apron'
        assert clearance.max()<=.80001,c['id']+' excessive fill'
        samples_checked+=len(points);minimum=min(minimum,float(clearance.min()))
    vegetation=json.loads((data/'pen_lucy_vegetation.json').read_text())
    growth=json.loads((data/'pen_lucy_shrub_growth.json').read_text())
    assert growth['source_sha256']==hashlib.sha256((data/'pen_lucy_vegetation.json').read_bytes()).hexdigest(),'Shrub-growth metadata invalidated'
    assert all(vegetation['plants'][g['index']]['kind'].startswith('bush') for g in growth['plants']),'Growth index refers to tree'
    return {'courts':len(records),'full':sum(c['kind']=='full' for c in records),'half':sum(c['kind']!='full' for c in records),
            'changed':changed,'supported_floor_samples':samples_checked,'min_ground_clearance_m':minimum,'court13':{k:chosen[k] for k in ('id','position','width_m','length_m','across','along','hoops')},'failures':[]}


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--data',type=Path,required=True);parser.add_argument('--previous',type=Path,required=True)
    parser.add_argument('--ground-cache',type=Path,required=True)
    args=parser.parse_args();print(json.dumps(audit(args.data,args.previous,args.ground_cache),indent=2))
