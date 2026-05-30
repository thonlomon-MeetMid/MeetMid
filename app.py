from fastapi import FastAPI, HTTPException, Query, Request
from fastapi.middleware.cors import CORSMiddleware
from contextlib import asynccontextmanager
from dotenv import load_dotenv
from math import radians, sin, cos, asin, sqrt, atan2, degrees as math_degrees
from pydantic import BaseModel
import asyncio
import hashlib
import httpx
import json
import os
import re
import sys
import time
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


def _offset_point(lat: float, lng: float, distance_km: float, bearing_deg: float) -> tuple[float, float]:
    """중심점에서 bearing 방향으로 distance_km 이동한 좌표 반환."""
    R = 6371
    d = distance_km / R
    lat_r, lng_r, b = radians(lat), radians(lng), radians(bearing_deg)
    lat2 = asin(sin(lat_r) * cos(d) + cos(lat_r) * sin(d) * cos(b))
    lng2 = lng_r + atan2(sin(b) * sin(d) * cos(lat_r), cos(d) - sin(lat_r) * sin(lat2))
    return math_degrees(lat2), math_degrees(lng2)


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

# ── OSM 태그 실증 데이터 기반 매핑 ──────────────────────────────────
# ODsay subwayCode → OSM relation ref 태그 정확한 값
# 확인 출처: Overpass API 직접 조회 (2024)
#   신분당(ref="신분당"), 경춘(ref="경춘"), 공항철도(ref="공항철도"|"AREX"),
#   인천2호선(ref="I2"), 인천1호선(ref="I1")
_SUBWAY_CODE_TO_OSM_REF: dict = {
    # 수도권 광역
    22: "신분당",          # 확인: OSM ref="신분당" (종래 "신분당선" 불일치 수정)
    23: "경의중앙",        # 패턴: "경의중앙선"→"경의중앙"
    101: "공항철도",       # 확인: ref="공항철도" (AREX는 alt로 포함)
    104: "경춘",           # 확인: ref="경춘"
    107: "에버라인",
    108: "의정부경전철",
    110: "김포골드라인",
    112: "신림선",
    114: "서해",           # 패턴: "서해선"→"서해"
    116: "수인분당",       # 패턴: "수인분당선"→"수인분당" (분당/수인 alt 포함)
    # fallback 코드
    21: "수인분당", 109: "서해",
    # 인천
    100: "I1",             # 확인: 인천1호선 ref="I1" 패턴
    102: "I2",             # 확인: 인천2호선 ref="I2"
    # 부산
    71: "1", 72: "2", 73: "3", 74: "4",
    # 대구
    91: "1", 92: "2",
    # 광주
    81: "1",
    # 대전
    131: "1",
}

# OSM ref → 대체 ref 목록 (분리 운영 노선 or 복수 관계 대응)
_ALT_OSM_REFS: dict = {
    "수인분당": ["수인분당", "분당", "수인"],   # 구 분당선/수인선 포함
    "경의중앙": ["경의중앙", "경의", "중앙"],   # 구 경의선/중앙선 포함
    "공항철도": ["공항철도", "AREX"],           # 일반열차+직통열차
    "서해":     ["서해"],
    "신분당":   ["신분당"],
    "경춘":     ["경춘"],
}

# OSM ref → name= 필드 폴백 검색어 (regex, ref 매칭 0건일 때 2차 시도)
_OSM_REF_TO_NAME_SEARCH: dict = {
    "신분당":   "신분당선",
    "경의중앙": "경의중앙선|경의선|중앙선",
    "수인분당": "수인분당선|분당선|수인선",
    "공항철도": "공항철도|AREX",
    "경춘":     "경춘선",
    "서해":     "서해선",
    "에버라인": "에버라인",
    "의정부경전철": "의정부경전철",
    "김포골드라인": "김포골드라인",
    "신림선":   "신림선",
    "I1":       "인천.*1호|Incheon.*Line 1",
    "I2":       "인천.*2호|Incheon.*Line 2",
}


def _build_osm_subway_query(ref: str, bbox: str) -> str:
    """Overpass 쿼리 빌더 — 런타임과 프리캐싱 배치가 공용으로 사용.

    1차: 매핑 테이블의 정확한 ref= 조건 (확인된 OSM 값)
    2차: name~ 폴백 (같은 쿼리 union에 포함)
    → 한글 ref 불일치 문제를 다단계로 흡수.
    """
    route_filter = 'route~"subway|railway|light_rail|train"'
    refs = _ALT_OSM_REFS.get(ref, [ref])
    name_term = _OSM_REF_TO_NAME_SEARCH.get(ref, ref)

    parts: list[str] = []
    # 1차: 정확한 ref 매칭
    for r in refs:
        parts.append(f'relation[type=route][{route_filter}][ref="{r}"]({bbox});')
    # 2차: name~ 폴백 (1차와 union — 중복은 Overpass가 자동 제거)
    parts.append(f'relation[type=route][{route_filter}]["name"~"{name_term}"]({bbox});')

    return f'[out:json][timeout:25];({" ".join(parts)});way(r);out geom;'

# ── 파일 캐시 (역 ID 쌍 → polyline coords) ────────────────────────
_SUBWAY_CACHE_PATH = os.path.join(os.path.dirname(__file__), "data", "subway_cache.json")
_subway_file_cache: dict = {}   # "{sc}:{lo_id}:{hi_id}" → {"coords": [...], "lo_first": bool}

# ── 노선 단위 geometry 파일 캐시 (서버 재시작 후에도 OSM 재호출 없음) ────
_OSM_LINE_GEO_PATH = os.path.join(os.path.dirname(__file__), "data", "osm_line_geo.json")
_osm_line_geo_file: dict = {}   # ref(str) → assembled_paths([[lng,lat],...] 리스트)

# ── OSM 메모리 캐시 (세션 내 빠른 공유) ───────────────────────────────
_osm_subway_cache: dict = {}    # ref(str) → assembled paths — bbox 의존성 제거, 노선 단위 키
_osm_empty_cache: dict = {}     # ref(str) → float timestamp — 빈 응답 임시 기록 (TTL 후 재시도)
_OSM_EMPTY_TTL = 300.0          # 5분 후 재시도
_overpass_semaphore: asyncio.Semaphore | None = None  # 동시 Overpass 요청 제한

def _get_overpass_sem() -> asyncio.Semaphore:
    global _overpass_semaphore
    if _overpass_semaphore is None:
        _overpass_semaphore = asyncio.Semaphore(1)
    return _overpass_semaphore


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


def _load_osm_line_geo_cache() -> None:
    """노선 단위 assembled geometry를 파일에서 메모리·파일 캐시로 로드."""
    global _osm_line_geo_file
    try:
        with open(_OSM_LINE_GEO_PATH, encoding="utf-8") as f:
            _osm_line_geo_file = json.load(f)
        # 메모리 캐시(_osm_subway_cache)에도 올려 첫 요청부터 히트되도록 함
        _osm_subway_cache.update(_osm_line_geo_file)
        print(f"[LineGeoCache] {len(_osm_line_geo_file)}개 노선 geometry 로드 (OSM 재호출 없음)")
    except FileNotFoundError:
        _osm_line_geo_file = {}
    except Exception as e:
        print(f"[LineGeoCache] 로드 오류: {e}")
        _osm_line_geo_file = {}


def _save_osm_line_geo_cache() -> None:
    """노선 단위 assembled geometry를 파일에 영속 저장."""
    try:
        os.makedirs(os.path.dirname(_OSM_LINE_GEO_PATH), exist_ok=True)
        with open(_OSM_LINE_GEO_PATH, "w", encoding="utf-8") as f:
            json.dump(_osm_line_geo_file, f, ensure_ascii=False, separators=(",", ":"))
    except Exception as e:
        print(f"[LineGeoCache] 저장 오류: {e}")


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


