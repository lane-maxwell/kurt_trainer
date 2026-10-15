"""Build a single-track GPX for a named trail from OpenStreetMap ways plus Open-Meteo elevation.

The trail's ways form a graph; the main line is taken as the longest of the shortest paths
between dead ends (the graph's diameter), which drops short spurs and connectors.
"""
import heapq
import json
import math
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from xml.sax.saxutils import escape

UA = {"User-Agent": "KineticRevival/0.1 (personal trainer app route builder)"}


def http(url, data=None, attempts=5):
    for attempt in range(attempts):
        try:
            req = urllib.request.Request(url, data=data, headers=UA)
            with urllib.request.urlopen(req, timeout=90) as response:
                return json.load(response)
        except (urllib.error.HTTPError, urllib.error.URLError, TimeoutError) as error:
            if attempt == attempts - 1:
                raise
            wait = 10 * (attempt + 1)
            print(f"  {error}; retrying in {wait}s", file=sys.stderr)
            time.sleep(wait)


def haversine(a, b):
    r = 6371008.8
    la1, lo1, la2, lo2 = map(math.radians, (a[0], a[1], b[0], b[1]))
    h = math.sin((la2 - la1) / 2) ** 2 + math.cos(la1) * math.cos(la2) * math.sin((lo2 - lo1) / 2) ** 2
    return 2 * r * math.asin(min(1, math.sqrt(h)))


def fetch_graph(endpoint, name, bbox):
    # One corridor often carries several names along its length, so `name` may be a list.
    names = name if isinstance(name, list) else [name]
    pattern = "^(" + "|".join(re.escape(n) for n in names) + ")$"
    query = f'[out:json][timeout:60];way["name"~"{pattern}"]({bbox});out body;>;out skel qt;'
    data = http(endpoint, urllib.parse.urlencode({"data": query}).encode())
    nodes = {e["id"]: (e["lat"], e["lon"]) for e in data["elements"] if e["type"] == "node"}
    ways = [e for e in data["elements"] if e["type"] == "way"]
    if not ways:
        raise SystemExit(f"no ways named {name!r}")
    graph, elevated = {}, set()
    for way in ways:
        tags = way.get("tags", {})
        off_ground = tags.get("bridge", "no") != "no" or tags.get("tunnel", "no") != "no"
        for a, b in zip(way["nodes"], way["nodes"][1:]):
            d = haversine(nodes[a], nodes[b])
            graph.setdefault(a, {})[b] = d
            graph.setdefault(b, {})[a] = d
            if off_ground:
                elevated.add(frozenset((a, b)))
    return nodes, graph, elevated


def join_gaps(graph, nodes, max_gap=100):
    """OSM trails are often split at road crossings; reconnect pieces whose ends are close."""
    def components():
        seen, result = set(), []
        for start in graph:
            if start in seen:
                continue
            stack, members = [start], []
            seen.add(start)
            while stack:
                u = stack.pop()
                members.append(u)
                for v in graph[u]:
                    if v not in seen:
                        seen.add(v)
                        stack.append(v)
            result.append(members)
        return result

    joined = []
    while True:
        parts = components()
        if len(parts) == 1:
            return joined
        best = None
        for i, part in enumerate(parts):
            ends = [n for n in part if len(graph[n]) == 1] or part
            for j, other in enumerate(parts):
                if i == j:
                    continue
                for a in ends:
                    for b in other:
                        d = haversine(nodes[a], nodes[b])
                        if d <= max_gap and (best is None or d < best[0]):
                            best = (d, a, b)
        if best is None:
            return joined
        d, a, b = best
        graph[a][b] = d
        graph[b][a] = d
        joined.append((d, a, b))


def dijkstra(graph, source):
    dist, prev, heap = {source: 0.0}, {}, [(0.0, source)]
    while heap:
        d, u = heapq.heappop(heap)
        if d > dist[u]:
            continue
        for v, w in graph[u].items():
            nd = d + w
            if nd < dist.get(v, math.inf):
                dist[v], prev[v] = nd, u
                heapq.heappush(heap, (nd, v))
    return dist, prev


