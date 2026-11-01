"""Fit public basketball courts into every usable green without regrading the city.

The central playing slab is planar. A narrow apron joins the existing ground;
every apron triangle must remain below 4 degrees. The exported mesh owns collision.
"""
import json
import math
from pathlib import Path
import numpy as np
import shapely
from shapely.geometry import Polygon, Point, box
from shapely.ops import unary_union

MIN_GREEN_AREA = 250.0
MAX_FILL = .80
MAX_COURT_GRADE = .015
FULL_COURT_SIZES = [(15.,28.),(13.,24.),(12.,22.),(11.,22.),(10.,20.),(10.,18.)]
HALF_COURT_SIZES = [(15.,11.),(14.,10.),(12.,9.)]


def civic_clearance_space(data_dir=None):
    """Mirror runtime civic footprint, parking, approach and landscape reservations."""
    data=Path(data_dir) if data_dir else Path(__file__).parents[2]/"godot/assets/data"
    polygons=[]
    def ring(points,holes=()):
        if len(points)>=3:
            polygons.append(Polygon([(p[0],-p[1]) for p in points],
                [[(p[0],-p[1]) for p in hole] for hole in holes]).buffer(0))
    path=data/'pen_lucy_civic_build.json'
    if path.exists():
        for site in json.loads(path.read_text()).get('sites',[]):
            for key in ('footprint_xz','parking_lot_xz','apron_xz'):ring(site.get(key,[]))
            if 'approach_center' in site:
                start=np.asarray(site['approach_center'])[[0,2]];end=np.asarray(site['position'])[[0,2]]
                delta=end-start;right=np.array([delta[1],-delta[0]])
                if np.linalg.norm(right)>0:
                    right=right/np.linalg.norm(right)*2.7
                    ring([start-right,start+right,end+right,end-right])
            if 'landscape_clear_zone' in site:
                geometry=site['landscape_clear_zone']
                for polygon in (geometry['coordinates'] if geometry['type']=='MultiPolygon' else [geometry['coordinates']]):
                    ring(polygon[0],polygon[1:])
    path=data/'pen_lucy_fire_grounds.json'
    if path.exists():ring(json.loads(path.read_text()).get('clearance_polygon_xz',[]))
    path=data/'pen_lucy_new_businesses.json'
    if path.exists():
        for entry in json.loads(path.read_text()).get('businesses',[]):ring(entry.get('clearance_polygon',entry.get('polygon',[])))
    return unary_union(polygons)


def bind_court_identities(greens):
    """Keep IDs attached to their physical green, independent of selection order."""
    path = Path(__file__).parent / "data/pen_lucy_court_identities.json"
    if not path.exists():
        return
    identities = json.loads(path.read_text())["courts"]
    for entry in identities:
        x,z = entry["anchor_xz"]
        matches = [g for g in greens if g["poly"].covers(Point(x,-z))]
        if len(matches) == 1:
            green = matches[0]
            if "court_id" in green:
                raise ValueError("Two saved court identities now occupy the same green")
            green["court_id"] = entry["id"]
            green["court_removed"] = entry.get("removed",False)
    reserved = {entry["id"] for entry in identities}
    next_id = 0
    for green in greens:
        if "court_id" in green:
            continue
        while "park_court_"+str(next_id) in reserved:
            next_id += 1
        green["court_id"] = "park_court_"+str(next_id)
        reserved.add(green["court_id"])


def green_spaces(parks, grass):
    """Inventory every substantial grass component, including unnamed clearings.

    Named park boundaries often describe just a playground inside a larger green;
    use the complete contiguous grass surface rather than duplicating that park.
    Narrow connected lawns remain in the audit and fail the rectangle fit openly.
    """
    parts = sorted((p for p in shapely.get_parts(grass) if p.geom_type == "Polygon"),
                   key=lambda p: (-p.area, p.centroid.x, p.centroid.y))
    result = []
    for index, poly in enumerate(parts):
        names = sorted(set(p["name"] for p in parks if p["poly"].intersection(poly).area > 10))
        if poly.area < MIN_GREEN_AREA and not names:
            continue
        result.append({"id": "green_%03d" % index, "name": " / ".join(names) or "Neighborhood green %d" % (index + 1),
                       "poly": poly, "named_parks": names})
    named_inventory=[{"park_index":i,"name":park["name"],"area_m2":round(park["poly"].area,2),
                      "green_ids":[r["id"] for r in result if r["poly"].intersection(park["poly"]).area>10]}
                     for i,park in enumerate(parks)]
    return result, {"grass_components": len(parts), "small_lawns_omitted": sum(p.area < MIN_GREEN_AREA and not any(
        park["poly"].intersection(p).area > 10 for park in parks) for p in parts), "minimum_green_area_m2": MIN_GREEN_AREA,
        "minimum_playing_area_m": [12, 9], "minimum_apron_footprint_m": [16, 13],
        "minimum_retained_slab_m":[14,11],"retained_access_ramps_m":{"width":3,"length_each":[2.5,8]},"named_parks":named_inventory}