async def _fetch_osm_paths(client: httpx.AsyncClient, subway_code: int) -> list:
    """노선 전체 OSM assembled paths 반환.

    cache_key = ref (노선 코드) — bbox 의존성 제거.
    같은 노선을 타는 멤버들이 동일 키를 공유하므로,
    첫 번째 멤버만 Overpass를 호출하고 나머지는 캐시 히트로 즉시 처리됨.

    캐시 계층:
      1. 메모리(_osm_subway_cache)  — 세션 내 가장 빠른 히트
      2. 파일(_osm_line_geo_file)   — 서버 재시작 후에도 OSM 재호출 없음
      3. Overpass API               — 완전 cold 일 때만 호출 (Semaphore(1) 보호)

    fallback: 실패 시 [] 반환 → 호출자(_subway_polyline_from_cache)가 구간 직선으로 대체.
    """
    ref = _SUBWAY_CODE_TO_OSM_REF.get(subway_code, str(subway_code))
    cache_key = ref  # 노선 단위 단일 키 (bbox 무관)

    # 1. 메모리 캐시 (세션 내 — 세마포어 진입 전 빠른 경로)
    if cache_key in _osm_subway_cache:
        print(f"[SubwayOSM] 메모리 캐시 히트 ref={ref}")
        return _osm_subway_cache[cache_key]

    # 2. 파일 캐시 (서버 재시작 후)
    if cache_key in _osm_line_geo_file:
        paths = _osm_line_geo_file[cache_key]
        _osm_subway_cache[cache_key] = paths
        print(f"[SubwayOSM] 파일 캐시 히트 ref={ref} ({len(paths)}경로) — OSM 호출 없음")
        return paths

    # 빈 응답 TTL 캐시 확인 (Overpass 과부하로 빈 응답을 받은 경우)
    if cache_key in _osm_empty_cache:
        since = time.time() - _osm_empty_cache[cache_key]
        if since < _OSM_EMPTY_TTL:
            print(f"[SubwayOSM] 빈 응답 캐시 히트 ref={ref} ({since:.0f}s / {_OSM_EMPTY_TTL:.0f}s)")
            return []
        del _osm_empty_cache[cache_key]  # TTL 만료 → 재시도 허용

    # 노선 전체를 한 번에 가져오기 위해 한국 전체 bbox 사용
    # → 멤버별 탑승 구간이 달라도 동일 노선이면 같은 geometry를 공유
    KOREA_BBOX = "33.0,124.0,38.5,131.5"
    query = _build_osm_subway_query(ref, KOREA_BBOX)

    _overpass_mirrors = [
        "https://overpass-api.de/api/interpreter",
        "https://overpass.kumi.systems/api/interpreter",
    ]
    _retry_delays = [0.5, 1.0, 2.0]

    async with _get_overpass_sem():
        # 세마포어 대기 중 다른 태스크가 채웠을 수 있으므로 재확인
        if cache_key in _osm_subway_cache:
            print(f"[SubwayOSM] 세마포어 대기 후 메모리 캐시 히트 ref={ref}")
            return _osm_subway_cache[cache_key]
        if cache_key in _osm_line_geo_file:
            paths = _osm_line_geo_file[cache_key]
            _osm_subway_cache[cache_key] = paths
            print(f"[SubwayOSM] 세마포어 대기 후 파일 캐시 히트 ref={ref}")
            return paths
        if cache_key in _osm_empty_cache:
            since = time.time() - _osm_empty_cache[cache_key]
            if since < _OSM_EMPTY_TTL:
                return []
            del _osm_empty_cache[cache_key]

        for mirror_url in _overpass_mirrors:
            mirror_name = mirror_url.split("/")[2]
            for attempt in range(3):
                if attempt > 0:
                    wait = _retry_delays[attempt - 1]
                    print(f"[SubwayOSM] {mirror_name} retry {attempt}/2, {wait:.1f}s 대기 (ref={ref})")
                    await asyncio.sleep(wait)
                t0 = time.time()
                try:
                    resp = await client.get(
                        mirror_url, params={"data": query},
                        headers={"User-Agent": "MeetMidApp/1.0"},
                        timeout=25.0,
                    )
                    elapsed = (time.time() - t0) * 1000
                    status = resp.status_code
                    print(f"[SubwayOSM] {mirror_name} status={status} {elapsed:.0f}ms ref={ref}")

                    if status == 429:
                        if attempt < 2:
                            continue
                        print(f"[SubwayOSM] {mirror_name} 429 재시도 소진 → 다음 mirror 시도")
                        break

                    resp.raise_for_status()
                    elems = resp.json().get("elements", [])
                    paths = _assemble_osm_ways(elems)
                    print(f"[SubwayOSM] {mirror_name} ref={ref}: {len(elems)}way → {len(paths)}경로")

                    if paths:
                        _osm_subway_cache[cache_key] = paths
                        _osm_line_geo_file[cache_key] = paths
                        _save_osm_line_geo_cache()
                        return paths

                    # 0way 원인 구분 로그
                    if len(elems) == 0:
                        print(f"[SubwayOSM] ⚠ 0 relation 매칭 ref={ref} — "
                              f"매핑 테이블 문제일 수 있음. {_OSM_EMPTY_TTL:.0f}s TTL")
                    else:
                        print(f"[SubwayOSM] relation {len(elems)}개 발견됐으나 way 조립 0 — "
                              f"해당 구간 OSM 미매핑. {_OSM_EMPTY_TTL:.0f}s TTL ref={ref}")

                    _osm_empty_cache[cache_key] = time.time()
                    return []

                except Exception as e:
                    elapsed = (time.time() - t0) * 1000
                    print(f"[SubwayOSM] 오류 {type(e).__name__} {elapsed:.0f}ms "
                          f"(mirror={mirror_name}, attempt={attempt+1}/3): {e}")
                    if attempt < 2:
                        continue
                    print(f"[SubwayOSM] {mirror_name} 재시도 소진 → 다음 mirror 시도")
                    break

        print(f"[SubwayOSM] 모든 mirror 실패 ref={ref} — 다음 요청에서 재시도")
        return []


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
        all_paths = await _fetch_osm_paths(client, subway_code)
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
    - 지하철(1): OSM Overpass 실노선 geometry (fallback: 역좌표 직선)
    - 버스(2):   첫/마지막 정류장 사이를 _car_polyline으로 실도로 표시
    - 도보(3):   구간 시작/끝 좌표 직선 연결
    반환: [[lng, lat], ...]

    [fallback 정책]
    - ODsay 자체 실패 → [] (호출자(_member_polyline)가 출발-도착 전체 직선으로 대체)
    - 특정 subPath geometry 실패 → 그 구간만 시작→끝 직선, 나머지는 유지
    즉 ODsay가 subPath를 반환한 이상, 출발-도착 전체 직선은 나오지 않는다.
    """
    odsay_key = os.getenv("ODSAY_API_KEY")
    if not odsay_key:
        return []

    # ── ODsay 경로 탐색 — 실패 시에만 [] 반환 (전체 직선 허용) ─────────
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
    except Exception as e:
        print(f"[TransitPolyline] ODsay 실패 → 전체 직선 fallback: {e}")
        return []

    # ── 실노선/버스 geometry 병렬 조회 ───────────────────────────────
    async_indices: list = []
    async_coros: list = []
    for i, sub in enumerate(sub_paths):
        stations = sub.get("passStopList", {}).get("stations", [])
        tt = sub.get("trafficType")
        try:
            if tt == 2 and len(stations) >= 2:
                s_lat = float(stations[0]["y"]);  s_lng = float(stations[0]["x"])
                e_lat = float(stations[-1]["y"]); e_lng = float(stations[-1]["x"])
                async_indices.append((i, "bus"))
                async_coros.append(_car_polyline(client, s_lat, s_lng, e_lat, e_lng))
            elif tt == 1 and len(stations) >= 2:
                lane = sub.get("lane", [{}])[0]
                subway_code = lane.get("subwayCode", 0)
                lane_name = lane.get("name") or lane.get("laneName") or ""
                print(f"[Transit] 지하철 구간: code={subway_code}, name='{lane_name}', 역수={len(stations)}")
                async_indices.append((i, "subway"))
                async_coros.append(_subway_polyline_from_cache(client, stations, subway_code))
        except Exception as e:
            print(f"[TransitPolyline] subPath {i} 조회 준비 오류: {e}")

    # return_exceptions=True: 구간 하나의 예외가 다른 멤버·구간 전체를 죽이지 않도록
    async_results = await asyncio.gather(*async_coros, return_exceptions=True)
    result_map = {
        idx: (res if not isinstance(res, Exception) else [])
        for (idx, _), res in zip(async_indices, async_results)
    }

    # ── subPath 조립 — 각 구간 실패는 구간 직선으로 대체 ──────────────
    all_coords: list = []
    for i, sub in enumerate(sub_paths):
        tt = sub.get("trafficType")
        sx, sy = sub.get("startX"), sub.get("startY")
        ex, ey = sub.get("endX"), sub.get("endY")

        def _sub_fallback(sx=sx, sy=sy, ex=ex, ey=ey) -> list:
            """이 subPath의 시작→끝 직선 (구간 단위 최소 fallback)."""
            pts = []
            if sx and sy:
                pts.append([float(sx), float(sy)])
            if ex and ey:
                pts.append([float(ex), float(ey)])
            return pts

        try:
            if tt in (1, 2):
                coords = result_map.get(i, [])
                if coords:
                    all_coords.extend(coords)
                    continue
                # geometry 없음 → stations 좌표 순서 연결
                stations = sub.get("passStopList", {}).get("stations", [])
                if stations:
                    for st in stations:
                        x, y = st.get("x"), st.get("y")
                        if x is not None and y is not None:
                            all_coords.append([float(x), float(y)])
                    continue
                # stations도 없음 → 구간 직선
                all_coords.extend(_sub_fallback())
            else:
                # 도보(tt=3) → 구간 직선
                all_coords.extend(_sub_fallback())
        except Exception as e:
            print(f"[TransitPolyline] subPath {i}(tt={tt}) 조립 오류 → 구간 직선 대체: {e}")
            all_coords.extend(_sub_fallback())

    return all_coords


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


# Gemini 결과 캐시 (prompt → {category, keyword}) — 같은 프롬프트면 재호출 없음
_GEMINI_CACHE_PATH = os.path.join(os.path.dirname(__file__), "data", "gemini_cache.json")
_gemini_prompt_cache: dict = {}
_MAX_GEMINI_CACHE = 200

# 상황 키워드 → 장소 키워드 룰 매핑 (Gemini 호출 전 빠른 경로)
_SITUATION_MAP = {
    "소개팅": "분위기카페",
    "데이트": "루프탑카페",
    "회식": "고깃집",
    "아이랑": "키즈카페",
    "아이와": "키즈카페",
    "어린이": "키즈카페",
    "가족": "패밀리레스토랑",
    "공부": "북카페",
    "독서": "북카페",
    "스터디": "스터디카페",
    "혼술": "이자카야",
    "혼밥": "음식점",
    "해장": "해장국",
}

# 검색 키워드 → 카카오 카테고리 코드 (더 정확한 카테고리 검색용)
_KW_TO_CODE = {"음식점": "FD6", "카페": "CE7", "편의점": "CS2", "맛집": "FD6"}

# Gemini 호출 없이 바로 카카오 검색 가능한 단순 키워드 (Gemini 타임아웃 방지)
_DIRECT_KEYWORDS = {
    "카페", "음식점", "맛집", "편의점", "술집", "이자카야", "호프", "포차",
    "노래방", "볼링장", "볼링", "방탈출카페", "방탈출", "영화관",
    "미술관", "박물관", "공원", "마트", "쇼핑몰",
    "북카페", "스터디카페", "키즈카페", "감성카페", "한옥카페", "루프탑카페",
    "피자", "치킨", "햄버거", "마라탕", "초밥", "삼겹살", "국밥",
    "해장국", "고깃집", "패밀리레스토랑", "이탈리안레스토랑",
    "스파", "찜질방", "마사지",
    "맥도날드", "롯데리아", "버거킹", "스타벅스", "이디야", "메가커피",
    "GS25", "CU", "세븐일레븐",
}

# 이 fallback 키워드들은 특정 음식명 검색 실패를 감추므로 목적지 탐색에서 제외
_BROAD_FOOD_FALLBACKS = {"음식점", "한식", "일식", "중식", "횟집"}

# 명시적 음식/장소 키워드 — 이게 있으면 상황 룰을 건너뛰고 Gemini로 넘김
_EXPLICIT_KEYWORDS = {
    "피자", "치킨", "햄버거", "버거", "초밥", "스시", "마라탕", "라멘", "라면",
    "파스타", "스테이크", "삼겹살", "갈비", "불고기", "냉면", "국밥", "떡볶이",
    "족발", "보쌈", "곱창", "막창", "닭갈비", "순대", "해장국", "설렁탕",
    "짜장면", "짬뽕", "탕수육", "양꼬치", "딤섬", "훠궈", "샤브샤브",
    "카페", "커피", "디저트", "케이크", "베이커리", "와플",
    "맥도날드", "롯데리아", "버거킹", "스타벅스", "이디야", "메가커피",
    "술집", "이자카야", "호프", "맥주", "와인", "소주", "포차", "바",
    "노래방", "볼링", "영화", "방탈출", "스크린골프", "클라이밍",
    "편의점", "마트", "쇼핑",
}


def _load_gemini_cache() -> None:
    try:
        with open(_GEMINI_CACHE_PATH, encoding="utf-8") as f:
            _gemini_prompt_cache.update(json.load(f))
        print(f"[GeminiCache] {len(_gemini_prompt_cache)}개 항목 로드")
    except FileNotFoundError:
        pass
    except Exception as e:
        print(f"[GeminiCache] 로드 오류: {e}")


def _save_gemini_cache() -> None:
    try:
        os.makedirs(os.path.dirname(_GEMINI_CACHE_PATH), exist_ok=True)
        with open(_GEMINI_CACHE_PATH, "w", encoding="utf-8") as f:
            json.dump(_gemini_prompt_cache, f, ensure_ascii=False, separators=(",", ":"))
    except Exception as e:
        print(f"[GeminiCache] 저장 오류: {e}")


async def _find_nearby_landmark(client: httpx.AsyncClient, lat: float, lng: float) -> dict | None:
    kakao_key = os.getenv("KAKAO_API_KEY")
    if not kakao_key:
        return None

    async def _fetch_category(code, radius):
        try:
            # AT4(관광명소)는 산 제외 필터링을 위해 후보 여러 개 조회
            size = 5 if code == "AT4" else 1
            resp = await client.get(
                "https://dapi.kakao.com/v2/local/search/category.json",
                params={"category_group_code": code, "x": lng, "y": lat,
                        "radius": radius, "sort": "distance", "size": size},
                headers={"Authorization": f"KakaoAK {kakao_key}"},
                timeout=5.0,
            )
            docs = resp.json().get("documents", [])
            if code == "AT4":
                # 카테고리 leaf가 "산"인 항목 제외 (예: "여행 > 관광,명소 > 자연명소 > 산")
                docs = [d for d in docs
                        if d.get("category_name", "").split(" > ")[-1].strip() != "산"]
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
    targets = [("SW8", 1000), ("AT4", 800)]
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


async def _get_google_rating(
    client: httpx.AsyncClient,
    google_key: str,
    place_name: str,
    lat: float,
    lng: float,
) -> dict:
    """Google Places API (New) Text Search로 별점/리뷰수 조회. 실패 시 rating=0 반환."""
    if not google_key or not place_name:
        return {"rating": 0, "review_count": 0}
    try:
        resp = await client.post(
            "https://places.googleapis.com/v1/places:searchText",
            json={
                "textQuery": place_name,
                "locationBias": {
                    "circle": {
                        "center": {"latitude": lat, "longitude": lng},
                        "radius": 100,
                    }
                },
            },
            headers={
                "X-Goog-Api-Key": google_key,
                "X-Goog-FieldMask": "places.rating,places.userRatingCount",
            },
            timeout=3.0,
        )
        data = resp.json()
        hits = data.get("places", [])
        print(f"[Google Rating] {place_name} → hits={len(hits)}, data={data}")
        if hits:
            rating = float(hits[0].get("rating", 0) or 0)
            count = int(hits[0].get("userRatingCount", 0) or 0)
            return {"rating": round(rating, 1), "review_count": count}
        return {"rating": 0, "review_count": 0}
    except Exception as e:
        print(f"[Google Rating 실패] {place_name}: {e}")
        return {"rating": 0, "review_count": 0}


_GEMINI_PARTICLES = ['입니다', '이에요', '예요', '이다', '으로', '로', '에서', '를', '을', '이가', '가', '이', '은', '는', '도', '만']

def _strip_gemini_output(raw: str) -> str:
    """Gemini 응답에서 순수 키워드만 추출 (불필요한 문장/어미/문장부호 제거)."""
    first_line = raw.strip().split('\n')[0].strip()
    tokens = first_line.split()
    first_token = tokens[0] if tokens else first_line
    cleaned = re.sub(r'[^가-힣a-zA-Z0-9]', '', first_token)
    for particle in sorted(_GEMINI_PARTICLES, key=len, reverse=True):
        if cleaned.endswith(particle) and len(cleaned) > len(particle) + 1:
            cleaned = cleaned[:-len(particle)]
            break
    return cleaned


def _best_doc(docs: list, keyword: str) -> dict | None:
    """여러 카카오 검색 결과 중 키워드와 가장 일치하는 장소 반환.
    관련 없는 결과만 있으면 None 반환."""
    if not docs:
        return None

    def score(doc):
        name = doc.get("place_name", "")
        cat = doc.get("category_name", "")
        s = 0
        if keyword in name:
            s += 3
        if keyword in cat:
            s += 2
        for i in range(len(keyword) - 1):
            sub = keyword[i:i + 2]
            if sub in name:
                s += 1
            if sub in cat:
                s += 1
        return s

    scored = [(score(doc), doc) for doc in docs]
    best_score, best_doc = max(scored, key=lambda x: x[0])

    if best_score == 0:
        print(f"[Gemini] '{keyword}' 관련 결과 없음 (최고점 0) → fallback 시도")
        return None

    return best_doc


def _get_fallback_keyword(keyword: str) -> str | None:
    """구체적 키워드 검색 실패 시 사용할 일반 키워드 반환."""
    rules = [
        # 카페/디저트
        (["카페", "커피", "브런치", "디저트", "케이크", "베이커리", "버블티", "흑당", "마카롱", "와플", "크로플", "티룸", "茶"], "카페"),

        # 음식 — 한식
        (["한식", "국밥", "설렁탕", "곰탕", "삼겹살", "고깃집", "갈비", "불고기", "냉면", "비빔밥", "쌈밥",
          "순대", "떡볶이", "분식", "김밥", "해장국", "백반", "보쌈", "족발", "닭갈비", "곱창", "막창"], "한식"),

        # 음식 — 일식
        (["일식", "초밥", "스시", "사시미", "회", "해산물", "라멘", "라면", "우동", "소바", "돈가스",
          "이자카야", "오마카세", "덮밥", "돈부리", "샤브샤브", "훠궈"], "일식"),

        # 음식 — 중식
        (["중식", "중국집", "짜장면", "짬뽕", "탕수육", "마라탕", "마라", "딤섬", "양꼬치"], "중식"),

        # 음식 — 양식/패스트푸드
        (["양식", "피자", "파스타", "스테이크", "햄버거", "버거", "샌드위치", "타코", "멕시코", "브리또",
          "치킨", "레스토랑", "그릴", "바비큐", "BBQ"], "음식점"),

        # 음식 — 해산물
        (["해산물", "조개구이", "게요리", "랍스터", "새우", "굴", "횟집"], "횟집"),

        # 술집/바
        (["술집", "이자카야", "포차", "호프", "맥주", "생맥주", "와인바", "루프탑바", "칵테일바", "펍", "바"], "술집"),

        # 카페 — 특수
        (["키즈카페", "어린이"], "키즈카페"),
        (["북카페", "만화카페", "독서"], "북카페"),
        (["PC방", "게임카페", "게임"], "PC방"),

        # 엔터테인먼트
        (["노래방", "코인노래", "노래"], "노래방"),
        (["볼링", "포켓볼", "당구", "탁구"], "볼링장"),
        (["영화", "시네마", "CGV", "롯데시네마", "메가박스"], "영화관"),
        (["방탈출", "탈출", "미션"], "방탈출카페"),
        (["VR", "가상현실", "아케이드"], "VR체험"),
        (["스크린골프", "골프"], "스크린골프"),
        (["클라이밍", "암벽"], "클라이밍센터"),

        # 문화/예술
        (["미술관", "갤러리", "전시"], "미술관"),
        (["박물관", "역사", "기념관"], "박물관"),
        (["공연", "뮤지컬", "연극", "콘서트"], "공연장"),
        (["서점", "책방", "도서관"], "서점"),

        # 쇼핑
        (["쇼핑", "백화점", "마트", "편집샵", "옷", "의류", "빈티지", "시장"], "쇼핑몰"),

        # 자연/야외
        (["공원", "산책", "광장", "한강", "강변"], "공원"),
        (["바다", "해변", "해수욕장"], "해수욕장"),

        # 휴식/뷰티
        (["스파", "찜질방", "사우나", "목욕"], "찜질방"),
        (["마사지", "힐링", "안마"], "마사지"),
        (["네일", "미용", "헤어", "살롱"], "네일샵"),

        # 스포츠/헬스
        (["헬스", "피트니스", "운동", "수영", "요가", "필라테스"], "헬스장"),
    ]
    for keywords, fallback in rules:
        if any(k in keyword for k in keywords):
            return fallback if fallback != keyword else None
    return None


async def _find_place_by_prompt(
    client: httpx.AsyncClient,
    lat: float,
    lng: float,
    prompt: str,
) -> dict | None:
    """Gemini가 프롬프트 전체를 분석해 장소명 추천 → 카카오 키워드 검색으로 좌표 반환."""
    kakao_key = os.getenv("KAKAO_API_KEY")
    if not kakao_key:
        return None

    # 캐시 확인
    cache_key = prompt.strip().lower()
    place_name = None
    from_cache = False

    if cache_key in _gemini_prompt_cache:
        place_name = _gemini_prompt_cache[cache_key].get("place_name")
        from_cache = True
        print(f"[Gemini] 캐시 사용: prompt='{prompt}' → place_name='{place_name}'")
    else:
        # 방법 2: 상황 키워드 룰 매핑 — 명시적 음식/장소 키워드가 없을 때만 적용
        has_explicit = any(kw in cache_key for kw in _EXPLICIT_KEYWORDS)
        if not has_explicit:
            for situation, mapped_kw in _SITUATION_MAP.items():
                if situation in cache_key:
                    place_name = mapped_kw
                    print(f"[Situation] '{situation}' 감지 → place_name='{place_name}'")
                    break

        # 방법 2b: 프롬프트 자체가 이미 알려진 카카오 검색 키워드 → Gemini 불필요
        if not place_name and cache_key in _DIRECT_KEYWORDS:
            place_name = cache_key
            print(f"[Direct] '{cache_key}' → 직접 사용 (Gemini 건너뜀)")

        if not place_name:
            # 방법 3: Gemini에게 프롬프트 전체를 주고 장소 유형명만 반환받기
            gemini_key = os.getenv("GEMINI_API_KEY")
            if not gemini_key:
                print("[Gemini] GEMINI_API_KEY 없음 → 프롬프트 검색 불가")
                return None
            gemini_payload = {
                "system_instruction": {"parts": [{"text": (
                    "당신은 카카오맵 장소 검색 전문가입니다. "
                    "사용자의 요청을 분석해서 카카오맵 키워드 검색에 적합한 장소 유형을 한국어로 딱 하나만 출력하세요. "
                    "출력 규칙: "
                    "1. 반드시 카카오맵에서 검색 가능한 2~5글자 키워드로 출력하세요. "
                    "2. 설명, 이유, 문장 형태는 절대 출력하지 마세요. 키워드만 출력하세요. "
                    "3. 분위기/감성이 중요한 경우 '감성카페', '루프탑카페', '한옥카페' 처럼 구체적으로 출력하세요. "
                    "4. '식당', '밥', '음식', '먹을 것', '밥집' 같은 일반 표현은 반드시 '음식점'으로 출력하세요. "
                    "5. '카페', '커피' 같은 단어는 반드시 '카페'로 출력하세요. "
                    "6. 맥도날드, 롯데리아, 버거킹, 스타벅스, 이디야, 투썸플레이스, 메가커피, 빽다방, GS25, CU, 세븐일레븐 같은 "
                    "특정 브랜드명이 포함된 경우 브랜드명을 그대로 출력하세요. "
                    "예시: "
                    "'소개팅하려고 하는데 분위기 좋은 카페' → '감성카페', "
                    "'분위기 있는 카페 어때' → '감성카페', "
                    "'둘이서 조용히 얘기하고 싶어' → '북카페', "
                    "'친구들이랑 술 한잔 하고 싶어' → '이자카야', "
                    "'가볍게 한잔 하기 좋은 곳' → '호프', "
                    "'분위기 있는 술자리 하고 싶어' → '와인바', "
                    "'조용히 공부하거나 쉬고 싶어' → '북카페', "
                    "'가족끼리 외식하고 싶어' → '패밀리레스토랑', "
                    "'분위기 있는 저녁 식사 하고 싶어' → '이탈리안레스토랑', "
                    "'데이트하기 좋은 곳' → '루프탑카페', "
                    "'뭔가 특별한 걸 하고 싶어' → '방탈출카페', "
                    "'친구들이랑 왁자지껄하게 놀고 싶어' → '노래방', "
                    "'아이랑 갈 수 있는 곳' → '키즈카페', "
                    "'해장하고 싶어' → '해장국', "
                    "'맛있는 거 먹고 싶어' → '맛집', "
                    "'야외에서 시간 보내고 싶어' → '공원', "
                    "'피자 먹고 싶어' → '피자', "
                    "'마라탕 먹으러 가자' → '마라탕', "
                    "'노래방 가고 싶어' → '노래방', "
                    "'방탈출 하고 싶어' → '방탈출카페', "
                    "'전시 보고 싶어' → '미술관', "
                    "'스파 가고 싶어' → '스파', "
                    "'쇼핑하고 싶어' → '쇼핑몰', "
                    "'산책하고 싶어' → '공원', "
                    "'식당 가고 싶어' → '음식점', "
                    "'밥 먹자' → '음식점', "
                    "'카페 가자' → '카페', "
                    "'커피 마시고 싶어' → '카페', "
                    "'맥도날드 가고 싶어' → '맥도날드', "
                    "'롯데리아 먹고 싶어' → '롯데리아', "
                    "'스타벅스 갈래' → '스타벅스', "
                    "'버거킹 가자' → '버거킹'. "
                    "키워드 외에 다른 말은 절대 출력하지 마세요."
                )}]},
                "contents": [{"parts": [{"text": f"요청: {prompt}"}]}],
                "generationConfig": {"maxOutputTokens": 30, "temperature": 0.1},
            }
            gemini_url = (
                f"https://generativelanguage.googleapis.com/v1beta/models/"
                f"gemini-2.5-flash-lite:generateContent?key={gemini_key}"
            )
            for attempt in range(2):
                try:
                    gemini_resp = await client.post(gemini_url, json=gemini_payload, timeout=15.0)
                    gemini_resp.raise_for_status()
                    candidates = gemini_resp.json().get("candidates", [])
                    raw = candidates[0]["content"]["parts"][0]["text"] if candidates else ""
                    place_name = _strip_gemini_output(raw) if raw else ""
                    if place_name:
                        break
                except Exception as e:
                    print(f"[Gemini] 분석 실패 (attempt {attempt + 1}): {e}")
                    if attempt == 1:
                        # Gemini 완전 실패 → 프롬프트에서 알려진 키워드 직접 추출
                        for kw in sorted(_DIRECT_KEYWORDS, key=len, reverse=True):
                            if kw in cache_key:
                                place_name = kw
                                print(f"[Gemini] 실패, 프롬프트 키워드 추출: '{kw}'")
                                break
                        if not place_name:
                            return None
                    print("[Gemini] 재시도 중...")

        if not place_name:
            return None

        print(f"[Search] 키워드 결정: prompt='{prompt}' → place_name='{place_name}'")

    if not place_name:
        return None

    # 카카오 키워드 검색: 구체 키워드 → 비음식 fallback 키워드 순으로 시도
    search_keywords = [place_name]
    fallback_kw = _get_fallback_keyword(place_name)
    if fallback_kw and fallback_kw not in _BROAD_FOOD_FALLBACKS:
        search_keywords.append(fallback_kw)
    # 카테고리별 추가 제외 필터
    _code_excludes = {
        "FD6": ["카페", "커피", "베이커리", "제과", "디저트"],
    }

    excluded = {"산", "봉", "계곡", "폭포", "등산"}
    for search_kw in search_keywords:
        category_code = _KW_TO_CODE.get(search_kw)
        extra_excluded = _code_excludes.get(category_code, [])
        for radius in [1000, 3000, 5000]:
            try:
                if category_code:
                    kakao_resp = await client.get(
                        "https://dapi.kakao.com/v2/local/search/category.json",
                        params={
                            "category_group_code": category_code,
                            "x": lng, "y": lat,
                            "radius": radius,
                            "sort": "distance",
                            "size": 5,
                        },
                        headers={"Authorization": f"KakaoAK {kakao_key}"},
                        timeout=5.0,
                    )
                else:
                    kakao_resp = await client.get(
                        "https://dapi.kakao.com/v2/local/search/keyword.json",
                        params={
                            "query": search_kw,
                            "x": lng, "y": lat,
                            "radius": radius,
                            "sort": "distance",
                            "size": 5,
                        },
                        headers={"Authorization": f"KakaoAK {kakao_key}"},
                        timeout=5.0,
                    )
                kakao_resp.raise_for_status()
                docs = kakao_resp.json().get("documents", [])
                valid_docs = [
                    d for d in docs
                    if not any(ex in d.get("category_name", "") for ex in excluded | set(extra_excluded))
                ]
                if valid_docs:
                    # 평점 병렬 조회 → 평점 있는 것 중 최고점 선택
                    _gkey = os.getenv("GOOGLE_MAPS_API_KEY", "")
                    ratings = await asyncio.gather(*[
                        _get_google_rating(client, _gkey, d.get("place_name", ""), float(d.get("y", 0)), float(d.get("x", 0))) for d in valid_docs
                    ])
                    rated_pairs = [(d, r) for d, r in zip(valid_docs, ratings) if r["rating"] > 0]
                    if rated_pairs:
                        doc = max(rated_pairs, key=lambda x: x[1]["rating"])[0]
                    else:
                        doc = _best_doc(valid_docs, search_kw)
                        if doc is None:
                            if category_code:
                                doc = valid_docs[0]
                            else:
                                continue
                    result = {
                        "name": doc["place_name"],
                        "lat": float(doc["y"]),
                        "lng": float(doc["x"]),
                        "category": "",
                        "keyword": search_kw,
                    }
                    # 카카오 검색 성공 시에만 캐시 저장 (최대 200개 초과 시 오래된 항목 제거)
                    if not from_cache:
                        _gemini_prompt_cache[cache_key] = {"place_name": place_name}
                        if len(_gemini_prompt_cache) > _MAX_GEMINI_CACHE:
                            oldest = list(_gemini_prompt_cache.keys())[0]
                            del _gemini_prompt_cache[oldest]
                        _save_gemini_cache()
                    print(f"[Gemini] 최종 장소: {result['name']} (키워드: '{search_kw}', radius: {radius}m)")
                    return result
            except Exception as e:
                print(f"[Gemini] 카카오 검색 실패(keyword='{search_kw}', radius={radius}): {e}")

    print(f"[Gemini] '{place_name}' 및 fallback 검색 결과 없음")
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


_FAIR_SPEED   = {"car": 1.5, "transit": 1.0}   # 교통수단 상대 속도
_FAIR_P_LIST  = [0.0, 0.5, 1.0, 1.5, 2.0, 2.5]  # 가중 지수 후보 (최대 6)
_FAIR_LAMBDA  = 0.7                               # 편차 가중치 (cost = mean + λ·spread)
_FAIR_DEDUP   = 1e-5                              # 후보 중복 판단 임계값(도 단위, ~1m)


async def _time_fair_midpoint(client: httpx.AsyncClient, members: list, max_iter: int = 6) -> tuple:
    """시간 공평 — 교통수단 속도 가중 중심점 후보 평가 방식.

    [핵심 설계]
    각 후보 center_p를 평가하기 전에 가장 가까운 역으로 스냅.
    대중교통 이동시간은 역 위치에 따라 계단식으로 달라지므로,
    평가도 "실제 모일 역"에서 수행해야 최적화 결과 ≡ 화면 표시 일치.

    반환: (snap_lat, snap_lng, time_map, station_name)
    - snap_lat/lng: 알고리즘이 선택한 역 좌표 (그대로 화면에 표시)
    - time_map: 해당 역에서 계산된 이동시간 (화면 표시값과 동일)
    - station_name: 역 이름 (mid_address로 사용)

    [API 호출]
    후보당: _find_nearby_landmark(~2 Kakao calls) + n회 travel_time = n+2 calls
    총 최대 6×(n+2). 기존 6n 대비 +12 Kakao lightweight calls.
    """
    n = len(members)

    # ── 1단계: 후보 좌표 생성 (API 없음) ──────────────────────────────
    candidates: list[tuple[float, float, float]] = []  # (lat, lng, p)
    seen: list[tuple[float, float]] = []

    for p in _FAIR_P_LIST:
        weights = [(1.0 / _FAIR_SPEED.get(m.get("transport", "transit"), 1.0)) ** p
                   for m in members]
        w_sum = sum(weights)
        clat = sum(w * m["lat"] for w, m in zip(weights, members)) / w_sum
        clng = sum(w * m["lng"] for w, m in zip(weights, members)) / w_sum

        dup = any(abs(clat - s[0]) < _FAIR_DEDUP and abs(clng - s[1]) < _FAIR_DEDUP
                  for s in seen)
        if not dup:
            candidates.append((clat, clng, p))
            seen.append((clat, clng))

    candidates = candidates[:max_iter]

    # ── 2단계: 각 후보 → 역 스냅 → 스냅된 역에서 평가 ────────────────
    best_lat, best_lng = candidates[0][0], candidates[0][1]
    best_cost = float("inf")
    best_time_map: dict = {}
    best_station_name: str | None = None

    for clat, clng, p in candidates:
        # 가장 가까운 역으로 스냅 (평가도 실제 모일 지점에서)
        station = await _find_nearby_landmark(client, clat, clng)
        if station:
            eval_lat = station["lat"]
            eval_lng = station["lng"]
            eval_name = station["name"]
        else:
            eval_lat, eval_lng = clat, clng
            eval_name = None

        times = await asyncio.gather(*[
            _travel_minutes(client, m["lat"], m["lng"], eval_lat, eval_lng, m["transport"])
            for m in members
        ])
        time_map = {m["name"]: t for m, t in zip(members, times)}

        mean_t = sum(times) / n
        spread = max(times) - min(times)
        cost   = mean_t + _FAIR_LAMBDA * spread

        names_str = ", ".join(f"{m['name']}{t:.0f}" for m, t in zip(members, times))
        print(f"[Fair] p={p:.1f}  snap={eval_name or '미스냅'}  "
              f"mean={mean_t:.1f}  spread={spread:.1f}  cost={cost:.1f}  t=[{names_str}]")

        # 이상치 경고
        sorted_t = sorted(times)
        mid = n // 2
        median_t = sorted_t[mid] if n % 2 == 1 else (sorted_t[mid-1] + sorted_t[mid]) / 2.0
        for m, t in zip(members, times):
            if median_t > 0 and t > 2.5 * median_t:
                print(f"[WARN] 라우팅 이상치 의심: {m['name']} {t:.0f}분 snap={eval_name}")

        if spread <= 2.0:
            best_lat, best_lng = eval_lat, eval_lng
            best_cost = cost
            best_time_map = time_map
            best_station_name = eval_name
            print(f"[Fair] spread≤2분 → 조기 채택 p={p:.1f} snap={eval_name}")
            break

        if cost < best_cost:
            best_cost = cost
            best_lat, best_lng = eval_lat, eval_lng
            best_time_map = time_map
            best_station_name = eval_name

    # ── 채택 후보 자동차 경고 ────────────────────────────────────────
    car_times     = [best_time_map[m["name"]] for m in members
                     if m.get("transport") == "car"]
    transit_times = [best_time_map[m["name"]] for m in members
                     if m.get("transport") != "car"]
    if car_times and transit_times:
        avg_transit = sum(transit_times) / len(transit_times)
        for m in members:
            if m.get("transport") == "car" and best_time_map[m["name"]] > avg_transit:
                print(f"[WARN] 자동차가 더 느림 ({m['name']} "
                      f"{best_time_map[m['name']]:.0f}분 > 대중교통 평균 {avg_transit:.0f}분)")

    t_str = ", ".join(f"{k}{v:.0f}" for k, v in best_time_map.items())
    print(f"[Fair] 최종 채택: snap={best_station_name}  cost={best_cost:.1f}  t=[{t_str}]")
    # 4-tuple: 화면 표시값(역 좌표·역명·이동시간)을 모두 포함 — get_midpoint가 그대로 사용
    return best_lat, best_lng, best_time_map, best_station_name


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
        "id": m["id"],
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
    room_password: str = ""

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
    target_name: str = ""
    target_member_id: str = ""

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

class UpdateRoomPromptRequest(BaseModel):
    prompt: str = ""


# ── FastAPI 앱 ────────────────────────────────────────────────────

@asynccontextmanager
async def lifespan(app: FastAPI):
    _load_subway_file_cache()
    _load_osm_line_geo_cache()
    _load_gemini_cache()
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
        rooms = await sb_select(client, "rooms", select="id,room_name,host_id,created_at,password")

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
            if len(members) >= 4:
                continue  # 정원 초과 방은 목록에서 제외
            result.append({
                "room_id": room["id"],
                "room_name": room["room_name"],
                "member_count": len(members),
                "member_names": [m["name"] for m in members],
                "has_password": bool(room.get("password")),
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

        room_data: dict = {"room_name": room_name, "host_id": host["id"]}
        raw_pw = data.room_password.strip()
        if raw_pw:
            room_data["password"] = _hash_pw(raw_pw)
        room_res = await sb_insert(client, "rooms", room_data)
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
    room_password = data.get("room_password", "").strip()

    if not name:
        raise HTTPException(status_code=400, detail="name이 필요합니다.")

    client = _client(request)
    try:
        rooms = await sb_select(client, "rooms", select="id,password", filters={"id": room_id}, limit=1)
        if not rooms:
            raise HTTPException(status_code=404, detail="존재하지 않는 방입니다.")

        # 이미 멤버거나 방장이 직접 추가한 경우 암호 체크 없이 허용
        already_member = await sb_select(client, "members", select="id",
                                         filters={"room_id": room_id, "name": name}, limit=1)
        # 최대 인원 4명 제한 (기존 멤버 업데이트는 허용)
        if not already_member:
            current_members = await _get_members(client, room_id)
            if len(current_members) >= 4:
                raise HTTPException(status_code=400, detail="최대 4명까지입니다.")
        if not already_member and not is_direct_added:
            stored_pw = rooms[0].get("password") or ""
            if stored_pw:
                if not room_password:
                    raise HTTPException(status_code=403, detail="암호가 필요한 방입니다.")
                if _hash_pw(room_password) != stored_pw:
                    raise HTTPException(status_code=403, detail="암호가 틀렸습니다.")

        resolved_user_id = None
        if user_uuid:
            resolved_user_id = user_uuid
        else:
            guest = await _get_or_create_guest_user(client, name)
            if guest:
                resolved_user_id = guest["id"]

        existing = already_member
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
    target_member_id = data.target_member_id.strip()

    if not requester_name or (not target_name and not target_member_id):
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

        if target_member_id:
            target_res = await sb_select(client, "members", select="id",
                                         filters={"id": target_member_id, "room_id": room_id}, limit=1)
        else:
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
                       polyline: bool = Query(False),
                       prompt: str = Query(""),
                       override_lat: float = Query(0.0),
                       override_lng: float = Query(0.0)):
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
        gemini_keyword = ""
        if override_lat != 0.0 and override_lng != 0.0:
            # 장소 선택 시 재계산: 지정 좌표를 목적지로 고정
            mid_lat, mid_lng = override_lat, override_lng
            mid_address = None
        else:
            if criteria == "timeFair" and len(located) >= 2:
                # _time_fair_midpoint가 내부에서 역 스냅까지 완료해 반환.
                # 추가 landmark snap 없이 그대로 사용 → 로그·화면 100% 일치.
                mid_lat, mid_lng, time_map, snap_name = await _time_fair_midpoint(client, located)
                mid_address = snap_name  # 알고리즘이 선택한 역 이름
                # ── 진단 로그: 최적화 결과 vs 화면 표시 일치 확인 ──
                algo_t = ", ".join(f"{k}{v:.0f}" for k, v in time_map.items())
                print(f"[Fair] 화면 표시 center=({mid_lat:.5f},{mid_lng:.5f})"
                      f"  역={mid_address}  t=[{algo_t}]")
                print(f"[Fair] ✓ 최적화 좌표 = 표시 좌표 (스냅 일치, 시간 폭발 없음)")
            elif criteria == "distanceFair" and len(located) >= 2:
                mid_lat, mid_lng, _ = await _route_distance_fair_midpoint(client, located)
                # 랜드마크 스냅
                landmark = await _find_nearby_landmark(client, mid_lat, mid_lng)
                if landmark:
                    mid_lat = landmark["lat"]
                    mid_lng = landmark["lng"]
                    mid_address = landmark["name"]
                else:
                    mid_address = None
            elif criteria in ("majority", "transitFocused") and len(located) >= 2:
                mid_lat, mid_lng = await _majority_midpoint(client, located)
                landmark = await _find_nearby_landmark(client, mid_lat, mid_lng)
                if landmark:
                    mid_lat = landmark["lat"]
                    mid_lng = landmark["lng"]
                    mid_address = landmark["name"]
                else:
                    mid_address = None
            else:
                mid_lat = sum(m["lat"] for m in located) / len(located)
                mid_lng = sum(m["lng"] for m in located) / len(located)
                landmark = await _find_nearby_landmark(client, mid_lat, mid_lng)
                if landmark:
                    mid_lat = landmark["lat"]
                    mid_lng = landmark["lng"]
                    mid_address = landmark["name"]
                else:
                    mid_address = None

            # 프롬프트가 있으면 Gemini로 근처 장소 탐색 → 최종 목적지 대체
            prompt = prompt.strip()
            gemini_keyword = ""
            if prompt:
                print(f"[Midpoint] Gemini 검색 전 좌표: lat={mid_lat}, lng={mid_lng}")
                place = await _find_place_by_prompt(client, mid_lat, mid_lng, prompt)
                if place:
                    mid_lat = place["lat"]
                    mid_lng = place["lng"]
                    mid_address = place["name"]
                    gemini_keyword = place.get("keyword", "")
                    time_map = {}  # 새 좌표 기준으로 이동시간 재계산
                    print(f"[Midpoint] Gemini 장소 적용 후 좌표: lat={mid_lat}, lng={mid_lng}, name={mid_address}")

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
            "gemini_keyword": gemini_keyword,
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


# ── 방 프롬프트 저장 ──────────────────────────────────────────────

@app.patch("/room/{room_id}/prompt")
async def update_room_prompt(room_id: str, request: Request, data: UpdateRoomPromptRequest):
    client = _client(request)
    try:
        if not await sb_select(client, "rooms", select="id", filters={"id": room_id}, limit=1):
            raise HTTPException(status_code=404, detail="존재하지 않는 방입니다.")
        await sb_update(client, "rooms", {"prompt": data.prompt}, filters={"id": room_id})
        return {"ok": True}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# ── 경로 polyline 전용 ────────────────────────────────────────────

@app.get("/midpoint/{room_id}/polylines")
async def get_member_polylines(
    room_id: str,
    request: Request,
    lat: float = Query(...),
    lng: float = Query(...),
):
    """midpoint 재계산 없이 멤버별 경로 polyline만 반환 (백그라운드 로드용)."""
    client = _client(request)
    try:
        members = await _get_members(client, room_id)
        members_with_addr = [m for m in members if m["address"]]
        coords_list = await asyncio.gather(*[
            geocode_address(client, m["address"]) for m in members_with_addr
        ])
        located = [
            {**m, "lat": c[0], "lng": c[1]}
            for m, c in zip(members_with_addr, coords_list)
            if c is not None
        ]
        if not located:
            return {"polylines": []}
        polylines = await asyncio.gather(*[
            _member_polyline(client, m, lat, lng) for m in located
        ])
        return {"polylines": list(polylines)}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


async def _ring_search_docs(
    client: httpx.AsyncClient,
    kakao_key: str,
    category_code: str | None,
    keyword: str,
    lat: float,
    lng: float,
    min_radius: int,
    radius: int,
) -> list:
    """링(min_radius~radius) 내 장소: 링 중심 4방향에서 병렬 검색 후 진거리 필터링."""
    ring_center_km = (min_radius + radius) / 2000.0
    ring_half_m = int((radius - min_radius) / 2 * 1.3)

    async def _from_bearing(bearing: int) -> list:
        o_lat, o_lng = _offset_point(lat, lng, ring_center_km, bearing)
        try:
            if category_code:
                resp = await client.get(
                    "https://dapi.kakao.com/v2/local/search/category.json",
                    params={"category_group_code": category_code, "x": o_lng, "y": o_lat,
                            "radius": ring_half_m, "sort": "distance", "size": 15},
                    headers={"Authorization": f"KakaoAK {kakao_key}"}, timeout=5.0,
                )
            else:
                resp = await client.get(
                    "https://dapi.kakao.com/v2/local/search/keyword.json",
                    params={"query": keyword, "x": o_lng, "y": o_lat,
                            "radius": ring_half_m, "sort": "distance", "size": 15},
                    headers={"Authorization": f"KakaoAK {kakao_key}"}, timeout=5.0,
                )
            resp.raise_for_status()
            result = []
            for d in resp.json().get("documents", []):
                true_m = _haversine_km(lat, lng, float(d["y"]), float(d["x"])) * 1000
                if min_radius <= true_m <= radius:
                    result.append({**d, "distance": true_m})
            return result
        except Exception:
            return []

    batches = await asyncio.gather(*[_from_bearing(b) for b in [0, 90, 180, 270]])
    seen: set = set()
    docs: list = []
    for batch in batches:
        for d in batch:
            if d.get("id") not in seen:
                seen.add(d.get("id"))
                docs.append(d)
    return docs


# ── 장소 추천 ──────────────────────────────────────────────────────

@app.get("/room/{room_id}/places")
async def get_place_recommendations(
    room_id: str,
    request: Request,
    category: str = Query(""),   # 전체=빈값, 식당=FD6, 카페=CE7, 편의점=CS2, 문화시설=CT1, 관광명소=AT4
    lat: float = Query(0.0),
    lng: float = Query(0.0),
    radius: int = Query(500),
    min_radius: int = Query(0),
    size: int = Query(5),
):
    """카카오 카테고리 검색으로 장소 목록 반환 (별점 내림차순)."""
    client = _client(request)
    kakao_key = os.getenv("KAKAO_API_KEY")

    if not kakao_key:
        raise HTTPException(status_code=500, detail="KAKAO_API_KEY가 없습니다.")

    # 좌표가 없으면 방 멤버 중간지점 자동 계산
    if lat == 0.0 and lng == 0.0:
        try:
            members = await _get_members(client, room_id)
            members_with_addr = [m for m in members if m["address"]]
            coords_list = await asyncio.gather(*[
                geocode_address(client, m["address"]) for m in members_with_addr
            ])
            located = [{"lat": c[0], "lng": c[1]} for c in coords_list if c]
            if located:
                lat = sum(m["lat"] for m in located) / len(located)
                lng = sum(m["lng"] for m in located) / len(located)
        except Exception:
            pass

    print(f"[Places 호출] lat={lat}, lng={lng}, category={category}, radius={radius}")
    valid_codes = {"CE7", "FD6", "CT1", "AT4", "SW8", "CS2", "MT1", "PM9", "HP8", "BK9"}
    category_code = category if category in valid_codes else None
    keyword = "맛집"  # 전체(category_code=None)일 때 키워드 검색에 사용

    # 카테고리별 제외 키워드
    category_excludes = {
        "FD6": ["카페", "커피", "베이커리", "제과", "디저트"],
        "MT1": ["편의점"],
    }
    exclude_keywords = category_excludes.get(category_code or "", [])

    places = []
    try:
        docs = []

        if min_radius > 0:
            # ── 링 검색: 오프셋 4방향 병렬 검색 ──────────────────
            docs = await _ring_search_docs(
                client, kakao_key, category_code, keyword, lat, lng, min_radius, radius
            )
            if not docs:
                fallback_kw = _get_fallback_keyword(keyword)
                fallback_code = _KW_TO_CODE.get(fallback_kw) if fallback_kw else None
                if fallback_kw and fallback_kw != keyword:
                    print(f"[Places] 링 결과 없음 → 1차 fallback '{fallback_kw}'")
                    docs = await _ring_search_docs(
                        client, kakao_key, fallback_code, fallback_kw,
                        lat, lng, min_radius, radius
                    )
                    if docs:
                        exclude_keywords = category_excludes.get(fallback_code or "", [])
            if not docs:
                _CAFE_HINTS = {"카페", "커피", "디저트", "케이크", "브런치", "베이커리"}
                _FOOD_HINTS = {"음식", "식당", "맛집", "레스토랑", "먹", "요리", "한식", "일식", "중식", "양식"}
                kw_lower = keyword.lower()
                fb2_code: str | None = None
                if any(h in kw_lower for h in _CAFE_HINTS):
                    fb2_code = "CE7"
                elif any(h in kw_lower for h in _FOOD_HINTS):
                    fb2_code = "FD6"
                if fb2_code and fb2_code != category_code:
                    print(f"[Places] 링 2차 fallback → {fb2_code}")
                    docs = await _ring_search_docs(
                        client, kakao_key, fb2_code, keyword, lat, lng, min_radius, radius
                    )

        else:
            # ── 500m: 중심점에서 정확도순 검색 ───────────────────
            try:
                if category_code:
                    resp = await client.get(
                        "https://dapi.kakao.com/v2/local/search/category.json",
                        params={"category_group_code": category_code, "x": lng, "y": lat,
                                "radius": radius, "sort": "accuracy", "size": size},
                        headers={"Authorization": f"KakaoAK {kakao_key}"}, timeout=5.0,
                    )
                else:
                    resp = await client.get(
                        "https://dapi.kakao.com/v2/local/search/keyword.json",
                        params={"query": keyword, "x": lng, "y": lat,
                                "radius": radius, "sort": "accuracy", "size": size},
                        headers={"Authorization": f"KakaoAK {kakao_key}"}, timeout=5.0,
                    )
                resp.raise_for_status()
                docs = resp.json().get("documents", [])
            except Exception as e:
                print(f"[Places] 카카오 검색 실패(radius={radius}): {e}")

        # exclude 카테고리 제외
        filtered_docs = [
            d for d in docs
            if not any(ex in d.get("category_name", "") for ex in exclude_keywords)
        ]

        # 구글 Places API로 별점 병렬 조회 (장소당 1회, timeout 3초)
        google_key = os.getenv("GOOGLE_MAPS_API_KEY", "")
        ratings_list: list[dict] = [{"rating": 0, "review_count": 0}] * len(filtered_docs)
        if filtered_docs:
            fetched = await asyncio.gather(*[
                _get_google_rating(client, google_key, d.get("place_name", ""),
                                   float(d.get("y", 0)), float(d.get("x", 0)))
                for d in filtered_docs
            ])
            ratings_list = list(fetched)
            # 별점 있는 결과가 하나라도 있으면 내림차순 정렬
            if any(r["rating"] > 0 for r in ratings_list):
                paired = sorted(zip(filtered_docs, ratings_list),
                                key=lambda x: x[1]["rating"], reverse=True)
                filtered_docs = [d for d, _ in paired]
                ratings_list = [r for _, r in paired]

        for i, doc in enumerate(filtered_docs):
            rating, review_cnt = ratings_list[i]["rating"], ratings_list[i]["review_count"]
            dist_m = float(doc.get("distance", 0))
            dist_str = f"{int(dist_m)}m" if dist_m < 1000 else f"{dist_m/1000:.1f}km"
            places.append({
                "id": doc.get("id", str(i)),
                "name": doc.get("place_name", ""),
                "category": doc.get("category_name", "").split(" > ")[-1],
                "distance": dist_str,
                "address": doc.get("road_address_name") or doc.get("address_name", ""),
                "rating": rating,
                "reviewCount": review_cnt,
                "aiRecommended": False,
                "lat": float(doc.get("y", lat)),
                "lng": float(doc.get("x", lng)),
                "url": doc.get("place_url", ""),
            })
    except Exception as e:
        print(f"[Places] 카카오 검색 실패: {e}")

    return {"places": places, "category": category_code, "keyword": keyword}


if __name__ == "__main__":
    import uvicorn
    uvicorn.run("app:app", host="0.0.0.0", port=5000, reload=True)