def farthest_ends_line(graph, nodes):
    """Shortest path between the two dead ends farthest apart on the map.

    Trails mapped as parallel bike and foot paths have dead ends side by side; taking the graph's
    longest shortest path then rides up one path and back down the other. Picking the ends that
    are farthest apart geographically gives the end-to-end trail instead.
    """
    # Restrict to the biggest connected piece, in case some fragment couldn't be joined.
    seen, biggest = set(), set()
    for start in graph:
        if start in seen:
            continue
        stack, part = [start], {start}
        while stack:
            for v in graph[stack.pop()]:
                if v not in part:
                    part.add(v)
                    stack.append(v)
        seen |= part
        biggest = max(biggest, part, key=len)
    ends = [n for n in biggest if len(graph[n]) == 1]
    if len(ends) < 2:
        return main_line(graph)
    a, b = max(((x, y) for i, x in enumerate(ends) for y in ends[i + 1:]),
               key=lambda pair: haversine(nodes[pair[0]], nodes[pair[1]]))
    dist, prev = dijkstra(graph, a)
    if b not in dist:
        return main_line(graph)
    path = [b]
    while path[-1] != a:
        path.append(prev[path[-1]])
    return dist[b], path[::-1]


def routed_gap(a, b, vias=()):
    """Bike-router geometry between two points, used to bridge gaps along real paths.

    `vias` are hand-placed points that keep the router on an unnamed riverside path when its
    shortest option would cut inland; only those inside the gap's bounding box are used.
    """
    lo_lat, hi_lat = sorted((a[0], b[0]))
    lo_lon, hi_lon = sorted((a[1], b[1]))
    pad = 0.003
    inside = [v for v in vias if lo_lat - pad <= v[0] <= hi_lat + pad and lo_lon - pad <= v[1] <= hi_lon + pad]
    inside.sort(key=lambda v: haversine(a, v))
    points = [a, *inside, b]
    coordinates = ";".join(f"{p[1]:.7f},{p[0]:.7f}" for p in points)
    query = urllib.parse.urlencode({"overview": "full", "geometries": "geojson"})
    url = f"https://routing.openstreetmap.de/routed-bike/route/v1/driving/{coordinates}?{query}"
    data = http(url)
    if data.get("code") != "Ok":
        return [a, b]
    return [(lat, lon) for lon, lat in data["routes"][0]["geometry"]["coordinates"]]


