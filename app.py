from fastapi import FastAPI, HTTPException, Query, Request
from fastapi.middleware.cors import CORSMiddleware
from contextlib import asynccontextmanager
from dotenv import load_dotenv
from math import radians, sin, cos, asin, sqrt
from pydantic import BaseModel
import asyncio
import hashlib
import httpx
import json
import os
import sys
import uuid

load_dotenv()

if sys.platform == "win32":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")


# ── 순수 계산 함수 (동기) ─────────────────────────────────────────

def _haversine_km(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    R = 6371
    dlat = radians(lat2 - lat1)
    dlng = radians(lng2 - lng1)
    a = sin(dlat / 2) ** 2 + cos(radians(lat1)) * cos(radians(lat2)) * sin(dlng / 2) ** 2
    return 2 * R * asin(sqrt(a))

# 거리 공평
def _fair_midpoint(points: list, max_iter: int = 200) -> tuple:
    n = len(points)
    if n == 1:
        return points[0]
    if n == 2:
        return ((points[0][0] + points[1][0]) / 2, (points[0][1] + points[1][1]) / 2)
    cx = sum(p[0] for p in points) / n
    cy = sum(p[1] for p in points) / n
    step = 0.5
    for _ in range(max_iter):
        farthest = max(points, key=lambda p: _haversine_km(cx, cy, p[0], p[1]))
        cx += (farthest[0] - cx) * step
        cy += (farthest[1] - cy) * step
        step *= 0.97
        if step < 0.0005:
            break
    return cx, cy


def _cluster_centroid(members: list, cluster_radius_km: float = 5.0) -> tuple:
    """멤버들을 반경 내 클러스터로 묶고 인원수 가중 평균 좌표 반환."""
    clusters = []
    assigned = [False] * len(members)
    for i, m in enumerate(members):
        if assigned[i]:
            continue
        cluster_lats = [m["lat"]]
        cluster_lngs = [m["lng"]]
        assigned[i] = True
        for j, other in enumerate(members):
            if assigned[j]:
                continue
            if _haversine_km(m["lat"], m["lng"], other["lat"], other["lng"]) <= cluster_radius_km:
                cluster_lats.append(other["lat"])
                cluster_lngs.append(other["lng"])
                assigned[j] = True
        clusters.append({
            "lat": sum(cluster_lats) / len(cluster_lats),
            "lng": sum(cluster_lngs) / len(cluster_lngs),
            "weight": len(cluster_lats),
        })
    total_w = sum(c["weight"] for c in clusters)
    return (
        sum(c["lat"] * c["weight"] for c in clusters) / total_w,
        sum(c["lng"] * c["weight"] for c in clusters) / total_w,
    )


async def _majority_midpoint(
    client: httpx.AsyncClient,
    members: list,
    cluster_radius_km: float = 5.0,
    bias: float = 0.4,
) -> tuple:
    """다수결: 거리 공평(실경로) 결과를 앵커로 하고, 다수 클러스터 중심 쪽으로 bias 만큼 치우침.
    bias=0 이면 순수 거리 공평, bias=1 이면 순수 클러스터 가중 평균.
    """
    if len(members) == 1:
        return members[0]["lat"], members[0]["lng"]
    if len(members) == 2:
        return (
            (members[0]["lat"] + members[1]["lat"]) / 2,
            (members[0]["lng"] + members[1]["lng"]) / 2,
        )

    # 1) 거리 공평 (실경로) 기준점
    fair_lat, fair_lng, _ = await _route_distance_fair_midpoint(client, members)

    # 2) 다수(인원 가중 클러스터) 중심
    maj_lat, maj_lng = _cluster_centroid(members, cluster_radius_km)

    # 3) 블렌딩: 거리 공평 → 다수 방향으로 bias 비율만큼 이동
    return (
        fair_lat * (1 - bias) + maj_lat * bias,
        fair_lng * (1 - bias) + maj_lng * bias,
    )


# ── 비동기 외부 API 호출 ──────────────────────────────────────────

async def _get_transit_metrics(client: httpx.AsyncClient, src_lat, src_lng, dst_lat, dst_lng):
    """ODsay 대중교통: (time_min, distance_km) 튜플. 실패 시 (None, None)."""
    odsay_key = os.getenv("ODSAY_API_KEY")
    if not odsay_key:
        return None, None
    try:
        resp = await client.get(
            "https://api.odsay.com/v1/api/searchPubTransPathT",
            params={"apiKey": odsay_key, "SX": src_lng, "SY": src_lat, "EX": dst_lng, "EY": dst_lat},
            timeout=10.0,
        )
        resp.raise_for_status()
        data = resp.json()
        result = data.get("result")
        if not result:
            return None, None
        paths = result.get("path", [])
        if not paths:
            return None, None
        info = paths[0].get("info", {})
        total_time = info.get("totalTime")
        total_dist_m = info.get("totalDistance")
        time_min = int(total_time) if total_time else None
        dist_km = (total_dist_m / 1000.0) if total_dist_m else None
        return time_min, dist_km
    except Exception as e:
        print(f"[ODsay error] {e}")
        return None, None


async def _get_car_metrics(client: httpx.AsyncClient, src_lat, src_lng, dst_lat, dst_lng):
    """카카오 모빌리티: (time_min, distance_km) 튜플. 실패 시 (None, None)."""
    kakao_key = os.getenv("KAKAO_API_KEY")
    if not kakao_key:
        return None, None
    try:
        resp = await client.get(
            "https://apis-navi.kakaomobility.com/v1/directions",
            params={"origin": f"{src_lng},{src_lat}", "destination": f"{dst_lng},{dst_lat}"},
            headers={"Authorization": f"KakaoAK {kakao_key}"},
            timeout=10.0,
        )
        resp.raise_for_status()
        routes = resp.json().get("routes", [])
        if not routes:
            return None, None
        summary = routes[0].get("summary", {})
        duration_sec = summary.get("duration", 0)
        distance_m = summary.get("distance", 0)
        time_min = max(1, round(duration_sec / 60)) if duration_sec else None
        dist_km = (distance_m / 1000.0) if distance_m else None
        return time_min, dist_km
    except Exception as e:
        print(f"[Kakao Navi error] {e}")
        return None, None


# ── Polyline 추출 ─────────────────────────────────────────────────

# ODsay subwayCode → OSM relation ref 매핑
_SUBWAY_CODE_TO_OSM_REF: dict = {
    21: "수인분당", 22: "신분당", 23: "경의",
    101: "공항", 104: "경춘", 109: "서해",
    71: "1", 72: "2", 73: "3", 74: "4",   # 부산
    91: "1", 92: "2",                       # 대구
    81: "1",                                # 광주
    131: "1",                               # 대전
}

# ── 파일 캐시 (역 ID 쌍 → polyline coords) ────────────────────────
_SUBWAY_CACHE_PATH = os.path.join(os.path.dirname(__file__), "data", "subway_cache.json")
_subway_file_cache: dict = {}   # "{sc}:{lo_id}:{hi_id}" → {"coords": [...], "lo_first": bool}
_osm_subway_cache: dict = {}    # (ref, bbox) → assembled paths (메모리 한정)


def _load_subway_file_cache() -> None:
    try:
        with open(_SUBWAY_CACHE_PATH, encoding="utf-8") as f:
            data = json.load(f)
        _subway_file_cache.clear()
        _subway_file_cache.update(data)
        print(f"[SubwayCache] {len(_subway_file_cache)}개 역간 구간 로드")
    except FileNotFoundError:
        print("[SubwayCache] 캐시 파일 없음 — prebuild 스크립트를 실행하세요")
    except Exception as e:
        print(f"[SubwayCache] 로드 오류: {e}")


def _save_subway_file_cache() -> None:
    try:
        os.makedirs(os.path.dirname(_SUBWAY_CACHE_PATH), exist_ok=True)
        with open(_SUBWAY_CACHE_PATH, "w", encoding="utf-8") as f:
            json.dump(_subway_file_cache, f, ensure_ascii=False, separators=(",", ":"))
    except Exception as e:
        print(f"[SubwayCache] 저장 오류: {e}")


def _cache_key(sc: int, id0: int, id1: int) -> str:
    lo, hi = (id0, id1) if id0 <= id1 else (id1, id0)
    return f"{sc}:{lo}:{hi}"


def _lookup_pair(sc: int, id0: int, id1: int) -> list | None:
    key = _cache_key(sc, id0, id1)
    entry = _subway_file_cache.get(key)
    if entry is None:
        return None
    coords = entry["coords"]
    lo_first = entry["lo_first"]
    forward_requested = (id0 <= id1)
    if forward_requested == lo_first:
        return coords
    return list(reversed(coords))


def _store_pair(sc: int, id0: int, id1: int, coords: list) -> None:
    key = _cache_key(sc, id0, id1)
    _subway_file_cache[key] = {"coords": coords, "lo_first": (id0 <= id1)}


# ── OSM 조립 ──────────────────────────────────────────────────────

def _assemble_osm_ways(elems: list) -> list:
    """OSM way 세그먼트를 연속 경로 목록으로 조립. [[lng,lat],...] 리스트."""
    TOLERANCE = 0.0001

    def close(a, b):
        return abs(a[0] - b[0]) < TOLERANCE and abs(a[1] - b[1]) < TOLERANCE

    coords_list = []
    for w in elems:
        geom = w.get("geometry", [])
        if len(geom) >= 2:
            coords_list.append([(g["lon"], g["lat"]) for g in geom])

    used = [False] * len(coords_list)
    paths = []
    for i in range(len(coords_list)):
        if used[i]:
            continue
        path = list(coords_list[i])
        used[i] = True
        changed = True
        while changed:
            changed = False
            for j in range(len(coords_list)):
                if used[j]:
                    continue
                c = coords_list[j]
                if close(path[-1], c[0]):
                    path.extend(c[1:]); used[j] = True; changed = True
                elif close(path[-1], c[-1]):
                    path.extend(list(reversed(c))[1:]); used[j] = True; changed = True
                elif close(path[0], c[-1]):
                    path = list(c[:-1]) + path; used[j] = True; changed = True
                elif close(path[0], c[0]):
                    path = list(reversed(c[:-1])) + path; used[j] = True; changed = True
        paths.append(path)
    return paths


def slice_lane_coords(
    all_paths: list,
    start_lng: float, start_lat: float,
    end_lng: float,   end_lat: float,
    start_name: str = "", end_name: str = "",
) -> list | None:
    """
    assembled OSM paths에서 출발역→도착역 구간만 슬라이싱.
    1. 두 역 모두 800m 이내에 있는 경로 후보 선정
    2. 후보 중 추출 구간 길이가 가장 짧은 경로 선택 (U-turn 루프 자연 탈락)
    3. poly거리 / 직선거리 > 5.0 이면 역 좌표 2점 직선 반환
    4. 매칭 실패 시 None 반환
    """
    NEAR_TH_SQ = 0.008 ** 2

    def nearest_idx(path, lng, lat):
        return min(range(len(path)), key=lambda i: (path[i][0] - lng) ** 2 + (path[i][1] - lat) ** 2)

    def near_dist_sq(path, lng, lat):
        i = nearest_idx(path, lng, lat)
        return (path[i][0] - lng) ** 2 + (path[i][1] - lat) ** 2

    def seg_path_len(path, i0, i1):
        lo, hi = (i0, i1) if i0 <= i1 else (i1, i0)
        total = 0.0
        for k in range(lo, hi):
            dlng = path[k + 1][0] - path[k][0]
            dlat = path[k + 1][1] - path[k][1]
            total += (dlng * dlng + dlat * dlat) ** 0.5
        return total

    direct_deg = ((end_lng - start_lng) ** 2 + (end_lat - start_lat) ** 2) ** 0.5

    best_path = None
    best_i0 = 0
    best_i1 = 0
    best_len = float("inf")

    for path in all_paths:
        d0 = near_dist_sq(path, start_lng, start_lat)
        d1 = near_dist_sq(path, end_lng, end_lat)
        if d0 < NEAR_TH_SQ and d1 < NEAR_TH_SQ:
            i0c = nearest_idx(path, start_lng, start_lat)
            i1c = nearest_idx(path, end_lng, end_lat)
            sl = seg_path_len(path, i0c, i1c)
            if sl < best_len:
                best_len = sl
                best_path = path
                best_i0 = i0c
                best_i1 = i1c

    if best_path is None:
        return None

    lo, hi = (best_i0, best_i1) if best_i0 <= best_i1 else (best_i1, best_i0)
    seg = best_path[lo : hi + 1]
    if best_i0 > best_i1:
        seg = list(reversed(seg))

    ratio = best_len / direct_deg if direct_deg > 1e-9 else 0.0
    if start_name or end_name:
        print(f"[SubwayCache] {start_name}→{end_name}: {best_len*111:.2f}km / {direct_deg*111:.2f}km = {ratio:.1f}x")

    if ratio > 5.0:
        print(f"[SubwayCache] U-turn 감지 (ratio {ratio:.1f}x), 역 좌표 직선 사용")
        return [[start_lng, start_lat], [end_lng, end_lat]]

    return seg


async def _fetch_osm_paths(client: httpx.AsyncClient, subway_code: int, stations: list) -> list:
    """주어진 노선·bbox의 OSM assembled paths 반환. 메모리 캐시 우선."""
    lats = [float(s["y"]) for s in stations]
    lngs = [float(s["x"]) for s in stations]
    margin = 0.06
    min_lat = round(min(lats) - margin, 2)
    max_lat = round(max(lats) + margin, 2)
    min_lng = round(min(lngs) - margin, 2)
    max_lng = round(max(lngs) + margin, 2)

    ref = _SUBWAY_CODE_TO_OSM_REF.get(subway_code, str(subway_code))
    cache_key = (ref, min_lat, min_lng, max_lat, max_lng)

    if cache_key not in _osm_subway_cache:
        query = (
            f'[out:json][timeout:30];'
            f'relation[type=route][route=subway][ref="{ref}"]'
            f'({min_lat},{min_lng},{max_lat},{max_lng});'
            f'way(r);out geom;'
        )
        try:
            resp = await client.get(
                "https://overpass-api.de/api/interpreter",
                params={"data": query},
                headers={"User-Agent": "MeetMidApp/1.0"},
                timeout=30.0,
            )
            resp.raise_for_status()
            elems = resp.json().get("elements", [])
            _osm_subway_cache[cache_key] = _assemble_osm_ways(elems)
            print(f"[SubwayOSM] ref={ref} bbox={min_lat},{min_lng}~{max_lat},{max_lng}: {len(elems)}개 way → {len(_osm_subway_cache[cache_key])}개 경로")
        except Exception as e:
            print(f"[SubwayOSM] {e}")
            _osm_subway_cache[cache_key] = []

    return _osm_subway_cache[cache_key]


async def _subway_polyline_from_cache(
    client: httpx.AsyncClient,
    stations: list,
    subway_code: int,
) -> list:
    """
    파일 캐시 우선 조회 → miss 시 OSM Overpass 호출 후 캐시 저장.
    반환: [[lng, lat], ...]
    """
    if len(stations) < 2:
        return [[float(s["x"]), float(s["y"])] for s in stations]

    # 파일 캐시에 없는 쌍 확인
    missing = any(
        _lookup_pair(subway_code, s["stationID"], stations[i + 1]["stationID"]) is None
        for i, s in enumerate(stations[:-1])
        if s.get("stationID") and stations[i + 1].get("stationID")
    )

    if missing:
        all_paths = await _fetch_osm_paths(client, subway_code, stations)
        cache_dirty = False
        if all_paths:
            for si in range(len(stations) - 1):
                st0, st1 = stations[si], stations[si + 1]
                id0, id1 = st0.get("stationID", 0), st1.get("stationID", 0)
                if not id0 or not id1:
                    continue
                if _lookup_pair(subway_code, id0, id1) is not None:
                    continue
                seg = slice_lane_coords(
                    all_paths,
                    float(st0["x"]), float(st0["y"]),
                    float(st1["x"]), float(st1["y"]),
                    st0.get("stationName", ""), st1.get("stationName", ""),
                )
                if seg is not None:
                    _store_pair(subway_code, id0, id1, seg)
                    cache_dirty = True
        if cache_dirty:
            _save_subway_file_cache()

    # 파일 캐시에서 조립
    result_coords: list = []
    for si in range(len(stations) - 1):
        st0, st1 = stations[si], stations[si + 1]
        id0, id1 = st0.get("stationID", 0), st1.get("stationID", 0)
        s0_lng, s0_lat = float(st0["x"]), float(st0["y"])
        s1_lng, s1_lat = float(st1["x"]), float(st1["y"])

        seg = _lookup_pair(subway_code, id0, id1) if (id0 and id1) else None
        if seg:
            result_coords.extend(seg[1:] if result_coords else seg)
        else:
            if not result_coords:
                result_coords.append([s0_lng, s0_lat])
            result_coords.append([s1_lng, s1_lat])

    if len(result_coords) < 2:
        return [[float(s["x"]), float(s["y"])] for s in stations]
    return result_coords


async def _car_polyline(client: httpx.AsyncClient,
                        src_lat, src_lng, dst_lat, dst_lng) -> list:
    """카카오 모빌리티 추천 경로 좌표. 반환: [[lng, lat], ...]"""
    kakao_key = os.getenv("KAKAO_API_KEY")
    if not kakao_key:
        return []
    try:
        resp = await client.get(
            "https://apis-navi.kakaomobility.com/v1/directions",
            params={
                "origin": f"{src_lng},{src_lat}",
                "destination": f"{dst_lng},{dst_lat}",
                "priority": "RECOMMEND",
            },
            headers={"Authorization": f"KakaoAK {kakao_key}"},
            timeout=10.0,
        )
        resp.raise_for_status()
        routes = resp.json().get("routes", [])
        if not routes:
            return []
        coords = []
        for section in routes[0].get("sections", []):
            for road in section.get("roads", []):
                verts = road.get("vertexes", [])
                for i in range(0, len(verts) - 1, 2):
                    coords.append([verts[i], verts[i + 1]])  # [lng, lat]
        return coords
    except Exception as e:
        print(f"[CarPolyline] {e}")
        return []


async def _transit_polyline(client: httpx.AsyncClient,
                            src_lat, src_lng, dst_lat, dst_lng) -> list:
    """대중교통 경로 polyline (하이브리드):
    - 지하철(1): OSM Overpass 실노선 geometry (역별 매칭, fallback: 역좌표 직선)
    - 버스(2):   첫/마지막 정류장 사이를 _car_polyline으로 실도로 표시
    - 도보(3):   역/정류장 좌표 순서 연결
    반환: [[lng, lat], ...]
    """
    odsay_key = os.getenv("ODSAY_API_KEY")
    if not odsay_key:
        return []
    try:
        resp = await client.get(
            "https://api.odsay.com/v1/api/searchPubTransPathT",
            params={"apiKey": odsay_key,
                    "SX": src_lng, "SY": src_lat,
                    "EX": dst_lng, "EY": dst_lat},
            timeout=10.0,
        )
        resp.raise_for_status()
        result = resp.json().get("result")
        if not result:
            return []
        paths = result.get("path", [])
        if not paths:
            return []

        sub_paths = paths[0].get("subPath", [])

        # 버스(2)/지하철(1) 구간 병렬 처리
        async_indices: list = []
        async_coros: list = []
        for i, sub in enumerate(sub_paths):
            stations = sub.get("passStopList", {}).get("stations", [])
            tt = sub.get("trafficType")
            if tt == 2 and len(stations) >= 2:  # 버스: 카카오 실도로
                s_lat = float(stations[0]["y"]);  s_lng = float(stations[0]["x"])
                e_lat = float(stations[-1]["y"]); e_lng = float(stations[-1]["x"])
                async_indices.append((i, "bus"))
                async_coros.append(_car_polyline(client, s_lat, s_lng, e_lat, e_lng))
            elif tt == 1 and len(stations) >= 2:  # 지하철: OSM 실노선
                subway_code = sub.get("lane", [{}])[0].get("subwayCode", 0)
                async_indices.append((i, "subway"))
                async_coros.append(_subway_polyline_from_cache(client, stations, subway_code))

        async_results = await asyncio.gather(*async_coros)
        result_map = {idx: res for (idx, _), res in zip(async_indices, async_results)}

        all_coords = []
        for i, sub in enumerate(sub_paths):
            traffic_type = sub.get("trafficType")
            stations = sub.get("passStopList", {}).get("stations", [])

            if traffic_type in (1, 2):
                coords = result_map.get(i, [])
                if coords:
                    all_coords.extend(coords)
                    continue
                # fallback: 역/정류장 좌표 직선

            # 도보·fallback: 역/정류장 좌표 순서 연결
            for station in stations:
                x, y = station.get("x"), station.get("y")
                if x is not None and y is not None:
                    all_coords.append([float(x), float(y)])

        return all_coords
    except Exception as e:
        print(f"[TransitPolyline] {e}")
        return []


async def _member_polyline(client: httpx.AsyncClient,
                           member: dict, dst_lat: float, dst_lng: float) -> dict:
    """멤버 출발지 → 중간지점 경로 좌표. API 실패 시 직선 fallback."""
    transport = member.get("transport", "transit")
    src_lat, src_lng = member["lat"], member["lng"]
    if transport == "car":
        coords = await _car_polyline(client, src_lat, src_lng, dst_lat, dst_lng)
    elif transport == "transit":
        coords = await _transit_polyline(client, src_lat, src_lng, dst_lat, dst_lng)
    else:  # walk
        coords = [[src_lng, src_lat], [dst_lng, dst_lat]]
    if not coords:  # API 실패 fallback
        coords = [[src_lng, src_lat], [dst_lng, dst_lat]]
    return {"name": member["name"], "transport": transport, "coords": coords}


# 하위 호환 wrapper
async def _get_transit_minutes(client, src_lat, src_lng, dst_lat, dst_lng):
    t, _ = await _get_transit_metrics(client, src_lat, src_lng, dst_lat, dst_lng)
    return t


async def _get_car_minutes(client, src_lat, src_lng, dst_lat, dst_lng):
    t, _ = await _get_car_metrics(client, src_lat, src_lng, dst_lat, dst_lng)
    return t


async def _route_km(client: httpx.AsyncClient, src_lat, src_lng, dst_lat, dst_lng, transport) -> float:
    """교통수단별 실제 이동거리(km). API 실패 시 Haversine × 우회계수."""
    if transport == "transit":
        _, d = await _get_transit_metrics(client, src_lat, src_lng, dst_lat, dst_lng)
        if d is not None:
            return d
    elif transport == "car":
        _, d = await _get_car_metrics(client, src_lat, src_lng, dst_lat, dst_lng)
        if d is not None:
            return d
    # 도보 또는 API 실패: 직선 × 우회계수 (도보 1.3 / 그외 1.2)
    detour = 1.3 if transport == "walk" else 1.2
    return _haversine_km(src_lat, src_lng, dst_lat, dst_lng) * detour


async def _travel_minutes(client: httpx.AsyncClient, src_lat, src_lng, dst_lat, dst_lng, transport):
    if transport == "transit":
        t = await _get_transit_minutes(client, src_lat, src_lng, dst_lat, dst_lng)
        if t is not None:
            return t
    elif transport == "car":
        t = await _get_car_minutes(client, src_lat, src_lng, dst_lat, dst_lng)
        if t is not None:
            return t
    distance_km = _haversine_km(src_lat, src_lng, dst_lat, dst_lng)
    speed_kmh = {"car": 30, "transit": 20, "walk": 4}.get(transport, 20)
    return max(1, round((distance_km / speed_kmh) * 60))


async def _find_nearby_landmark(client: httpx.AsyncClient, lat: float, lng: float) -> dict | None:
    kakao_key = os.getenv("KAKAO_API_KEY")
    if not kakao_key:
        return None

    async def _fetch_category(code, radius):
        try:
            resp = await client.get(
                "https://dapi.kakao.com/v2/local/search/category.json",
                params={"category_group_code": code, "x": lng, "y": lat,
                        "radius": radius, "sort": "distance", "size": 1},
                headers={"Authorization": f"KakaoAK {kakao_key}"},
                timeout=5.0,
            )
            docs = resp.json().get("documents", [])
            if docs:
                doc = docs[0]
                return {
                    "name": doc["place_name"],
                    "lat": float(doc["y"]),
                    "lng": float(doc["x"]),
                }
            return None
        except Exception as e:
            print(f"[Landmark] {code} 오류: {e}")
            return None

    # 1단계: 3개 카테고리 병렬 검색
    targets = [("SW8", 1000), ("AT4", 800), ("SC4", 600)]
    results = await asyncio.gather(*[_fetch_category(code, radius) for code, radius in targets])
    result = next((r for r in results if r), None)
    if result:
        return result

    # 2단계: 지하철역 2000m fallback
    result = await _fetch_category("SW8", 2000)
    if result:
        print(f"[Landmark] 반경 2000m 확장: {result['name']}")
        return result

    # 3단계: 지하철역 5000m fallback
    result = await _fetch_category("SW8", 5000)
    if result:
        print(f"[Landmark] 반경 5000m 확장: {result['name']}")
        return result

    print("[Landmark] 5000m 내 랜드마크 없음")
    return None


async def geocode_address(client: httpx.AsyncClient, address: str):
    try:
        address = address.encode("latin-1").decode("cp949")
    except (UnicodeEncodeError, UnicodeDecodeError):
        pass
    kakao_key = os.getenv("KAKAO_API_KEY")
    if not kakao_key:
        return None
    headers = {"Authorization": f"KakaoAK {kakao_key}"}
    try:
        resp = await client.get(
            "https://dapi.kakao.com/v2/local/search/address.json",
            params={"query": address},
            headers=headers,
            timeout=5.0,
        )
        resp.raise_for_status()
        docs = resp.json().get("documents", [])
        if docs:
            return float(docs[0]["y"]), float(docs[0]["x"])
        resp = await client.get(
            "https://dapi.kakao.com/v2/local/search/keyword.json",
            params={"query": address, "size": 1},
            headers=headers,
            timeout=5.0,
        )
        resp.raise_for_status()
        docs = resp.json().get("documents", [])
        if docs:
            return float(docs[0]["y"]), float(docs[0]["x"])
        return None
    except Exception:
        return None


async def _route_distance_fair_midpoint(
    client: httpx.AsyncClient, members: list, max_iter: int = 6
) -> tuple:
    """거리 공평 (실경로): 각 멤버의 교통수단별 실제 도로/대중교통 거리(km) max를 최소화.
    구조는 시간 공평과 동일 (1-Center heuristic), 측정값만 거리.
    반환: (lat, lng, {name: distance_km})
    """
    n = len(members)
    cx = sum(m["lat"] for m in members) / n
    cy = sum(m["lng"] for m in members) / n
    dist_map = {}
    step = 0.4

    for it in range(max_iter):
        # 멤버별 실제 경로 거리 병렬 측정
        dists = await asyncio.gather(*[
            _route_km(client, m["lat"], m["lng"], cx, cy, m["transport"])
            for m in members
        ])
        dist_map = {m["name"]: d for m, d in zip(members, dists)}

        slowest = None
        slowest_d = -1.0
        fastest_d = float("inf")
        for m, d in zip(members, dists):
            if d > slowest_d:
                slowest_d = d
                slowest = m
            if d < fastest_d:
                fastest_d = d

        # 수렴 조건: 최대-최소 차가 1km 이내 또는 마지막 반복
        if slowest is None or slowest_d - fastest_d <= 1.0 or it == max_iter - 1:
            break

        cx += (slowest["lat"] - cx) * step
        cy += (slowest["lng"] - cy) * step
        step *= 0.7

    return cx, cy, dist_map


async def _time_fair_midpoint(client: httpx.AsyncClient, members: list, max_iter: int = 6) -> tuple:
    n = len(members)
    cx = sum(m["lat"] for m in members) / n
    cy = sum(m["lng"] for m in members) / n
    time_map = {}
    step = 0.4

    for it in range(max_iter):
        # 모든 멤버 이동시간 병렬 계산
        times = await asyncio.gather(*[
            _travel_minutes(client, m["lat"], m["lng"], cx, cy, m["transport"])
            for m in members
        ])
        time_map = {m["name"]: t for m, t in zip(members, times)}

        slowest = None
        slowest_t = -1
        fastest_t = float("inf")
        for m, t in zip(members, times):
            if t > slowest_t:
                slowest_t = t
                slowest = m
            if t < fastest_t:
                fastest_t = t

        if slowest is None or slowest_t - fastest_t <= 2 or it == max_iter - 1:
            break

        cx += (slowest["lat"] - cx) * step
        cy += (slowest["lng"] - cy) * step
        step *= 0.7

    return cx, cy, time_map


# ── Supabase REST 헬퍼 (비동기) ───────────────────────────────────

_supabase_url = os.getenv("SUPABASE_URL", "")
_supabase_service_key = os.getenv("SUPABASE_SERVICE_KEY", os.getenv("SUPABASE_KEY", ""))
_SB_REST = f"{_supabase_url}/rest/v1"
_SB_HEADERS = {
    "apikey": _supabase_service_key,
    "Authorization": f"Bearer {_supabase_service_key}",
    "Content-Type": "application/json",
    "Prefer": "return=representation",
}


async def sb_select(client: httpx.AsyncClient, table: str, select: str = "*",
                    limit: int = None, filters: dict = None) -> list:
    params = {"select": select}
    if filters:
        for k, v in filters.items():
            params[k] = f"eq.{v}"
    if limit:
        params["limit"] = str(limit)
    r = await client.get(f"{_SB_REST}/{table}", params=params, headers=_SB_HEADERS)
    r.raise_for_status()
    return r.json()


async def sb_insert(client: httpx.AsyncClient, table: str, data: dict) -> list:
    r = await client.post(f"{_SB_REST}/{table}", json=data, headers=_SB_HEADERS)
    r.raise_for_status()
    return r.json()


async def sb_update(client: httpx.AsyncClient, table: str, data: dict, filters: dict) -> list:
    params = {k: f"eq.{v}" for k, v in filters.items()}
    r = await client.patch(f"{_SB_REST}/{table}", params=params, json=data, headers=_SB_HEADERS)
    r.raise_for_status()
    return r.json()


async def sb_delete(client: httpx.AsyncClient, table: str, filters: dict) -> None:
    params = {k: f"eq.{v}" for k, v in filters.items()}
    r = await client.delete(f"{_SB_REST}/{table}", params=params, headers=_SB_HEADERS)
    r.raise_for_status()


async def sb_select_in(client: httpx.AsyncClient, table: str, in_col: str,
                       in_values: list, select: str = "*") -> list:
    """PostgREST IN 필터: 괄호 URL 인코딩 방지를 위해 URL 수동 구성"""
    if not in_values:
        return []
    values_str = ",".join(str(v) for v in in_values)
    url = f"{_SB_REST}/{table}?select={select}&{in_col}=in.({values_str})"
    r = await client.get(url, headers=_SB_HEADERS)
    r.raise_for_status()
    return r.json()


# ── 내부 헬퍼 ────────────────────────────────────────────────────

def _hash_pw(password: str) -> str:
    return hashlib.sha256(password.encode()).hexdigest()


def _mask_username(username: str) -> str:
    n = len(username)
    if n <= 2:
        return username[0] + "*" * (n - 1)
    show = min(3, max(2, n // 3))
    return username[:show] + "*" * (n - show)


async def _get_or_create_guest_user(client: httpx.AsyncClient, name: str) -> dict | None:
    try:
        rows = await sb_select(client, "users", filters={"name": name}, limit=1)
        if rows:
            return rows[0]
        suffix = uuid.uuid4().hex[:6]
        guest_username = f"guest_{name.replace(' ', '_')}_{suffix}"
        guest_email = f"{guest_username}@guest.local"
        inserted = await sb_insert(client, "users", {
            "name": name,
            "username": guest_username,
            "email": guest_email,
            "password": _hash_pw(uuid.uuid4().hex),
        })
        return inserted[0] if inserted else None
    except Exception as e:
        print(f"[ERROR] _get_or_create_guest_user: {e}")
        return None


async def _get_members(client: httpx.AsyncClient, room_id: str) -> list:
    return await sb_select(client, "members", filters={"room_id": room_id})


def _format_member(m: dict) -> dict:
    return {
        "name": m["name"],
        "address": m["address"],
        "transport": m["transport"],
        "is_direct_added": m.get("is_direct_added", False),
    }


# ── Pydantic 요청 모델 ────────────────────────────────────────────

class RegisterRequest(BaseModel):
    name: str
    username: str
    email: str
    password: str

class LoginRequest(BaseModel):
    username: str
    password: str

class FindUsernameRequest(BaseModel):
    name: str
    email: str

class FindPwVerifyRequest(BaseModel):
    username: str
    email: str

class ResetPasswordRequest(BaseModel):
    username: str
    email: str
    new_password: str

class CreateRoomRequest(BaseModel):
    room_name: str
    host_name: str = ""
    host_uuid: str = ""

class JoinRoomRequest(BaseModel):
    name: str
    address: str = ""
    transport: str = "transit"
    user_uuid: str = ""
    is_direct_added: bool = False

class UpdateMemberRequest(BaseModel):
    requester_name: str
    old_name: str
    new_name: str = ""
    address: str = ""
    transport: str = "transit"

class KickMemberRequest(BaseModel):
    requester_name: str
    target_name: str

class TransferHostRequest(BaseModel):
    requester_name: str
    new_host_name: str

class LeaveRoomRequest(BaseModel):
    user_name: str

class UpdateLocationRequest(BaseModel):
    member_name: str
    lat: float | None = None
    lng: float | None = None
    shared: bool = True


# ── FastAPI 앱 ────────────────────────────────────────────────────

@asynccontextmanager
async def lifespan(app: FastAPI):
    _load_subway_file_cache()
    async with httpx.AsyncClient(timeout=httpx.Timeout(10.0)) as client:
        app.state.client = client
        yield

app = FastAPI(lifespan=lifespan)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


def _client(request: Request) -> httpx.AsyncClient:
    return request.app.state.client


# ── 지오코딩 ─────────────────────────────────────────────────────

@app.get("/geocode")
async def geocode_endpoint(request: Request, address: str = Query(...)):
    address = address.strip()
    if not address:
        raise HTTPException(status_code=400, detail="address가 필요합니다.")
    coords = await geocode_address(_client(request), address)
    if coords:
        return {"lat": coords[0], "lng": coords[1]}
    raise HTTPException(status_code=404, detail="주소를 찾을 수 없습니다.")


@app.get("/reverse-geocode")
async def reverse_geocode(request: Request, lat: str = Query(""), lng: str = Query("")):
    lat, lng = lat.strip(), lng.strip()
    if not lat or not lng:
        raise HTTPException(status_code=400, detail="lat, lng가 필요합니다.")
    kakao_key = os.getenv("KAKAO_API_KEY")
    if not kakao_key:
        return {"address": ""}
    try:
        resp = await _client(request).get(
            "https://dapi.kakao.com/v2/local/geo/coord2address.json",
            params={"x": lng, "y": lat},
            headers={"Authorization": f"KakaoAK {kakao_key}"},
            timeout=5.0,
        )
        resp.raise_for_status()
        docs = resp.json().get("documents", [])
        if docs:
            road = docs[0].get("road_address") or {}
            addr = docs[0].get("address") or {}
            return {"address": road.get("address_name") or addr.get("address_name", "")}
        return {"address": ""}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/places/search")
async def search_places(request: Request, query: str = Query("")):
    query = query.strip()
    if not query:
        return {"places": []}
    kakao_key = os.getenv("KAKAO_API_KEY")
    if not kakao_key:
        return {"places": []}
    try:
        resp = await _client(request).get(
            "https://dapi.kakao.com/v2/local/search/keyword.json",
            params={"query": query, "size": 10},
            headers={"Authorization": f"KakaoAK {kakao_key}"},
            timeout=5.0,
        )
        resp.raise_for_status()
        docs = resp.json().get("documents", [])
        return {"places": [
            {"name": d.get("place_name", ""),
             "address": d.get("road_address_name") or d.get("address_name", "")}
            for d in docs
        ]}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# ── 인증 ─────────────────────────────────────────────────────────

@app.get("/auth/check-username/{username}")
async def check_username(request: Request, username: str):
    rows = await sb_select(_client(request), "users", select="id", filters={"username": username}, limit=1)
    return {"available": len(rows) == 0}


@app.get("/auth/check-email")
async def check_email(request: Request, email: str = Query("")):
    email = email.strip()
    if not email:
        raise HTTPException(status_code=400, detail="email이 필요합니다.")
    rows = await sb_select(_client(request), "users", select="id", filters={"email": email}, limit=1)
    return {"available": len(rows) == 0}


@app.post("/auth/register", status_code=201)
async def register(request: Request, data: RegisterRequest):
    name, username, email, password = (
        data.name.strip(), data.username.strip(),
        data.email.strip(), data.password.strip(),
    )
    if not all([name, username, email, password]):
        raise HTTPException(status_code=400, detail="name, username, email, password가 필요합니다.")
    client = _client(request)
    try:
        if await sb_select(client, "users", select="id", filters={"username": username}, limit=1):
            raise HTTPException(status_code=409, detail="이미 사용 중인 아이디입니다.")
        if await sb_select(client, "users", select="id", filters={"email": email}, limit=1):
            raise HTTPException(status_code=409, detail="이미 사용 중인 이메일입니다.")
        inserted = await sb_insert(client, "users", {
            "name": name, "username": username,
            "email": email, "password": _hash_pw(password),
        })
        if not inserted:
            raise HTTPException(status_code=500, detail="회원가입 실패")
        user = inserted[0]
        return {"ok": True, "user": {
            "id": user["id"], "name": user["name"],
            "username": user["username"], "email": user["email"],
        }}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/auth/login")
async def login(request: Request, data: LoginRequest):
    username, password = data.username.strip(), data.password.strip()
    if not username or not password:
        raise HTTPException(status_code=400, detail="username과 password가 필요합니다.")
    try:
        rows = await sb_select(_client(request), "users",
                               filters={"username": username, "password": _hash_pw(password)}, limit=1)
        if not rows:
            raise HTTPException(status_code=401, detail="아이디 또는 비밀번호가 올바르지 않습니다.")
        user = rows[0]
        return {"ok": True, "user": {
            "id": user["id"], "name": user["name"],
            "username": user["username"], "email": user["email"],
        }}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/auth/find-username")
async def find_username(request: Request, data: FindUsernameRequest):
    name, email = data.name.strip(), data.email.strip()
    if not name or not email:
        raise HTTPException(status_code=400, detail="name과 email이 필요합니다.")
    try:
        rows = await sb_select(_client(request), "users", select="username",
                               filters={"name": name, "email": email}, limit=1)
        if not rows:
            raise HTTPException(status_code=404, detail="일치하는 계정이 없습니다.")
        return {"username": _mask_username(rows[0]["username"])}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/auth/find-pw/verify")
async def find_pw_verify(request: Request, data: FindPwVerifyRequest):
    username, email = data.username.strip(), data.email.strip()
    if not username or not email:
        raise HTTPException(status_code=400, detail="username과 email이 필요합니다.")
    try:
        rows = await sb_select(_client(request), "users", select="id",
                               filters={"username": username, "email": email}, limit=1)
        if not rows:
            raise HTTPException(status_code=404, detail="아이디 또는 이메일이 올바르지 않습니다.")
        return {"ok": True}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/auth/reset-password")
async def reset_password(request: Request, data: ResetPasswordRequest):
    username, email, new_password = (
        data.username.strip(), data.email.strip(), data.new_password.strip()
    )
    if not all([username, email, new_password]):
        raise HTTPException(status_code=400, detail="username, email, new_password가 필요합니다.")
    client = _client(request)
    try:
        rows = await sb_select(client, "users", select="id",
                               filters={"username": username, "email": email}, limit=1)
        if not rows:
            raise HTTPException(status_code=404, detail="아이디 또는 이메일이 올바르지 않습니다.")
        await sb_update(client, "users", {"password": _hash_pw(new_password)}, filters={"id": rows[0]["id"]})
        return {"ok": True}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# ── 방 목록 ───────────────────────────────────────────────────────

@app.get("/rooms")
async def get_rooms(request: Request, user_id: str = Query("")):
    client = _client(request)
    try:
        user_id = user_id.strip()
        if user_id:
            member_rows = await sb_select(client, "members", select="room_id", filters={"user_id": user_id})
            room_ids = list({m["room_id"] for m in member_rows})
            if not room_ids:
                return {"rooms": []}
            rooms = await sb_select_in(client, "rooms", "id", room_ids,
                                       select="id,room_name,host_id,created_at")
        else:
            rooms = await sb_select(client, "rooms", select="id,room_name,host_id,created_at")

        result = []
        for room in rooms:
            members = await _get_members(client, room["id"])
            host_name = ""
            try:
                u = await sb_select(client, "users", select="name",
                                    filters={"id": room["host_id"]}, limit=1)
                if u:
                    host_name = u[0]["name"]
            except Exception:
                pass
            result.append({
                "room_id": room["id"],
                "room_name": room["room_name"],
                "host_id": host_name,
                "host_uuid": room["host_id"],
                "members": [_format_member(m) for m in members],
            })
        return {"rooms": result}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/rooms/all")
async def get_rooms_all(request: Request, user_id: str = Query(""), search: str = Query("")):
    client = _client(request)
    try:
        user_id, search = user_id.strip(), search.strip().lower()
        rooms = await sb_select(client, "rooms", select="id,room_name,host_id,created_at")

        if user_id:
            member_rows = await sb_select(client, "members", select="room_id",
                                          filters={"user_id": user_id})
            my_room_ids = {m["room_id"] for m in member_rows}
            rooms = [r for r in rooms if r["id"] not in my_room_ids]

        if search:
            rooms = [r for r in rooms if search in r["room_name"].lower()]

        result = []
        for room in rooms:
            members = await _get_members(client, room["id"])
            result.append({
                "room_id": room["id"],
                "room_name": room["room_name"],
                "member_count": len(members),
                "member_names": [m["name"] for m in members],
            })
        return {"rooms": result}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# ── 방 만들기 ─────────────────────────────────────────────────────

@app.post("/room")
async def create_room(request: Request, data: CreateRoomRequest):
    room_name = data.room_name.strip()
    host_name = data.host_name.strip()
    host_uuid = data.host_uuid.strip()

    if not room_name:
        raise HTTPException(status_code=400, detail="room_name이 필요합니다.")
    if not host_name and not host_uuid:
        raise HTTPException(status_code=400, detail="host_name 또는 host_uuid가 필요합니다.")

    client = _client(request)
    try:
        if host_uuid:
            u = await sb_select(client, "users", select="id,name",
                                filters={"id": host_uuid}, limit=1)
            if not u:
                raise HTTPException(status_code=404, detail="존재하지 않는 사용자입니다.")
            host = u[0]
        else:
            host = await _get_or_create_guest_user(client, host_name)
            if not host:
                raise HTTPException(status_code=500, detail="사용자 처리 실패")

        room_res = await sb_insert(client, "rooms", {"room_name": room_name, "host_id": host["id"]})
        if not room_res:
            raise HTTPException(status_code=500, detail="방 생성 실패")
        room = room_res[0]

        await sb_insert(client, "members", {
            "room_id": room["id"], "user_id": host["id"],
            "name": host["name"], "address": "", "transport": "transit",
        })

        members = await _get_members(client, room["id"])
        return {
            "room_id": room["id"],
            "room_name": room["room_name"],
            "host_id": host["name"],
            "host_uuid": host["id"],
            "members": [_format_member(m) for m in members],
        }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# ── 방 참여 ───────────────────────────────────────────────────────

@app.post("/room/{room_id}/join")
async def join_room(room_id: str, request: Request):
    # cp949 인코딩 폴백을 위해 raw body 직접 처리
    raw = await request.body()
    try:
        data = json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError):
        try:
            data = json.loads(raw.decode("cp949"))
        except Exception:
            data = {}

    name = data.get("name", "").strip()
    address = data.get("address", "").strip()
    transport = data.get("transport", "transit")
    user_uuid = data.get("user_uuid", "").strip()
    is_direct_added = bool(data.get("is_direct_added", False))

    if not name:
        raise HTTPException(status_code=400, detail="name이 필요합니다.")

    client = _client(request)
    try:
        if not await sb_select(client, "rooms", select="id", filters={"id": room_id}, limit=1):
            raise HTTPException(status_code=404, detail="존재하지 않는 방입니다.")

        resolved_user_id = None
        if user_uuid:
            resolved_user_id = user_uuid
        else:
            guest = await _get_or_create_guest_user(client, name)
            if guest:
                resolved_user_id = guest["id"]

        existing = await sb_select(client, "members", select="id",
                                   filters={"room_id": room_id, "name": name}, limit=1)
        if existing:
            await sb_update(client, "members",
                            {"address": address, "transport": transport},
                            filters={"id": existing[0]["id"]})
        else:
            member_data = {
                "room_id": room_id, "user_id": resolved_user_id,
                "name": name, "address": address, "transport": transport,
            }
            if is_direct_added:
                try:
                    await sb_insert(client, "members", {**member_data, "is_direct_added": True})
                except Exception:
                    await sb_insert(client, "members", member_data)
            else:
                await sb_insert(client, "members", member_data)

        members = await _get_members(client, room_id)
        return {"ok": True, "members": [_format_member(m) for m in members]}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# ── 멤버 정보 변경 ────────────────────────────────────────────────

@app.put("/room/{room_id}/member")
async def update_member(room_id: str, request: Request, data: UpdateMemberRequest):
    requester_name = data.requester_name.strip()
    old_name = data.old_name.strip()
    new_name = data.new_name.strip() or old_name
    address = data.address.strip()

    if not old_name:
        raise HTTPException(status_code=400, detail="old_name이 필요합니다.")

    client = _client(request)
    try:
        room_res = await sb_select(client, "rooms", select="host_id",
                                   filters={"id": room_id}, limit=1)
        if not room_res:
            raise HTTPException(status_code=404, detail="존재하지 않는 방입니다.")

        host_user = await sb_select(client, "users", select="name",
                                    filters={"id": room_res[0]["host_id"]}, limit=1)
        if (host_user[0]["name"] if host_user else "") != requester_name:
            raise HTTPException(status_code=403, detail="방장만 정보를 변경할 수 있습니다.")

        member_res = await sb_select(client, "members", select="id",
                                     filters={"room_id": room_id, "name": old_name}, limit=1)
        if not member_res:
            raise HTTPException(status_code=404, detail="해당 멤버가 없습니다.")

        await sb_update(client, "members",
                        {"name": new_name, "address": address, "transport": data.transport},
                        filters={"id": member_res[0]["id"]})

        members = await _get_members(client, room_id)
        return {"ok": True, "members": [_format_member(m) for m in members]}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# ── 강퇴 ─────────────────────────────────────────────────────────

@app.post("/room/{room_id}/kick")
async def kick_member(room_id: str, request: Request, data: KickMemberRequest):
    requester_name = data.requester_name.strip()
    target_name = data.target_name.strip()

    if not requester_name or not target_name:
        raise HTTPException(status_code=400, detail="requester_name과 target_name이 필요합니다.")

    client = _client(request)
    try:
        room_res = await sb_select(client, "rooms", select="host_id",
                                   filters={"id": room_id}, limit=1)
        if not room_res:
            raise HTTPException(status_code=404, detail="존재하지 않는 방입니다.")

        host_user = await sb_select(client, "users", select="name",
                                    filters={"id": room_res[0]["host_id"]}, limit=1)
        if (host_user[0]["name"] if host_user else "") != requester_name:
            raise HTTPException(status_code=403, detail="방장만 강퇴할 수 있습니다.")

        target_res = await sb_select(client, "members", select="id",
                                     filters={"room_id": room_id, "name": target_name}, limit=1)
        if not target_res:
            raise HTTPException(status_code=404, detail="해당 멤버가 없습니다.")

        await sb_delete(client, "members", filters={"id": target_res[0]["id"]})
        members = await _get_members(client, room_id)
        return {"ok": True, "members": [_format_member(m) for m in members]}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# ── 방장 양도 ─────────────────────────────────────────────────────

@app.post("/room/{room_id}/transfer-host")
async def transfer_host(room_id: str, request: Request, data: TransferHostRequest):
    requester_name = data.requester_name.strip()
    new_host_name = data.new_host_name.strip()

    if not requester_name or not new_host_name:
        raise HTTPException(status_code=400, detail="requester_name과 new_host_name이 필요합니다.")

    client = _client(request)
    try:
        room_res = await sb_select(client, "rooms", select="host_id",
                                   filters={"id": room_id}, limit=1)
        if not room_res:
            raise HTTPException(status_code=404, detail="존재하지 않는 방입니다.")

        host_user = await sb_select(client, "users", select="name",
                                    filters={"id": room_res[0]["host_id"]}, limit=1)
        if (host_user[0]["name"] if host_user else "") != requester_name:
            raise HTTPException(status_code=403, detail="방장만 권한을 양도할 수 있습니다.")

        new_host_member = await sb_select(client, "members", select="user_id,name",
                                          filters={"room_id": room_id, "name": new_host_name}, limit=1)
        if not new_host_member:
            raise HTTPException(status_code=404, detail="해당 멤버가 없습니다.")

        new_host_user_id = new_host_member[0]["user_id"]
        if not new_host_user_id:
            guest = await _get_or_create_guest_user(client, new_host_name)
            new_host_user_id = guest["id"] if guest else None

        if not new_host_user_id:
            raise HTTPException(status_code=500, detail="새 방장의 사용자 정보를 찾을 수 없습니다.")

        await sb_update(client, "rooms", {"host_id": new_host_user_id}, filters={"id": room_id})
        members = await _get_members(client, room_id)
        return {
            "ok": True,
            "host_id": new_host_name,
            "host_uuid": new_host_user_id,
            "members": [_format_member(m) for m in members],
        }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# ── 방 나가기 ─────────────────────────────────────────────────────

@app.post("/room/{room_id}/leave")
async def leave_room(room_id: str, request: Request, data: LeaveRoomRequest):
    user_name = data.user_name.strip()

    if not user_name:
        raise HTTPException(status_code=400, detail="user_name이 필요합니다.")

    client = _client(request)
    try:
        room_res = await sb_select(client, "rooms", select="id,host_id",
                                   filters={"id": room_id}, limit=1)
        if not room_res:
            raise HTTPException(status_code=404, detail="존재하지 않는 방입니다.")

        host_uuid = room_res[0]["host_id"]
        leaving_member = await sb_select(client, "members", select="id,user_id,name",
                                         filters={"room_id": room_id, "name": user_name}, limit=1)
        if not leaving_member:
            raise HTTPException(status_code=404, detail="해당 멤버가 없습니다.")

        await sb_delete(client, "members", filters={"id": leaving_member[0]["id"]})
        remaining = await _get_members(client, room_id)

        if not remaining:
            await sb_delete(client, "rooms", filters={"id": room_id})
            return {"ok": True, "room_deleted": True}

        host_user = await sb_select(client, "users", select="name",
                                    filters={"id": host_uuid}, limit=1)
        host_name = host_user[0]["name"] if host_user else ""
        new_host_name = host_name

        if host_name == user_name:
            new_host = remaining[0]
            new_host_user_id = new_host.get("user_id")
            if not new_host_user_id:
                guest = await _get_or_create_guest_user(client, new_host["name"])
                new_host_user_id = guest["id"] if guest else None
            if new_host_user_id:
                await sb_update(client, "rooms", {"host_id": new_host_user_id},
                                filters={"id": room_id})
                new_host_name = new_host["name"]

        return {
            "ok": True,
            "room_deleted": False,
            "host_id": new_host_name,
            "members": [_format_member(m) for m in remaining],
        }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# ── 중간지점 ──────────────────────────────────────────────────────

@app.get("/midpoint/{room_id}")
async def get_midpoint(room_id: str, request: Request,
                       criteria: str = Query("distanceFair"),
                       polyline: bool = Query(False)):
    client = _client(request)
    try:
        if not await sb_select(client, "rooms", select="id", filters={"id": room_id}, limit=1):
            raise HTTPException(status_code=404, detail="존재하지 않는 방입니다.")

        members = await _get_members(client, room_id)
        if not members:
            raise HTTPException(status_code=400, detail="멤버가 없습니다.")

        # 주소가 있는 멤버 전체 지오코딩 병렬 처리
        members_with_addr = [m for m in members if m["address"]]
        coords_list = await asyncio.gather(*[
            geocode_address(client, m["address"]) for m in members_with_addr
        ])
        located = [
            {**m, "lat": coords[0], "lng": coords[1]}
            for m, coords in zip(members_with_addr, coords_list)
            if coords is not None
        ]

        if not located:
            raise HTTPException(status_code=400, detail="좌표를 확인할 수 있는 멤버가 없습니다.")

        time_map = {}
        if criteria == "timeFair" and len(located) >= 2:
            mid_lat, mid_lng, time_map = await _time_fair_midpoint(client, located)
        elif criteria == "distanceFair" and len(located) >= 2:
            mid_lat, mid_lng, _ = await _route_distance_fair_midpoint(client, located)
        elif criteria in ("majority", "transitFocused") and len(located) >= 2:
            mid_lat, mid_lng = await _majority_midpoint(client, located)
        else:
            mid_lat = sum(m["lat"] for m in located) / len(located)
            mid_lng = sum(m["lng"] for m in located) / len(located)

        # 랜드마크 검색 → 찾으면 좌표를 중간지점으로 스냅
        landmark = await _find_nearby_landmark(client, mid_lat, mid_lng)
        if landmark:
            mid_lat = landmark["lat"]
            mid_lng = landmark["lng"]
            mid_address = landmark["name"]
            time_map = {}  # 랜드마크 좌표 기준으로 재계산
        else:
            mid_address = None

        # 이동시간 병렬 계산 (timeFair이고 랜드마크 스냅 없으면 기존 값 재사용)
        if not time_map:
            times = await asyncio.gather(*[
                _travel_minutes(client, m["lat"], m["lng"], mid_lat, mid_lng, m["transport"])
                for m in located
            ])
            time_map = {m["name"]: t for m, t in zip(located, times)}

        travel_times = [
            {
                "name": m["name"],
                "minutes": time_map.get(m["name"], 0),
                "transport": m["transport"],
                "lat": m["lat"],
                "lng": m["lng"],
            }
            for m in located
        ]

        # 랜드마크 없으면 역지오코딩으로 주소 표시
        if not mid_address:
            kakao_key = os.getenv("KAKAO_API_KEY")
            if kakao_key:
                try:
                    resp = await client.get(
                        "https://dapi.kakao.com/v2/local/geo/coord2address.json",
                        params={"x": mid_lng, "y": mid_lat},
                        headers={"Authorization": f"KakaoAK {kakao_key}"},
                        timeout=5.0,
                    )
                    docs = resp.json().get("documents", [])
                    if docs:
                        road = docs[0].get("road_address")
                        addr = docs[0].get("address")
                        mid_address = (road or addr or {}).get("address_name")
                except Exception:
                    pass
        if not mid_address:
            mid_address = "중간 지점"

        response: dict = {
            "midpoint": {"lat": mid_lat, "lng": mid_lng},
            "address": mid_address,
            "travel_times": travel_times,
        }

        if polyline:
            polylines = await asyncio.gather(*[
                _member_polyline(client, m, mid_lat, mid_lng) for m in located
            ])
            response["polylines"] = list(polylines)

        return response
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# ── 탐색 상태 (메모리) ───────────────────────────────────────────
_search_status: dict = {}  # room_id → {"started": bool, "criteria": str}

@app.post("/room/{room_id}/start-search")
async def start_search(room_id: str, criteria: str = Query("distanceFair")):
    import time
    if criteria == 'reset':
        _search_status[room_id] = {"started": False, "criteria": "distanceFair", "time": time.time()}
        return {"ok": True}
    _search_status[room_id] = {"started": True, "criteria": criteria, "time": time.time()}
    return {"ok": True}

@app.get("/room/{room_id}/search-status")
async def get_search_status(room_id: str):
    import time
    status = _search_status.get(room_id, {"started": False, "criteria": "distanceFair"})
    if status.get("started") and time.time() - status.get("time", 0) > 30:
        _search_status[room_id] = {"started": False, "criteria": status["criteria"]}
        return {"started": False, "criteria": status["criteria"]}
    return status

# ── 실시간 위치 공유 ──────────────────────────────────────────────

@app.post("/room/{room_id}/location")
async def update_location(room_id: str, request: Request, data: UpdateLocationRequest):
    member_name = data.member_name.strip()
    if not member_name:
        raise HTTPException(status_code=400, detail="member_name이 필요합니다.")

    client = _client(request)
    try:
        members = await sb_select(client, "members", select="id",
                                  filters={"room_id": room_id, "name": member_name}, limit=1)
        if not members:
            raise HTTPException(status_code=404, detail="멤버를 찾을 수 없습니다.")

        update_data: dict = {"location_shared": data.shared}
        if data.shared and data.lat is not None and data.lng is not None:
            update_data["current_lat"] = data.lat
            update_data["current_lng"] = data.lng
        else:
            update_data["current_lat"] = None
            update_data["current_lng"] = None

        await sb_update(client, "members", update_data, {"id": members[0]["id"]})
        return {"ok": True}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/room/{room_id}/locations")
async def get_locations(room_id: str, request: Request):
    try:
        members = await sb_select(
            _client(request), "members",
            select="name,current_lat,current_lng,location_shared",
            filters={"room_id": room_id},
        )
        return {"locations": [
            {"name": m["name"], "lat": m["current_lat"], "lng": m["current_lng"]}
            for m in members
            if m.get("location_shared")
            and m.get("current_lat") is not None
            and m.get("current_lng") is not None
        ]}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


if __name__ == "__main__":
    import uvicorn
    uvicorn.run("app:app", host="0.0.0.0", port=5000, reload=True)