class Mesh:
    def __init__(self):
        self.vertices, self.normals, self.colors = [], [], []

    def tri(self, points, color, normal=None):
        p = np.asarray(points, float)
        n = np.cross(p[1]-p[0], p[2]-p[0])
        length = np.linalg.norm(n)
        if length < 1e-10: return
        n /= length
        if normal is not None and n @ normal < 0:
            p = p[::-1]; n = -n
        self.vertices.extend(p[::-1].round(6).ravel().tolist())
        self.normals.extend(n.round(6).tolist()*3)
        self.colors.extend([*color, 1]*3)

    def quad(self, p, color, normal=None):
        self.tri([p[0],p[1],p[2]],color,normal)
        self.tri([p[0],p[2],p[3]],color,normal)

    def payload(self):
        return {"vertices":self.vertices,"normals":self.normals,"colors":self.colors,"triangles":len(self.vertices)//9}


def rectangle(center, across, along, width, length):
    return Polygon([center+across*u+along*v for u,v in ((-width/2,-length/2),(width/2,-length/2),(width/2,length/2),(-width/2,length/2))])


def trees_outside_courts(trees, court_space):
    # GEOS distance(empty, point) is NaN; comparing that NaN would erase the
    # complete forest. Empty selections must be the identity operation.
    if court_space.is_empty:
        return list(trees)
    kept=[tree for tree in trees if court_space.distance(Point(tree[0],tree[1])) > tree[3]*.06+.40]
    return kept


def fit_candidate(center, across, along, width, length, apron, height, max_grade):
    pad_w, pad_l = width+2.0, length+2.0
    # Include every one-metre seam: the supporting field is exactly linear per
    # half-cell, and the final mesh receives its own stricter triangle audit.
    us = np.linspace(-pad_w/2,pad_w/2,int(math.ceil(pad_w))+1)
    vs = np.linspace(-pad_l/2,pad_l/2,int(math.ceil(pad_l))+1)
    uu,vv = np.meshgrid(us,vs); uv=np.column_stack([uu.ravel(),vv.ravel()])
    xy=center+uv[:,0,None]*across+uv[:,1,None]*along
    ground=height(xy[:,0],xy[:,1])+.10
    coeff=np.linalg.lstsq(np.column_stack([uv,np.ones(len(uv))]),ground,rcond=None)[0]
    gradient=coeff[:2].copy(); magnitude=np.linalg.norm(gradient)
    if magnitude>max_grade: gradient*=max_grade/magnitude
    intercept=float(np.max(ground-uv@gradient))+.013
    fill=uv@gradient+intercept-ground
    if float(fill.max())>MAX_FILL: return None
    # Source terrain is not changed. A bounded apron fills the small difference.
    xs=np.unique(np.r_[np.linspace(-pad_w/2-apron,pad_w/2+apron,int(math.ceil(pad_w+2*apron))+1),-pad_w/2,pad_w/2])
    zs=np.unique(np.r_[np.linspace(-pad_l/2-apron,pad_l/2+apron,int(math.ceil(pad_l+2*apron))+1),-pad_l/2,pad_l/2])
    x,z=np.meshgrid(xs,zs); flat=np.column_stack([x.ravel(),z.ravel()])
    points=center+flat[:,0,None]*across+flat[:,1,None]*along
    ground_all=height(points[:,0],points[:,1])+.10
    plane=flat@gradient+intercept
    outer=np.maximum(np.maximum(np.abs(flat[:,0])-pad_w/2,np.abs(flat[:,1])-pad_l/2),0)
    blend=np.clip(outer/apron,0,1)
    top=np.maximum(plane*(1-blend)+(ground_all+.006)*blend,ground_all+.006)
    if np.min(top-ground_all)<-.002: return None
    # Different triangulation diagonals can differ by a few millimetres on the
    # existing heightfield. A 14mm outer slab lip keeps grass below every face.
    top += .008
    intercept += .008
    if float((top-ground_all).max())>MAX_FILL: return None
    grid=np.column_stack([flat,top]).reshape(len(zs),len(xs),3)
    tris=np.concatenate([np.stack([grid[:-1,:-1],grid[:-1,1:],grid[1:,1:]],axis=2).reshape(-1,3,3),
                         np.stack([grid[:-1,:-1],grid[1:,1:],grid[1:,:-1]],axis=2).reshape(-1,3,3)])
    cross=np.cross(tris[:,1]-tris[:,0],tris[:,2]-tris[:,0])
    slope=np.degrees(np.arctan2(np.linalg.norm(cross[:,:2],axis=1),np.abs(cross[:,2])))
    if float(slope.max())>3.99: return None
    return {"center":center,"across":across,"along":along,"width":width,"length":length,
            "apron":apron,"gradient":gradient,"intercept":intercept,"triangles":tris,
            "max_fill_m":float((top-ground_all).max()),"max_apron_slope_deg":float(slope.max()),
            "court_grade":float(np.linalg.norm(gradient)),"survey_grade":float(magnitude)}


def retained_candidate(center, across, along, width, length, apron, height, max_grade, ramp_axis="across", ramp_offset=0.):
    """A filled slab with two 3m-wide access ramps and solid retaining sides.

    Side terrain may be steep, but the two approaches and entire playing surface
    still stay under four degrees. No terrain is cut or hidden inside a deck.
    """
    if ramp_axis=="along":
        # Put the two end approaches beside, rather than through, the hoop poles.
        fit=retained_candidate(center,along,-across,length,width,apron,height,max_grade,ramp_offset=width/2-2.)
        if fit is None:return None
        for key in ("triangles","retaining_triangles"):
            tri=fit[key].copy();fit[key][:,:,0]=-tri[:,:,1];fit[key][:,:,1]=tri[:,:,0]
        fit.update(across=across,along=along,width=width,length=length,
                   gradient=np.array([-fit["gradient"][1],fit["gradient"][0]]),access="opposed_offset_end_ramps")
        return fit
    pw,pl=width+2,length+2
    us=np.linspace(-pw/2,pw/2,int(math.ceil(pw))+1)
    vs=np.unique(np.r_[np.linspace(-pl/2,pl/2,int(math.ceil(pl))+1),ramp_offset-1.5,ramp_offset+1.5])
    uu,vv=np.meshgrid(us,vs);uv=np.column_stack([uu.ravel(),vv.ravel()])
    xy=center+uv[:,0,None]*across+uv[:,1,None]*along
    ground=height(xy[:,0],xy[:,1])+.10
    coeff=np.linalg.lstsq(np.column_stack([uv,np.ones(len(uv))]),ground,rcond=None)[0]
    gradient=coeff[:2]; magnitude=np.linalg.norm(gradient)
    if magnitude>max_grade:gradient=gradient*max_grade/magnitude
    intercept=float(np.max(ground-uv@gradient))+.021
    top=uv@gradient+intercept
    if float((top-ground).max())>MAX_FILL:return None
    def triangles(grid):
        return np.concatenate([np.stack([grid[:-1,:-1],grid[:-1,1:],grid[1:,1:]],axis=2).reshape(-1,3,3),
                               np.stack([grid[:-1,:-1],grid[1:,1:],grid[1:,:-1]],axis=2).reshape(-1,3,3)])
    tris=[triangles(np.column_stack([uv,top]).reshape(len(vs),len(us),3))]
    skirts=[];max_fill=float((top-ground).max())
    # Sample skirts along the actual one-metre ground facets, so there is no open underside.
    def skirt(points,tops):
        p=np.asarray(points);xy=center+p[:,0,None]*across+p[:,1,None]*along
        bottom=height(xy[:,0],xy[:,1])+.095
        for i in range(len(p)-1):
            a,b=np.r_[p[i],tops[i]],np.r_[p[i+1],tops[i+1]]
            c,d=np.r_[p[i+1],bottom[i+1]],np.r_[p[i],bottom[i]]
            skirts.extend([[a,b,c],[a,c,d]])
    for v in (-pl/2,pl/2):
        p=np.column_stack([us,np.full(len(us),v)]);skirt(p,p@gradient+intercept)
    for sign in (-1,1):
        for lo,hi in ((-pl/2,ramp_offset-1.5),(ramp_offset+1.5,pl/2)):
            vv=np.linspace(lo,hi,int(math.ceil(hi-lo))+1);p=np.column_stack([np.full(len(vv),sign*pw/2),vv]);skirt(p,p@gradient+intercept)
        ru=sign*(pw/2+np.linspace(0,apron,int(math.ceil(apron))+1))
        rv=np.linspace(ramp_offset-1.5,ramp_offset+1.5,7);uu,vv=np.meshgrid(ru,rv);p=np.column_stack([uu.ravel(),vv.ravel()])
        xy=center+p[:,0,None]*across+p[:,1,None]*along;g=height(xy[:,0],xy[:,1])+.10
        edge=np.column_stack([np.full(len(rv),ru[-1]),rv]);exy=center+edge[:,0,None]*across+edge[:,1,None]*along
        end=height(exy[:,0],exy[:,1])+.114
        start=gradient[0]*ru[0]+gradient[1]*rv+intercept
        blend=np.linspace(0,1,len(ru));t=(start[:,None]*(1-blend)+end[:,None]*blend).ravel()
        clearance=t-g
        if float(clearance.min())<.006 or float(clearance.max())>MAX_FILL:return None
        max_fill=max(max_fill,float(clearance.max()))
        grid=np.column_stack([p,t]).reshape(len(rv),len(ru),3);tris.append(triangles(grid))
        for row in (grid[0],grid[-1]):skirt(row[:,:2],row[:,2])
    tris=np.concatenate(tris);cross=np.cross(tris[:,1]-tris[:,0],tris[:,2]-tris[:,0])
    slope=np.degrees(np.arctan2(np.linalg.norm(cross[:,:2],axis=1),np.abs(cross[:,2])))
    if float(slope.max())>3.99:return None
    return {"center":center,"across":across,"along":along,"width":width,"length":length,"apron":apron,
            "gradient":gradient,"intercept":intercept,"triangles":tris,"retaining_triangles":np.asarray(skirts),
            "max_fill_m":max_fill,"max_apron_slope_deg":float(slope.max()),"court_grade":float(np.linalg.norm(gradient)),
            "survey_grade":float(magnitude),"access":"opposed_across_ramps","ramp_width_m":3.0}


def placement_candidates(usable, width, length, step=2., retained=False, ramp_axis="across"):
    """Vectorized exact footprint checks; preserve every fitting sampled location."""
    shapely.prepare(usable)
    xmin,ymin,xmax,ymax=usable.bounds
    # Include long-edge directions so diagonal greens are not lost to 15-degree quantization.
    corners=np.asarray(usable.minimum_rotated_rectangle.exterior.coords)
    edges=np.diff(corners,axis=0)
    angles=np.unique(np.r_[np.arange(0,180,15),np.degrees(np.arctan2(edges[:,1],edges[:,0]))%180])
    for angle in angles:
        theta=np.radians(angle); across=np.array([np.cos(theta),np.sin(theta)]); along=np.array([-np.sin(theta),np.cos(theta)])
        for apron in ((8.,6.,4.,2.5) if retained else (6.0,4.0,2.5,1.75,1.0)):
            half=np.array([width/2+1+apron,length/2+1+(0 if retained else apron)])
            if retained and ramp_axis=="along":half=np.array([width/2+1,length/2+1+apron])
            radius=np.abs(across)*half[0]+np.abs(along)*half[1]
            xs=np.arange(xmin+radius[0],xmax-radius[0]+.001,step)
            ys=np.arange(ymin+radius[1],ymax-radius[1]+.001,step)
            if not len(xs) or not len(ys): continue
            xx,yy=np.meshgrid(xs,ys);centers=np.column_stack([xx.ravel(),yy.ravel()])
            offsets=np.array([[-1,-1],[1,-1],[1,1],[-1,1]])*half
            corners=centers[:,None,:]+offsets[None,:,0,None]*across+offsets[None,:,1,None]*along
            footprints=shapely.polygons(corners)
            if retained:
                # A cross-shaped reservation: only the slab and two actual ramps.
                pw,pl=(length+2,width+2) if ramp_axis=="along" else (width+2,length+2)
                offset=width/2-2. if ramp_axis=="along" else 0.
                lo,hi=offset-1.5,offset+1.5
                local=np.array([[-pw/2,-pl/2],[pw/2,-pl/2],
                    [pw/2,lo],[pw/2+apron,lo],[pw/2+apron,hi],[pw/2,hi],
                    [pw/2,pl/2],[-pw/2,pl/2],[-pw/2,hi],
                    [-pw/2-apron,hi],[-pw/2-apron,lo],[-pw/2,lo]])
                if ramp_axis=="along":local=np.column_stack([-local[:,1],local[:,0]])
                footprints=shapely.polygons(centers[:,None,:]+local[None,:,0,None]*across+local[None,:,1,None]*along)
            keep=shapely.covers(usable,footprints)
            for center,footprint in zip(centers[keep],footprints[keep]):
                yield center,across,along,apron,footprint


def select(parks, forbidden, height, with_audit=False):
    selected=[]; coverage=[]
    sizes=FULL_COURT_SIZES+HALF_COURT_SIZES
    for index,park in enumerate(parks):
        usable=park["poly"].buffer(-.20).difference(forbidden.buffer(.20))
        audit={"green_id":park.get("id", "green_%03d" % index),"name":park["name"],
               "area_m2":round(park["poly"].area,2),"named_parks":park.get("named_parks",[]),
               "bounds_xz":[round(v,3) for v in (park["poly"].bounds[0],-park["poly"].bounds[3],park["poly"].bounds[2],-park["poly"].bounds[1])],
               "geometry_candidates":0,"size_attempts":[],"status":"excluded","reason":"too_narrow_for_half_court_with_apron_or_two_access_ramps"}
        best=None
        if park.get("court_removed",False):
            audit.update(reason="removed_at_user_request",court_id=park["court_id"])
            coverage.append(audit)
            continue
        if not usable.is_empty and usable.area >= 208:
            for width,length in sizes:
                step=1.0 if length>=18 else 2.0
                candidates=[(c,"") for c in placement_candidates(usable,width,length,step=step)]
                for ramp_axis in ("across","along"):
                    candidates += [(c,ramp_axis) for c in placement_candidates(usable,width,length,step=step,retained=True,ramp_axis=ramp_axis)]
                audit["geometry_candidates"]+=len(candidates)
                attempt={"width_m":width,"length_m":length,"geometry_candidates":len(candidates),"terrain_candidates":0,"selected":False}
                audit["size_attempts"].append(attempt)
                # Rank using sparse real-height samples, then fully audit promising fits.
                # Full courts get all allowed grades before trying a half court.
                ranked=[]
                uv=np.array([(u,v) for u in (-width/2-1,0,width/2+1) for v in (-length/2-1,0,length/2+1)])
                for candidate,retained in candidates:
                    center,across,along,apron,footprint=candidate
                    xy=center+uv[:,0,None]*across+uv[:,1,None]*along
                    ground=height(xy[:,0],xy[:,1])
                    coeff=np.linalg.lstsq(np.column_stack([uv,np.ones(len(uv))]),ground,rcond=None)[0]
                    gradient=coeff[:2]; magnitude=np.linalg.norm(gradient)
                    if magnitude>MAX_COURT_GRADE: gradient=gradient*MAX_COURT_GRADE/magnitude
                    fill=float(np.ptp(ground-uv@gradient))+.021
                    if fill<=MAX_FILL: ranked.append((fill,candidate,retained))
                attempt["terrain_candidates"]=len(ranked)
                for _,candidate,retained in sorted(ranked,key=lambda c:(c[2],c[0])):
                    center,across,along,apron,footprint=candidate
                    fit=retained_candidate(center,across,along,width,length,apron,height,MAX_COURT_GRADE,ramp_axis=retained) if retained else fit_candidate(center,across,along,width,length,apron,height,MAX_COURT_GRADE)
                    if fit is not None:
                        tri=fit["triangles"]
                        # Vertices alone miss a raised source facet crossing a new
                        # triangle. Audit centres and all edge midpoints as well.
                        samples=np.concatenate([tri.reshape(-1,3),tri.mean(axis=1),
                            (tri[:,0]+tri[:,1])/2,(tri[:,1]+tri[:,2])/2,(tri[:,2]+tri[:,0])/2])
                        xy=center+samples[:,0,None]*across+samples[:,1,None]*along
                        clearance=samples[:,2]-height(xy[:,0],xy[:,1])-.10
                        if clearance.min()<.002 or clearance.max()>MAX_FILL:continue
                        fit.update(min_ground_clearance_m=float(clearance.min()),max_fill_m=float(clearance.max()),support_samples=len(samples))
                        fit.update(footprint=footprint,park=park["name"],green_id=audit["green_id"],court_id=park.get("court_id","park_court_"+str(len(selected))),road_building_overlap_m2=float(footprint.intersection(forbidden).area))
                        attempt["selected"]=True
                        best=fit;break
                if best is not None: break
        if best is not None:
            selected.append(best);audit.update(status="covered",reason="",court_id=best["court_id"])
        elif audit["geometry_candidates"]:
            audit["reason"]="terrain_exceeds_1_5_percent_plane_or_80_cm_fill_or_4_degree_access_ramps"
        coverage.append(audit)
        print("[courts]",audit["green_id"],audit["name"],audit["area_m2"],audit["status"],audit["reason"],flush=True)
    return (selected,coverage) if with_audit else selected


def mesh_for(court, origin_y):
    mesh=Mesh(); c=court["center"]; a=court["across"]; b=court["along"]
    gradient=court["gradient"]; intercept=court["intercept"]
    width,length=court["width"],court["length"]
    origin=np.array([c[0],intercept-origin_y,-c[1]])
    def world(u,v,y=None):
        xy=c+a*u+b*v
        return np.array([xy[0],(intercept+gradient@np.array([u,v]) if y is None else y)-origin_y,-xy[1]])-origin
    up=np.array([-gradient[0]*a[0]-gradient[1]*b[0],1,gradient[0]*a[1]+gradient[1]*b[1]]); up/=np.linalg.norm(up)
    for i,tri in enumerate(court["triangles"]):
        base=np.array([.29,.31,.30])
        color=base*(.985+.03*((i*73)%97)/97)
        mesh.tri([world(p[0],p[1],p[2]) for p in tri],color,up)
    floor_triangles=len(mesh.vertices)//9
    for tri in court.get("retaining_triangles",[]):
        mesh.tri([world(p[0],p[1],p[2]) for p in tri],(.26,.28,.27))
    white=(.87,.86,.76)
    def patch(u0,v0,u1,v1,color,lift=.005):
        mesh.quad([world(u,v)+np.array([0,lift,0]) for u,v in ((u0,v0),(u1,v0),(u1,v1),(u0,v1))],color,up)
    def stroke(points,thickness=.055,color=white):
        for p,q in zip(points,points[1:]):
            p,q=np.asarray(p),np.asarray(q); d=q-p; norm=np.linalg.norm(d)
            if norm<1e-8: continue
            side=np.array([-d[1],d[0]])/norm*thickness/2
            mesh.quad([world(*(p-side))+[0,.008,0],world(*(q-side))+[0,.008,0],world(*(q+side))+[0,.008,0],world(*(p+side))+[0,.008,0]],color,up)
    def arc(center,r,start,end,segments=40):
        return [np.array(center)+r*np.array([math.cos(t),math.sin(t)]) for t in np.linspace(start,end,segments+1)]
    # Exact rectangular paint boundary, independent of the terrain grid's
    # diagonals. Triangle-centroid coloring produces visible sawtooth edges.
    patch(-width/2,-length/2,width/2,length/2,(.25,.40,.36),.003)
    stroke([(-width/2,-length/2),(width/2,-length/2),(width/2,length/2),(-width/2,length/2),(-width/2,-length/2)])
    ends=[-1,1] if length>=18 else [-1]
    hoops=[]
    for sign in ends:
        baseline=sign*length/2; inward=-sign
        lane_end=baseline+inward*5.80
        patch(-2.45,min(baseline,lane_end),2.45,max(baseline,lane_end),(.23,.32,.42))
        stroke([(-2.45,baseline),(-2.45,lane_end),(2.45,lane_end),(2.45,baseline)])
        stroke(arc((0,lane_end),1.8,0,math.pi) if inward>0 else arc((0,lane_end),1.8,math.pi,math.tau))
        for u in (-2.45,2.45):
            for distance in (1.1,2.0,2.9,3.8): stroke([(u,baseline+inward*distance),(u+math.copysign(.16,u),baseline+inward*distance)])
        rim_v=baseline+inward*1.575
        radius=min(6.75,width/2-.75); corner=width/2-.90; angle=math.acos(min(corner/radius,.999))
        points=arc((0,rim_v),radius,angle,math.pi-angle)
        if inward<0: points=[np.array([p[0],2*rim_v-p[1]]) for p in points]
        stroke(points)
        for u in (-corner,corner): stroke([(u,baseline),(u,rim_v+inward*math.sqrt(max(radius*radius-corner*corner,0)))])
        pole_v=baseline+sign*.72
        pole_ground=intercept+gradient@np.array([0,pole_v])
        rim_ground=intercept+gradient@np.array([0,rim_v])
        hoops.append({"position":(world(0,pole_v)+origin).round(5).tolist(),"radius":.22,
                      "rim_position":(world(0,rim_v,rim_ground+3.05)+origin).round(5).tolist()})
        def box3(center,size,color):
            center=np.asarray(center); size=np.asarray(size)/2
            corners=[world(center[0]+u,center[2]+v,pole_ground+center[1]+h) for u,h,v in
                     [(-size[0],-size[1],-size[2]),(size[0],-size[1],-size[2]),(size[0],size[1],-size[2]),(-size[0],size[1],-size[2]),
                      (-size[0],-size[1],size[2]),(size[0],-size[1],size[2]),(size[0],size[1],size[2]),(-size[0],size[1],size[2])]]
            center_world=world(center[0],center[2],pole_ground+center[1])
            for ids in ((0,1,2,3),(4,7,6,5),(0,4,5,1),(3,2,6,7),(0,3,7,4),(1,5,6,2)):
                pts=np.array([corners[j] for j in ids]); normal=pts.mean(axis=0)-center_world
                mesh.quad(pts,color,normal)
        box3((0,1.87,pole_v),(.15,3.74,.15),(.30,.34,.33))
        board_v=baseline+inward*1.20; arm_len=abs(board_v-pole_v)
        box3((0,3.48,(pole_v+board_v)/2),(.12,.14,arm_len),(.33,.37,.35))
        board_y=rim_ground-pole_ground+3.45
        box3((0,board_y,board_v),(1.80,1.05,.06),(.77,.79,.74))
        front_v=board_v+inward*.035
        # Raised white backboard target and frame, all on one batched surface.
        for center,size in [((0,board_y-.175,front_v),(.59,.035,.018)),((0,board_y+.275,front_v),(.59,.035,.018)),
                            ((-.295,board_y+.05,front_v),(.035,.45,.018)),((.295,board_y+.05,front_v),(.035,.45,.018)),
                            ((0,board_y-.51,front_v),(1.78,.035,.018)),((0,board_y+.51,front_v),(1.78,.035,.018)),
                            ((-.88,board_y,front_v),(.035,1.03,.018)),((.88,board_y,front_v),(.035,1.03,.018))]: box3(center,size,white)
        def tube(start,end,radius,color,sides=5):
            start,end=np.asarray(start),np.asarray(end); axis=end-start; axis/=np.linalg.norm(axis)
            ref=np.array([0,1,0]) if abs(axis[1])<.9 else np.array([1,0,0])
            u=np.cross(axis,ref);u/=np.linalg.norm(u);v=np.cross(axis,u)
            ring=[math.cos(t)*u+math.sin(t)*v for t in np.linspace(0,math.tau,sides+1)]
            for j in range(sides): mesh.quad([start+ring[j]*radius,end+ring[j]*radius,end+ring[j+1]*radius,start+ring[j+1]*radius],color,ring[j]+ring[j+1])
        rim_y=rim_ground+3.05
        ring=[world(.225*math.cos(t),rim_v+.225*math.sin(t),rim_y) for t in np.linspace(0,math.tau,25)]
        for p,q in zip(ring,ring[1:]): tube(p,q,.017,(.80,.32,.12),4)
        for t in np.linspace(0,math.tau,13)[:-1]:
            top=world(.22*math.cos(t),rim_v+.22*math.sin(t),rim_y-.025)
            bottom=world(.13*math.cos(t+.20),rim_v+.13*math.sin(t+.20),rim_y-.42)
            tube(top,bottom,.008,(.74,.75,.67),3)
    if len(ends)==2:
        stroke([(-width/2,0),(width/2,0)]);stroke(arc((0,0),1.8,0,math.tau))
    return mesh.payload(),origin.round(6).tolist(),hoops,floor_triangles


def record_for(court, origin_y):
    mesh,origin,hoops,floor_triangles=mesh_for(court,origin_y)
    record={"id":court["court_id"],"green_id":court["green_id"],"park":court["park"],"kind":"full" if court["length"]>=18 else ("3x3_half" if court["width"]==15 and court["length"]==11 else "practice_half"),
            "width_m":court["width"],"length_m":court["length"],"position":origin,"mesh":mesh,"hoops":hoops,
            "floor_triangles":floor_triangles,"footprint":[[round(x,5),round(-y,5)] for x,y in court["footprint"].exterior.coords],
            "across":[float(court["across"][0]),0,float(-court["across"][1])],"along":[float(court["along"][0]),0,float(-court["along"][1])],
            "court_grade":round(court["court_grade"],6),"max_apron_slope_deg":round(court["max_apron_slope_deg"],5),
            "max_fill_m":round(court["max_fill_m"],5),"apron_width_m":court["apron"],"road_building_overlap_m2":round(court.get("road_building_overlap_m2",0.),8)}
    record.update(size_class="standard" if court["length"]>=28 else ("compact_full" if court["length"]>=18 else "half"),
                  access=court.get("access","all_sides_apron"),ramp_width_m=court.get("ramp_width_m",0),
                  retaining_triangles=len(court.get("retaining_triangles",[])),
                  min_ground_clearance_m=round(court["min_ground_clearance_m"],6),support_samples=court["support_samples"])
    return record


def locked_publication(output,forbidden,height,origin_y):
    """Preserve the approved overlay through unrelated full-city source builds.

    Moving/reselecting an approved court requires an explicit authoring update;
    changed ground/road support fails loudly rather than silently moving IDs.
    """
    identity_path=Path(__file__).parent/'data/pen_lucy_court_identities.json'
    if not identity_path.exists():return None
    identities=json.loads(identity_path.read_text())
    if not identities.get('preserve_published_layout',False):return None
    path=Path(output)
    if not path.exists():raise ValueError('Approved court layout missing: '+str(path))
    published=json.loads(path.read_text());records=published['courts']
    expected={c['id'] for c in identities['courts'] if not c.get('removed',False)}
    if {c['id'] for c in records}!=expected:raise ValueError('Approved court identity set changed')
    for identity in identities['courts']:
        if 'approved_position' not in identity:continue
        record=next(c for c in records if c['id']==identity['id'])
        if record['position']!=identity['approved_position'] or len(record['hoops'])!=2:
            raise ValueError('Explicit court approval changed: '+record['id'])
    spaces=[];minimum=float('inf');maximum=0.;samples=0
    for record in records:
        polygon=Polygon([(x,-z) for x,z in record['footprint']])
        if polygon.intersection(forbidden).area>1e-5:raise ValueError('Locked court overlaps changed road/building: '+record['id'])
        spaces.append(polygon)
        tri=np.asarray(record['mesh']['vertices']).reshape(-1,3,3)[:record['floor_triangles']]+np.asarray(record['position'])
        points=np.concatenate([tri.reshape(-1,3),tri.mean(axis=1),(tri[:,0]+tri[:,1])/2,(tri[:,1]+tri[:,2])/2,(tri[:,0]+tri[:,2])/2])
        clearance=points[:,1]+origin_y-height(points[:,0],-points[:,2])-.10
        minimum=min(minimum,float(clearance.min()));maximum=max(maximum,float(clearance.max()));samples+=len(points)
        if not np.isfinite(clearance).all() or clearance.min()<-.012 or clearance.max()>MAX_FILL+.012:
            raise ValueError('Locked court needs terrain review before rebuilding: %s clearance %.5f..%.5f'%(record['id'],clearance.min(),clearance.max()))
    # Source H can differ slightly from its triangulated export between vertices;
    # actual support is additionally checked against final exported triangles.
    audit=dict(published['audit'])
    audit['layout_locked']=True
    audit['source_field_support_check']={'samples':samples,'min_clearance_m':minimum,'max_fill_m':maximum,'triangulation_tolerance_m':.012}
    return unary_union(spaces),audit


def export(parks,footprints,zones,height,origin_y,output,trees=None):
    physical_forbidden=unary_union([footprints,zones["road"],zones["sidewalk"],zones["alley"],zones["lot"]])
    locked=locked_publication(output,physical_forbidden,height,origin_y)
    if locked is not None:
        space,audit=locked
        if trees is not None:
            kept=trees_outside_courts(trees,space)
            audit.update(tree_trunks_removed_from_courts=len(trees)-len(kept),retained_trees=len(kept))
        return space,audit
    forbidden=unary_union([physical_forbidden,civic_clearance_space()])
    greens,inventory=green_spaces(parks,zones["grass"])
    bind_court_identities(greens)
    courts,coverage=select(greens,forbidden,height,with_audit=True)
    records=[]
    for index,court in enumerate(courts):
        records.append(record_for(court,origin_y))
    audit={"courts":len(records),"hoops":sum(len(r["hoops"]) for r in records),"triangles":sum(r["mesh"]["triangles"] for r in records),
           "max_court_grade":max((r["court_grade"] for r in records),default=0),"max_apron_slope_deg":max((r["max_apron_slope_deg"] for r in records),default=0),
           "max_fill_m":max((r["max_fill_m"] for r in records),default=0),"road_building_overlap_m2":sum(r["road_building_overlap_m2"] for r in records)}
    space=unary_union([c["footprint"] for c in courts])
    audit.update(green_inventory=inventory,green_coverage=coverage,covered_greens=len(records),
                 excluded_greens=len(coverage)-len(records),full_courts=sum(r["kind"]=="full" for r in records),
                 placement_limits={"max_fill_m":MAX_FILL,"max_court_grade":MAX_COURT_GRADE,"max_apron_slope_deg":4.0})
    if len(records)<2 or audit["max_apron_slope_deg"]>4 or audit["max_fill_m"]>MAX_FILL or audit["road_building_overlap_m2"]>1e-6:
        raise ValueError("Court placement did not pass publication checks: "+str(audit))
    if trees is not None:
        retained=trees_outside_courts(trees,space)
        audit["tree_trunks_removed_from_courts"]=len(trees)-len(retained)
        audit["retained_trees"]=len(retained)
    path=Path(output); temporary=path.with_suffix(path.suffix+".tmp")
    temporary.write_text(json.dumps({"version":1,"courts":records,"audit":audit},separators=(",",":")),encoding="utf-8")
    temporary.replace(path)
    return space,audit