def main_line(graph):
    ends = [n for n, adj in graph.items() if len(adj) == 1] or list(graph)
    if len(ends) > 60:
        # Exhaustive search is quadratic; the farthest pair is almost always among far-apart ends.
        ends = sorted(ends)[:: max(len(ends) // 60, 1)]
    best = (0.0, None, None, None)
    for source in ends:
        dist, prev = dijkstra(graph, source)
        target = max((n for n in ends if n in dist), key=lambda n: dist[n])
        if dist[target] > best[0]:
            best = (dist[target], source, target, prev)
    length, source, target, prev = best
    path = [target]
    while path[-1] != source:
        path.append(prev[path[-1]])
    return length, path[::-1]


def elevated_intervals(path, nodes, elevated):
    """Distance ranges along the path that are on bridges or in tunnels, merged when adjacent."""
    intervals, distance = [], 0.0
    for a, b in zip(path, path[1:]):
        length = haversine(nodes[a], nodes[b])
        if frozenset((a, b)) in elevated:
            if intervals and abs(intervals[-1][1] - distance) < 1:
                intervals[-1][1] = distance + length
            else:
                intervals.append([distance, distance + length])
        distance += length
    return intervals


def level_elevated_sections(elevs, spacing, intervals, total):
    """The DEM sees the river or road under a bridge, so span each one with a straight line."""
    elevs = list(elevs)
    positions = [min(i * spacing, total) for i in range(len(elevs))]
    for start, end in intervals:
        inside = [i for i, d in enumerate(positions) if start <= d <= end]
        if not inside:
            continue
        before = max(inside[0] - 1, 0)
        after = min(inside[-1] + 1, len(elevs) - 1)
        span = positions[after] - positions[before]
        for i in inside:
            fraction = (positions[i] - positions[before]) / span if span > 0 else 0
            elevs[i] = elevs[before] + (elevs[after] - elevs[before]) * fraction
    return elevs


def resample(points, spacing):
    out, carry = [points[0]], 0.0
    for a, b in zip(points, points[1:]):
        seg = haversine(a, b)
        pos = spacing - carry
        while pos <= seg:
            f = pos / seg
            out.append((a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f))
            pos += spacing
        carry = seg - (pos - spacing)
    if out[-1] != points[-1]:
        out.append(points[-1])
    return out


def elevations(points):
    """USGS NED 1/3 arc-second (~10 m) via OpenTopoData; coarser global DEMs blend in nearby bluffs."""
    result = []
    for i in range(0, len(points), 100):
        chunk = points[i:i + 100]
        locations = "|".join(f"{p[0]:.6f},{p[1]:.6f}" for p in chunk)
        data = http("https://api.opentopodata.org/v1/ned10m?" + urllib.parse.urlencode({"locations": locations}))
        result += [r["elevation"] for r in data["results"]]
        time.sleep(1.1)
    if len(result) != len(points) or any(e is None for e in result):
        raise SystemExit("elevation lookup returned missing values")
    return result


def despike(values, window=11):
    """Rolling median: removes bridges, culverts and DEM pixels that catch a bluff edge."""
    half = window // 2
    return [sorted(values[max(0, i - half):i + half + 1])[len(values[max(0, i - half):i + half + 1]) // 2]
            for i in range(len(values))]


def write_gpx(path, name, description, points, elevs):
    rows = "\n".join(
        f'      <trkpt lat="{p[0]:.6f}" lon="{p[1]:.6f}"><ele>{e:.1f}</ele></trkpt>'
        for p, e in zip(points, elevs)
    )
    with open(path, "w") as f:
        f.write(f"""<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="Kinetic Revival route builder" xmlns="http://www.topografix.com/GPX/1/1">
  <metadata>
    <name>{escape(name)}</name>
    <desc>{escape(description)}</desc>
    <copyright author="OpenStreetMap contributors"><license>https://opendatacommons.org/licenses/odbl/</license></copyright>
  </metadata>
  <trk>
    <name>{escape(name)}</name>
    <trkseg>
{rows}
    </trkseg>
  </trk>
</gpx>
""")


def build(endpoint, osm_name, display_name, bbox, out_path, direction=None, max_gap=600, vias=()):
    nodes, graph, elevated = fetch_graph(endpoint, osm_name, bbox)
    joined = join_gaps(graph, nodes, max_gap)
    length, path = farthest_ends_line(graph, nodes)
    gaps = {frozenset((a, b)) for d, a, b in joined if d > 40}
    coords = [nodes[path[0]]]
    for a, b in zip(path, path[1:]):
        if frozenset((a, b)) in gaps:
            coords += routed_gap(nodes[a], nodes[b], [tuple(v) for v in vias])[1:]
        else:
            coords.append(nodes[b])
    total_ways_length = sum(sum(adj.values()) for adj in graph.values()) / 2
    spacing = 15
    points = resample(coords, spacing)
    bridges = elevated_intervals(path, nodes, elevated)
    elevs = despike(level_elevated_sections(elevations(points), spacing, bridges, length))
    if (direction == "uphill" and elevs[-1] < elevs[0]) or (direction == "downhill" and elevs[-1] > elevs[0]):
        points.reverse()
        elevs.reverse()
    write_gpx(
        out_path, display_name,
        "Trail geometry © OpenStreetMap contributors (ODbL). Elevation: USGS 3DEP/NED 10 m via OpenTopoData.",
        points, elevs,
    )
    print(f"{display_name}: {length/1000:.2f} km main line of {total_ways_length/1000:.2f} km mapped, "
          f"{len(joined)} gaps joined (longest {max((d for d, _, _ in joined), default=0):.0f} m, {len(gaps)} routed), {len(bridges)} bridges levelled, {len(points)} points, "
          f"elevation {min(elevs):.0f}-{max(elevs):.0f} m", flush=True)


if __name__ == "__main__":
    import os
    if len(sys.argv) == 4 and sys.argv[2].endswith(".json"):
        # Batch: osm_trail_to_gpx.py <endpoint> <routes.json> <output dir>
        endpoint, spec_path, out_dir = sys.argv[1:4]
        failures = []
        for spec in json.load(open(spec_path)):
            folder = os.path.join(out_dir, spec["collection"])
            os.makedirs(folder, exist_ok=True)
            out_path = os.path.join(folder, spec["name"] + ".gpx")
            if os.path.exists(out_path):
                print(f"{spec['name']}: exists, skipping", flush=True)
                continue
            try:
                build(endpoint, spec["osm"], spec["name"], spec["bbox"], out_path, spec.get("direction"), spec.get("max_gap", 600), spec.get("gap_vias", ()))
            except (Exception, SystemExit) as error:
                failures.append(spec["name"])
                print(f"{spec['name']}: FAILED {error}", flush=True)
            time.sleep(2)
        print("failures:", failures or "none")
    else:
        endpoint, osm_name, display_name, bbox, out_path = sys.argv[1:6]
        build(endpoint, osm_name, display_name, bbox, out_path, sys.argv[6] if len(sys.argv) > 6 else None)
