import json,sys
from pathlib import Path
import numpy as np, shapely, laspy
from pyproj import CRS,Transformer
from shapely.geometry import shape,Polygon,LineString,Point,mapping
root=Path(__file__).resolve().parents[2]
d=json.loads((root/'godot/assets/data/pen_lucy_level.json').read_text())
with laspy.open(next((root/'.work/city/raw').glob('*.laz'))) as f: crs=f.header.parse_crs() or CRS.from_epsg(6347)
h=crs.sub_crs_list[0] if crs.is_compound else crs
factor=h.axis_info[0].unit_conversion_factor
tf=Transformer.from_crs('EPSG:4326',h,always_xy=True);ox,oy=tf.transform(*d['origin_lonlat'])
def project(a):
 x,y=tf.transform(a[:,0],a[:,1]);return np.column_stack([(x-ox)*factor,-(y-oy)*factor])
b=json.loads((root/'blender/city/data/pen_lucy_buildings.geojson').read_text())
features=[dict(p=f['properties'],polygon=mapping(shapely.transform(shape(f['geometry']),project))) for f in b['features']]
out=dict(buildings=features,level=d)
(root/'artifacts/civic-plan/map-source.json').write_text(json.dumps(out))
print(len(features),'building footprints exported')
