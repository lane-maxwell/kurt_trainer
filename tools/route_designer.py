"""Build rides from hand-picked waypoints, routed along OpenStreetMap by the FOSSGIS bike router.

Usage: route_designer.py <designed_routes.json> <output dir>

Each entry: {"collection", "name", "waypoints": [[lat, lon], ...], "loop": bool,
             "direction": "uphill"?, "profile": "bike" (default) | "road",
             "smoothing": moving-average window in 15 m points (default 7),
             "max_grade": fraction, for paved roads (optional)}
Geometry © OpenStreetMap contributors; elevation from USGS 3DEP 10 m.
"""
import json
import os
import sys
import time
import urllib.parse

sys.path.insert(0, os.path.dirname(__file__))
from import_gpx import smooth  # noqa: E402
from osm_trail_to_gpx import despike, elevations, haversine, http, resample, write_gpx  # noqa: E402

ROUTERS = {
    "bike": "https://routing.openstreetmap.de/routed-bike/route/v1/driving/",
    # For road climbs: the bike profile happily detours onto mountain trails.
    "road": "https://routing.openstreetmap.de/routed-car/route/v1/driving/",
}


def route(waypoints, profile="bike"):
    coordinates = ";".join(f"{lon:.6f},{lat:.6f}" for lat, lon in waypoints)
    query = urllib.parse.urlencode({"overview": "full", "geometries": "geojson"})
    data = http(f"{ROUTERS[profile]}{coordinates}?{query}")
    if data.get("code") != "Ok":
        raise SystemExit(f"router error: {data.get('code')} {data.get('message', '')}")
    return [(lat, lon) for lon, lat in data["routes"][0]["geometry"]["coordinates"]]


def cap_grades(points, elevs, max_grade):
    """Clip each segment's grade, then spread the lost height evenly so the summit stays put.

    Paved roads are engineered below ~12%, so steeper samples on a highway are DEM artifacts.
    """
    steps = [haversine(a, b) for a, b in zip(points, points[1:])]
    capped = [elevs[0]]
    for step, a, b in zip(steps, elevs, elevs[1:]):
        rise = max(min(b - a, step * max_grade), -step * max_grade)
        capped.append(capped[-1] + rise)
    total = sum(steps) or 1
    residual = elevs[-1] - capped[-1]
    walked, result = 0.0, [capped[0]]
    for step, value in zip(steps, capped[1:]):
        walked += step
        result.append(value + residual * walked / total)
    return result


def build(spec, out_dir):
    waypoints = [tuple(p) for p in spec["waypoints"]]
    if spec.get("loop"):
        waypoints.append(waypoints[0])
    line = route(waypoints, spec.get("profile", "bike"))
    points = resample(line, 15)
    # Routed tracks carry no bridge tags, so smooth harder than OSM trail builds. Mountain roads
    # cut into a hillside need more: the 10 m grid also samples the slope above and below the road.
    elevs = smooth(despike(elevations(points), window=11), window=spec.get("smoothing", 7))
    if "max_grade" in spec:
        elevs = cap_grades(points, elevs, spec["max_grade"])
    if spec.get("direction") == "uphill" and elevs[-1] < elevs[0]:
        points.reverse()
        elevs.reverse()

    folder = os.path.join(out_dir, spec["collection"])
    os.makedirs(folder, exist_ok=True)
    write_gpx(
        os.path.join(folder, spec["name"] + ".gpx"), spec["name"],
        "Designed for Kinetic Revival. Route © OpenStreetMap contributors (ODbL), routed with FOSSGIS OSRM. "
        "Elevation: USGS 3DEP/NED 10 m via OpenTopoData.",
        points, elevs,
    )
    length = sum(haversine(a, b) for a, b in zip(points, points[1:]))
    straight = sum(haversine(a, b) for a, b in zip(waypoints, waypoints[1:]))
    gain = sum(max(b - a, 0) for a, b in zip(elevs, elevs[1:]))
    print(f"{spec['name']}: {length/1000:.1f} km (waypoint straight-line {straight/1000:.1f} km, "
          f"detour x{length/max(straight, 1):.2f}), gain {gain:.0f} m, elevation {min(elevs):.0f}-{max(elevs):.0f} m",
          flush=True)


if __name__ == "__main__":
    spec_path, out_dir = sys.argv[1:3]
    only = set(sys.argv[3:])
    for spec in json.load(open(spec_path)):
        if only and spec["name"] not in only:
            continue
        try:
            build(spec, out_dir)
        except (Exception, SystemExit) as error:
            print(f"{spec['name']}: FAILED {error}", flush=True)
        time.sleep(1)
