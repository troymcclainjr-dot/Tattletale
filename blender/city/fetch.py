"""Download everything the Pen Lucy build needs into .work/city/raw/:
OpenStreetMap (buildings, streets, parks, parking) and the USGS LiDAR tiles.

    python blender/city/fetch.py            # skips files that are already there
    python blender/city/fetch.py --force    # downloads again
"""
import json, os, sys, time, urllib.error, urllib.parse, urllib.request
from concurrent.futures import ThreadPoolExecutor

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import config as C

UA = {"User-Agent": "tattletale-city-build/0.1"}
FORCE = "--force" in sys.argv


def get(url, data=None, timeout=300):
    req = urllib.request.Request(url, data=data, headers=UA)
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.read()


def fetch_osm():
    if os.path.exists(C.OSM_JSON) and not FORCE:
        print("[fetch] osm.json already there")
        return
    s, w, n, e = C.BBOX
    bb = f"({s},{w},{n},{e})"
    q = (f"[out:json][timeout:180];("
         f"way[building]{bb};relation[building]{bb};"
         f"way[highway]{bb};"
         f"way[leisure]{bb};way[landuse]{bb};way[amenity=parking]{bb};"
         f");out tags geom;")
    body = urllib.parse.urlencode({"data": q}).encode()
    for attempt in range(3):
        for ep in C.OVERPASS:
            try:
                raw = get(ep, body)
                d = json.loads(raw)
                stamp = d.get("osm3s", {}).get("timestamp_osm_base", "?")
                with open(C.OSM_JSON, "wb") as f:
                    f.write(raw)
                print(f"[fetch] osm.json: {len(d['elements'])} elements from {ep} (data as of {stamp})")
                return
            except Exception as ex:   # busy mirrors answer with HTML or time out
                print(f"[fetch] {ep} failed: {str(ex)[:120]}")
        time.sleep(20 * (attempt + 1))
    raise SystemExit("[fetch] every Overpass mirror failed; try again in a few minutes")


def download(link, path, size, parts=3):
    """rockyweb serves about 125 KB/s per connection and answers 429 past a few at once, so fetch
    a few byte ranges in parallel, each resuming where it stopped after a 429 or a dropped connection."""
    tmp = path + ".part"
    with open(tmp, "wb") as f:
        f.truncate(size)

    def grab(i):
        time.sleep(2 * i)
        pos, end = i * size // parts, (i + 1) * size // parts - 1
        for attempt in range(10):
            try:
                req = urllib.request.Request(link, headers={**UA, "Range": f"bytes={pos}-{end}"})
                with urllib.request.urlopen(req, timeout=900) as r, open(tmp, "r+b") as f:
                    if r.status != 206:
                        raise RuntimeError(f"server ignored the byte range (HTTP {r.status})")
                    f.seek(pos)
                    while chunk := r.read(1 << 20):
                        f.write(chunk)
                        pos += len(chunk)
                if pos > end:
                    return
            except urllib.error.HTTPError as ex:
                if ex.code not in (429, 500, 502, 503, 504):
                    raise
                print(f"[fetch]   range {i}: HTTP {ex.code}, retrying", flush=True)
                time.sleep(15 * (attempt + 1))
            except (TimeoutError, ConnectionError, urllib.error.URLError) as ex:
                print(f"[fetch]   range {i}: {ex}, retrying", flush=True)
                time.sleep(10)
        raise RuntimeError(f"range {i} of {os.path.basename(path)} kept failing")

    with ThreadPoolExecutor(parts) as ex:
        list(ex.map(grab, range(parts)))
    os.replace(tmp, path)


def fetch_lidar():
    s, w, n, e = C.BBOX
    url = (f"{C.TNM_API}?bbox={w},{s},{e},{n}&datasets="
           + urllib.parse.quote("Lidar Point Cloud (LPC)") + "&max=100&outputFormat=JSON")
    # the API also returns neighbors that only touch the bbox; keep tiles that really overlap it
    hit = lambda bb: bb["minX"] < e - 5e-5 and bb["maxX"] > w + 5e-5 and bb["minY"] < n - 5e-5 and bb["maxY"] > s + 5e-5
    items = [it for it in json.loads(get(url))["items"] if C.LIDAR_PROJECT in it["title"] and hit(it["boundingBox"])]
    if not items:
        raise SystemExit(f"[fetch] no {C.LIDAR_PROJECT} tiles found for the bbox")
    for it in items:
        link = it.get("downloadLazURL") or it["downloadURL"]
        path = os.path.join(C.RAW, os.path.basename(link))
        if os.path.exists(path) and os.path.getsize(path) == it["sizeInBytes"] and not FORCE:
            print(f"[fetch] {os.path.basename(path)} already there")
            continue
        print(f"[fetch] {os.path.basename(path)} ({it['sizeInBytes'] / 1e6:.0f} MB)...", flush=True)
        t0 = time.time()
        download(link, path, it["sizeInBytes"])
        print(f"[fetch]   done in {time.time() - t0:.0f}s", flush=True)
    print(f"[fetch] {len(items)} LiDAR tiles ready")


if __name__ == "__main__":
    os.makedirs(C.RAW, exist_ok=True)
    fetch_osm()
    fetch_lidar()
