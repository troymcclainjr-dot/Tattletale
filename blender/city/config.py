"""Pen Lucy (Baltimore) city build: the area, the data sources and the paths shared by
fetch.py, process.py and blender/assets/pen_lucy.py."""
import os

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
WORK = os.path.join(ROOT, ".work", "city")
RAW = os.path.join(WORK, "raw")             # downloads (OSM json, LiDAR laz), not committed
BUILD = os.path.join(WORK, "build")         # process.py output for Blender, not committed
DATA = os.path.join(ROOT, "blender", "city", "data")   # small derived data that is committed

AREA = "pen_lucy"

# The playable area is the polygon closed by these streets: Greenmount Ave (west), E 41st St (north),
# Argonne Dr (east, the diagonal with the bus stops) and E 38th St (south). Argonne Dr turns east
# past E 41st, so only its diagonal part counts (west of ARGONNE_MAX_LON, south of ARGONNE_MAX_LAT).
NORTH, EAST, SOUTH = "East 41st Street", "Argonne Drive", "East 38th Street"
ARGONNE_MAX_LON, ARGONNE_MAX_LAT = -76.6011, 39.3398
WEST_LON = -76.6100      # Greenmount Ave runs along -76.6095; boundary street points west of it are ignored

SITE_BUFFER = 45.0       # m past the boundary streets, so both sides of every boundary street get built
CONTEXT_BUFFER = 150.0   # m of plain gray massing past the site, so the world doesn't end at a cliff

# Game origin: the Old York Rd / Wyanoke Ave intersection, at ground level (y = 0 there).
ORIGIN_STREETS = ("Old York Road", "Wyanoke Avenue")

# south, west, north, east. Covers the site plus the context ring (two LiDAR tiles: 18suj610550, 18suj620550).
BBOX = (39.3336, -76.6120, 39.3416, -76.5988)

OVERPASS = [
    "https://overpass-api.de/api/interpreter",
    "https://overpass.private.coffee/api/interpreter",
    "https://overpass.kumi.systems/api/interpreter",
]
TNM_API = "https://tnmaccess.nationalmap.gov/api/v1/products"
LIDAR_PROJECT = "MD_4County_D24"   # USGS 3DEP, flown Dec 17-30 2024 (leaf-off), public domain

OSM_JSON = os.path.join(RAW, "osm.json")
GEOM_JSON = os.path.join(BUILD, AREA + "_geom.json")
REPORT_JSON = os.path.join(BUILD, AREA + "_report.json")
BUILDINGS_GEOJSON = os.path.join(DATA, AREA + "_buildings.geojson")
AREA_GEOJSON = os.path.join(DATA, AREA + "_area.geojson")
