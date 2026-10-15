"""Normalise a third-party GPX (e.g. a RideWithGPS export) into a bundled route.

Usage: import_gpx.py <in.gpx> <out.gpx> <display name> [--reelevate]

--reelevate resamples the track every 15 m and replaces its elevation with USGS 3DEP 10 m data
(median-filtered), for files whose own elevation has spikes.
"""
import sys
import xml.etree.ElementTree as ET

sys.path.insert(0, __import__("os").path.dirname(__file__))
from osm_trail_to_gpx import despike, elevations, haversine, resample  # noqa: E402
from xml.sax.saxutils import escape

NS = {"g": "http://www.topografix.com/GPX/1/1"}


def smooth(values, window):
    half = window // 2
    return [sum(values[max(0, i - half):i + half + 1]) / len(values[max(0, i - half):i + half + 1])
            for i in range(len(values))]


def main(in_path, out_path, name, reelevate):
    root = ET.parse(in_path).getroot()
    link = root.find("g:metadata/g:link", NS)
    source = link.get("href") if link is not None else in_path.rsplit("/", 1)[-1]
    points = [
        (float(p.get("lat")), float(p.get("lon")), p.findtext("g:ele", namespaces=NS))
        for p in root.iterfind(".//g:trkpt", NS)
    ]
    if len(points) < 2:
        raise SystemExit(f"{in_path}: fewer than 2 track points")

    if reelevate:
        coords = resample([(lat, lon) for lat, lon, _ in points], 15)
        # Median removes spikes; the moving average then rounds off creek-crossing dips that GPX,
        # unlike OSM, has no bridge tags to level.
        elevs = smooth(despike(elevations(coords), window=11), window=7)
        rows = list(zip(coords, elevs))
        elevation_note = "Elevation: USGS 3DEP/NED 10 m via OpenTopoData."
    else:
        rows = [((lat, lon), float(e)) for lat, lon, e in points if e is not None]
        elevation_note = "Elevation from the source file."

    length = sum(haversine(a[0], b[0]) for a, b in zip(rows, rows[1:]))
    track = "\n".join(f'      <trkpt lat="{c[0]:.6f}" lon="{c[1]:.6f}"><ele>{e:.1f}</ele></trkpt>' for c, e in rows)
    with open(out_path, "w") as f:
        f.write(f"""<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="Kinetic Revival route importer" xmlns="http://www.topografix.com/GPX/1/1">
  <metadata>
    <name>{escape(name)}</name>
    <desc>{escape(f"Route from {source}. {elevation_note}")}</desc>
  </metadata>
  <trk>
    <name>{escape(name)}</name>
    <trkseg>
{track}
    </trkseg>
  </trk>
</gpx>
""")
    print(f"{name}: {length/1000:.1f} km, {len(rows)} points, elevation {min(e for _, e in rows):.0f}-{max(e for _, e in rows):.0f} m", flush=True)


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    main(*args, reelevate="--reelevate" in sys.argv)
