"""
지하철 polyline 파일 캐시 사전 수집 스크립트.

실행: python scripts/prebuild_subway_cache.py

ODsay 경로 검색 → subPath 지하철 구간 추출 → OSM 슬라이싱 → data/subway_cache.json 저장.
같은 키가 이미 있으면 스킵하므로 여러 번 실행해도 안전.
"""

import asyncio
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))

import httpx
from app import (
    _SUBWAY_CODE_TO_OSM_REF,
    _assemble_osm_ways,
    _cache_key,
    _load_subway_file_cache,
    _lookup_pair,
    _save_subway_file_cache,
    _store_pair,
    _subway_file_cache,
    slice_lane_coords,
)

# 각 경로는 (출발 lng, 출발 lat, 도착 lng, 도착 lat, 레이블)
SAMPLE_ROUTES = [
    (126.6161, 37.4743, 126.9724, 37.5547, "인천→서울역 (1호선)"),
    (126.9244, 37.5566, 127.0276, 37.4979, "홍대→강남 (2호선)"),
    (127.0586, 37.5392, 126.9769, 37.5796, "왕십리→광화문 (5호선)"),
    (126.9813, 37.4764, 127.0286, 37.4979, "사당→강남 (2호선)"),
    (127.0286, 37.4979, 127.1082, 37.5134, "강남→잠실 (2호선)"),
    (127.1082, 37.5134, 127.0586, 37.5392, "잠실→왕십리 (2호선)"),
    # 4호선
    (126.9813, 37.4764, 126.9679, 37.5179, "사당→서울역 (4호선)"),
    (126.9679, 37.5179, 127.0422, 37.6128, "서울역→당고개 (4호선)"),
    # 5호선
    (126.8014, 37.5636, 126.9769, 37.5796, "김포공항→광화문 (5호선)"),
    (126.9769, 37.5796, 127.1174, 37.5497, "광화문→마천 (5호선)"),
    # 3호선
    (126.9244, 37.5566, 127.0586, 37.5392, "홍대입구→왕십리 (2·3·5호선)"),
    (126.9244, 37.5566, 127.0193, 37.6547, "홍대→수서 (3호선)"),
]


async def fetch_odsay(client: httpx.AsyncClient, sx, sy, ex, ey, label: str, api_key: str):
    params = {
        "apiKey": api_key,
        "SX": str(sx), "SY": str(sy),
        "EX": str(ex), "EY": str(ey),
        "OPT": "0", "SearchType": "0",
    }
    try:
        resp = await client.get(
            "https://api.odsay.com/v1/api/searchPubTransPathT",
            params=params, timeout=15.0,
        )
        resp.raise_for_status()
        data = resp.json()
        paths = data.get("result", {}).get("path", [])
        if not paths:
            print(f"  [{label}] 경로 없음")
            return []
        subs = []
        for sub in paths[0].get("subPath", []):
            if sub.get("trafficType") == 1:
                stations = sub.get("passStopList", {}).get("stations", [])
                lane = sub.get("lane", [{}])
                sc = lane[0].get("subwayCode", 0) if lane else 0
                if len(stations) >= 2 and sc:
                    subs.append((sc, stations))
        return subs
    except Exception as e:
        print(f"  [{label}] ODsay 오류: {e}")
        return []


async def fetch_osm(client: httpx.AsyncClient, subway_code: int, stations: list) -> list:
    lats = [float(s["y"]) for s in stations]
    lngs = [float(s["x"]) for s in stations]
    margin = 0.06
    min_lat = round(min(lats) - margin, 2)
    max_lat = round(max(lats) + margin, 2)
    min_lng = round(min(lngs) - margin, 2)
    max_lng = round(max(lngs) + margin, 2)
    ref = _SUBWAY_CODE_TO_OSM_REF.get(subway_code, str(subway_code))
    query = (
        f'[out:json][timeout:40];'
        f'relation[type=route][route=subway][ref="{ref}"]'
        f'({min_lat},{min_lng},{max_lat},{max_lng});'
        f'way(r);out geom;'
    )
    try:
        resp = await client.get(
            "https://overpass-api.de/api/interpreter",
            params={"data": query},
            headers={"User-Agent": "MeetMidPrebuild/1.0"},
            timeout=45.0,
        )
        resp.raise_for_status()
        elems = resp.json().get("elements", [])
        paths = _assemble_osm_ways(elems)
        print(f"    OSM ref={ref}: {len(elems)}개 way → {len(paths)}개 경로")
        return paths
    except Exception as e:
        print(f"    OSM 오류: {e}")
        return []


async def main():
    env_vars: dict = {}
    env_path = os.path.join(os.path.dirname(os.path.dirname(__file__)), ".env")
    try:
        with open(env_path) as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith("#") and "=" in line:
                    k, v = line.split("=", 1)
                    env_vars[k.strip()] = v.strip().strip('"').strip("'")
    except FileNotFoundError:
        pass

    api_key = env_vars.get("ODSAY_API_KEY", os.getenv("ODSAY_API_KEY", ""))
    if not api_key:
        print("ODSAY_API_KEY 없음 — .env 파일을 확인하세요")
        return

    _load_subway_file_cache()
    total_new = 0

    async with httpx.AsyncClient() as client:
        for sx, sy, ex, ey, label in SAMPLE_ROUTES:
            print(f"\n[{label}]")
            subs = await fetch_odsay(client, sx, sy, ex, ey, label, api_key)
            if not subs:
                continue

            # 노선별 OSM 캐시 (한 경로 내 같은 노선 중복 쿼리 방지)
            osm_cache: dict = {}

            for sc, stations in subs:
                osm_key = (sc, round(min(float(s["y"]) for s in stations) - 0.06, 2),
                           round(max(float(s["y"]) for s in stations) + 0.06, 2))
                if osm_key not in osm_cache:
                    osm_cache[osm_key] = await fetch_osm(client, sc, stations)
                    await asyncio.sleep(6)  # Overpass rate limit

                all_paths = osm_cache[osm_key]
                if not all_paths:
                    continue

                line_new = 0
                for si in range(len(stations) - 1):
                    st0, st1 = stations[si], stations[si + 1]
                    id0, id1 = st0.get("stationID", 0), st1.get("stationID", 0)
                    if not id0 or not id1:
                        continue
                    if _lookup_pair(sc, id0, id1) is not None:
                        continue  # 이미 캐시됨

                    seg = slice_lane_coords(
                        all_paths,
                        float(st0["x"]), float(st0["y"]),
                        float(st1["x"]), float(st1["y"]),
                        st0.get("stationName", ""),
                        st1.get("stationName", ""),
                    )
                    if seg is not None:
                        _store_pair(sc, id0, id1, seg)
                        line_new += 1

                if line_new:
                    print(f"    subwayCode={sc}: {line_new}개 구간 신규 저장")
                    total_new += line_new

    if total_new:
        _save_subway_file_cache()
        print(f"\n완료: {total_new}개 신규 구간 → data/subway_cache.json 저장")
    else:
        print("\n신규 구간 없음 (이미 모두 캐시됨)")

    # _subway_file_cache는 app 모듈의 dict를 직접 참조
    import app as _app
    print(f"총 캐시 항목: {len(_app._subway_file_cache)}개")


if __name__ == "__main__":
    asyncio.run(main())
