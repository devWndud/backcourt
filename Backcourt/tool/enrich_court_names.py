#!/usr/bin/env python3
"""Match unnamed courts to Korean 읍·면·동 polygons and persist stable names."""

import argparse
import json
import math
import ssl
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

import certifi


DEFAULT_BOUNDARIES = (
    "https://raw.githubusercontent.com/southkorea/southkorea-maps/master/"
    "kostat/2018/json/skorea-submunicipalities-2018-geo.json"
)
UNNAMED_COURT = "이름 없는 농구 코트"
SSL_CONTEXT = ssl.create_default_context(cafile=certifi.where())


def load_json(source: str) -> dict:
    path = Path(source)
    if path.exists():
        return json.loads(path.read_text())
    request = urllib.request.Request(
        source,
        headers={"User-Agent": "Backcourt court catalog builder (backcourt.kr)"},
    )
    with urllib.request.urlopen(request, context=SSL_CONTEXT) as response:
        return json.load(response)


def geometry_bounds(geometry: dict) -> tuple[float, float, float, float]:
    points: list[tuple[float, float]] = []

    def collect(value: object) -> None:
        if (
            isinstance(value, list)
            and len(value) >= 2
            and isinstance(value[0], (int, float))
            and isinstance(value[1], (int, float))
        ):
            points.append((float(value[0]), float(value[1])))
            return
        if isinstance(value, list):
            for child in value:
                collect(child)

    collect(geometry.get("coordinates", []))
    if not points:
        raise ValueError("좌표가 없는 행정경계가 있습니다.")
    xs = [point[0] for point in points]
    ys = [point[1] for point in points]
    return min(xs), min(ys), max(xs), max(ys)


def point_in_ring(longitude: float, latitude: float, ring: list) -> bool:
    inside = False
    previous = ring[-1]
    for current in ring:
        x1, y1 = float(previous[0]), float(previous[1])
        x2, y2 = float(current[0]), float(current[1])
        crosses = (y1 > latitude) != (y2 > latitude)
        if crosses:
            boundary_x = (x2 - x1) * (latitude - y1) / (y2 - y1) + x1
            if longitude < boundary_x:
                inside = not inside
        previous = current
    return inside


def point_in_polygon(longitude: float, latitude: float, polygon: list) -> bool:
    if not polygon or not point_in_ring(longitude, latitude, polygon[0]):
        return False
    return not any(point_in_ring(longitude, latitude, hole) for hole in polygon[1:])


def point_in_geometry(longitude: float, latitude: float, geometry: dict) -> bool:
    coordinates = geometry.get("coordinates", [])
    if geometry.get("type") == "Polygon":
        return point_in_polygon(longitude, latitude, coordinates)
    if geometry.get("type") == "MultiPolygon":
        return any(
            point_in_polygon(longitude, latitude, polygon)
            for polygon in coordinates
        )
    return False


def prepare_regions(boundaries: dict) -> list[dict]:
    result = []
    for feature in boundaries.get("features", []):
        properties = feature.get("properties", {})
        geometry = feature.get("geometry", {})
        name = str(properties.get("name") or "").strip()
        if not name:
            continue
        bounds = geometry_bounds(geometry)
        result.append(
            {
                "name": name,
                "englishName": properties.get("name_eng"),
                "code": str(properties.get("code") or ""),
                "baseYear": str(properties.get("base_year") or "2018"),
                "geometry": geometry,
                "bounds": bounds,
                "area": (bounds[2] - bounds[0]) * (bounds[3] - bounds[1]),
                "center": ((bounds[0] + bounds[2]) / 2, (bounds[1] + bounds[3]) / 2),
            }
        )
    if not result:
        raise ValueError("행정경계 데이터가 비어 있습니다.")
    return result


def distance_to_region(longitude: float, latitude: float, region: dict) -> float:
    center_longitude, center_latitude = region["center"]
    longitude_scale = math.cos(math.radians(latitude))
    return math.hypot(
        (center_longitude - longitude) * longitude_scale,
        center_latitude - latitude,
    )


def match_region(longitude: float, latitude: float, regions: list[dict]) -> tuple[dict, str]:
    candidates = []
    for region in regions:
        min_x, min_y, max_x, max_y = region["bounds"]
        if min_x <= longitude <= max_x and min_y <= latitude <= max_y:
            if point_in_geometry(longitude, latitude, region["geometry"]):
                candidates.append(region)
    if candidates:
        return min(candidates, key=lambda region: region["area"]), "polygon"
    return min(
        regions,
        key=lambda region: distance_to_region(longitude, latitude, region),
    ), "nearest"


def is_osm_named(properties: dict) -> bool:
    source = properties.get("name_source")
    name = str(properties.get("name") or "").strip()
    if source == "openstreetmap":
        return True
    if source in {"kostat_2018_neighborhood", "address_fallback", "generated"}:
        return False
    return bool(name and name != UNNAMED_COURT)


def enrich(catalog: dict, boundaries: dict) -> dict[str, int]:
    regions = prepare_regions(boundaries)
    matched = 0
    nearest = 0
    preserved = 0
    for feature in catalog.get("features", []):
        properties = feature.setdefault("properties", {})
        coordinates = feature.get("geometry", {}).get("coordinates", [])
        region, match_type = match_region(
            float(coordinates[0]),
            float(coordinates[1]),
            regions,
        )
        properties["administrative_name"] = region["name"]
        properties["administrative_name_eng"] = region["englishName"]
        properties["administrative_code"] = region["code"]
        properties["administrative_base_year"] = region["baseYear"]
        properties["administrative_match"] = match_type
        if match_type == "nearest":
            nearest += 1
        if is_osm_named(properties):
            properties["name_source"] = "openstreetmap"
            preserved += 1
            continue
        properties["name"] = f"{region['name']} 농구장"
        properties["name_source"] = "kostat_2018_neighborhood"
        matched += 1

    catalog.setdefault("metadata", {})["name_enrichment"] = {
        "source": "KOSTAT 2018 administrative boundaries",
        "license": "Korea Open Government License Type 1",
        "source_url": DEFAULT_BOUNDARIES,
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "matched_unnamed_courts": matched,
        "nearest_fallbacks": nearest,
    }
    return {
        "regions": len(regions),
        "matched": matched,
        "nearest": nearest,
        "preserved": preserved,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--catalog",
        default="assets/data/korea_basketball_courts.geojson",
    )
    parser.add_argument("--boundaries", default=DEFAULT_BOUNDARIES)
    args = parser.parse_args()

    catalog_path = Path(args.catalog)
    catalog = json.loads(catalog_path.read_text())
    stats = enrich(catalog, load_json(args.boundaries))
    temporary_path = catalog_path.with_suffix(".geojson.tmp")
    temporary_path.write_text(
        json.dumps(catalog, ensure_ascii=False, separators=(",", ":"))
    )
    temporary_path.replace(catalog_path)
    print(
        f"행정구역 {stats['regions']}개 / OSM 실명 {stats['preserved']}개 보존 / "
        f"동네명 {stats['matched']}개 생성 / 근접 보정 {stats['nearest']}개"
    )


if __name__ == "__main__":
    main()
