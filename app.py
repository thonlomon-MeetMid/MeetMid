from flask import Flask, request, jsonify
from flask_cors import CORS
from dotenv import load_dotenv
from math import radians, sin, cos, asin, sqrt
import hashlib
import os
import uuid
import sys
import json
import requests


def _haversine_km(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    """두 좌표 간 구면 거리 (km)."""
    R = 6371
    dlat = radians(lat2 - lat1)
    dlng = radians(lng2 - lng1)
    a = sin(dlat / 2) ** 2 + cos(radians(lat1)) * cos(radians(lat2)) * sin(dlng / 2) ** 2
    return 2 * R * asin(sqrt(a))


def _fair_midpoint(points: list, max_iter: int = 200) -> tuple:
    """1-Center: 가장 먼 멤버까지의 거리를 최소화하는 점 (거리 공평).
    Haversine 기반, 점진적 step 감소로 안정 수렴.
    points: [(lat, lng), ...]
    """
    n = len(points)
    if n == 1:
        return points[0]
    if n == 2:
        return ((points[0][0] + points[1][0]) / 2,
                (points[0][1] + points[1][1]) / 2)

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


# ── 이동 시간 계산 ────────────────────────────────────────────

def _get_transit_minutes(src_lat, src_lng, dst_lat, dst_lng):
    """ODsay 대중교통 소요시간 (분). 실패 시 None."""
    odsay_key = os.getenv("ODSAY_API_KEY")
    if not odsay_key:
        return None
    try:
        resp = requests.get(
            "https://api.odsay.com/v1/api/searchPubTransPathT",
            params={
                "apiKey": odsay_key,
                "SX": src_lng,
                "SY": src_lat,
                "EX": dst_lng,
                "EY": dst_lat,
            },
            timeout=10,
        )
        resp.raise_for_status()
        data = resp.json()
        result = data.get("result")
        if not result:
            return None
        paths = result.get("path", [])
        if not paths:
            return None
        total = paths[0].get("info", {}).get("totalTime")
        return int(total) if total else None
    except Exception as e:
        print(f"[ODsay error] {e}")
        return None


def _get_car_minutes(src_lat, src_lng, dst_lat, dst_lng):
    """카카오 모빌리티 자동차 소요시간 (분). 실패 시 None."""
    kakao_key = os.getenv("KAKAO_API_KEY")
    if not kakao_key:
        return None
    try:
        resp = requests.get(
            "https://apis-navi.kakaomobility.com/v1/directions",
            params={
                "origin": f"{src_lng},{src_lat}",
                "destination": f"{dst_lng},{dst_lat}",
            },
            headers={"Authorization": f"KakaoAK {kakao_key}"},
            timeout=10,
        )
        resp.raise_for_status()
        routes = resp.json().get("routes", [])
        if not routes:
            return None
        duration_sec = routes[0].get("summary", {}).get("duration", 0)
        return max(1, round(duration_sec / 60))
    except Exception as e:
        print(f"[Kakao Navi error] {e}")
        return None


def _find_nearby_landmark(lat: float, lng: float) -> str | None:
    """중간지점 근처 주요 거점(지하철역 → 관광명소/공원 → 학교) 이름 반환. 없으면 None."""
    kakao_key = os.getenv("KAKAO_API_KEY")
    if not kakao_key:
        return None
    # (카테고리 코드, 탐색 반경 m) 우선순위 순
    targets = [("SW8", 1000), ("AT4", 800), ("SC4", 600)]
    for code, radius in targets:
        try:
            resp = requests.get(
                "https://dapi.kakao.com/v2/local/search/category.json",
                params={"category_group_code": code, "x": lng, "y": lat,
                        "radius": radius, "sort": "distance", "size": 1},
                headers={"Authorization": f"KakaoAK {kakao_key}"},
                timeout=5,
            )
            docs = resp.json().get("documents", [])
            if docs:
                return docs[0]["place_name"]
        except Exception as e:
            print(f"[Landmark] {code} 오류: {e}")
    return None


def _travel_minutes(src_lat, src_lng, dst_lat, dst_lng, transport):
    """교통수단별 이동시간(분). API 실패 시 거리·속도 기반 추정."""
    if transport == "transit":
        t = _get_transit_minutes(src_lat, src_lng, dst_lat, dst_lng)
        if t is not None:
            return t
    elif transport == "car":
        t = _get_car_minutes(src_lat, src_lng, dst_lat, dst_lng)
        if t is not None:
            return t

    distance_km = _haversine_km(src_lat, src_lng, dst_lat, dst_lng)
    speed_kmh = {"car": 30, "transit": 20, "walk": 4}.get(transport, 20)
    return max(1, round((distance_km / speed_kmh) * 60))


def _time_fair_midpoint(members: list, max_iter: int = 6) -> tuple:
    """시간 공평: 각 멤버의 이동시간 max-min 차를 최소화하는 점.
    가장 오래 걸리는 멤버 쪽으로 점진 이동.
    members: [{lat, lng, transport, name, ...}, ...]
    반환: (mid_lat, mid_lng, {name: minutes})
    """
    n = len(members)
    cx = sum(m["lat"] for m in members) / n
    cy = sum(m["lng"] for m in members) / n
    time_map = {}

    step = 0.4
    for it in range(max_iter):
        time_map = {}
        slowest = None
        slowest_t = -1
        fastest_t = float("inf")
        for m in members:
            t = _travel_minutes(m["lat"], m["lng"], cx, cy, m["transport"])
            time_map[m["name"]] = t
            if t > slowest_t:
                slowest_t = t
                slowest = m
            if t < fastest_t:
                fastest_t = t

        if slowest is None:
            break
        if slowest_t - fastest_t <= 2:  # 시간 차이 2분 이내면 수렴
            break
        if it == max_iter - 1:
            break

        cx += (slowest["lat"] - cx) * step
        cy += (slowest["lng"] - cy) * step
        step *= 0.7

    return cx, cy, time_map


def _majority_midpoint(members: list, cluster_radius_km: float = 5.0, max_iter: int = 50) -> tuple:
    """다수결 중간: 인원이 많은 지역에 가중치를 부여한 가중 기하중앙값 (Weiszfeld).

    1. Haversine 5km 반경으로 멤버를 클러스터링
    2. 각 클러스터 중심 + 인원수를 가중치로 설정
    3. Weiszfeld 알고리즘으로 가중 기하중앙값 수렴
    members: [{lat, lng, ...}, ...]
    반환: (mid_lat, mid_lng)
    """
    if len(members) == 1:
        return members[0]["lat"], members[0]["lng"]
    if len(members) == 2:
        return (
            (members[0]["lat"] + members[1]["lat"]) / 2,
            (members[0]["lng"] + members[1]["lng"]) / 2,
        )

    # ── 1. 클러스터링 (greedy, 거리 기준) ───────────────────────
    clusters = []  # [{cx, cy, weight}]
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

    # ── 2. 가중 평균을 시작점으로 ───────────────────────────────
    total_w = sum(c["weight"] for c in clusters)
    cx = sum(c["lat"] * c["weight"] for c in clusters) / total_w
    cy = sum(c["lng"] * c["weight"] for c in clusters) / total_w

    # ── 3. Weiszfeld 반복 ────────────────────────────────────────
    for _ in range(max_iter):
        num_lat = num_lng = denom = 0.0
        for c in clusters:
            d = _haversine_km(cx, cy, c["lat"], c["lng"])
            if d < 1e-9:
                # 현재 점이 클러스터 중심과 일치하면 해당 클러스터는 건너뜀
                continue
            w = c["weight"] / d
            num_lat += w * c["lat"]
            num_lng += w * c["lng"]
            denom += w

        if denom == 0:
            break

        new_cx = num_lat / denom
        new_cy = num_lng / denom

        # 수렴 판정: 10m 이내 이동이면 중단
        if _haversine_km(cx, cy, new_cx, new_cy) * 1000 < 10:
            cx, cy = new_cx, new_cy
            break
        cx, cy = new_cx, new_cy

    return cx, cy


load_dotenv()

if sys.platform == "win32":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

app = Flask(__name__)
CORS(app, resources={r"/*": {"origins": "*"}})

# Supabase REST API — service_role 키로 RLS 우회
_supabase_url = os.getenv("SUPABASE_URL", "")
_supabase_service_key = os.getenv("SUPABASE_SERVICE_KEY", os.getenv("SUPABASE_KEY", ""))
_SB_REST = f"{_supabase_url}/rest/v1"
_SB_HEADERS = {
    "apikey": _supabase_service_key,
    "Authorization": f"Bearer {_supabase_service_key}",
    "Content-Type": "application/json",
    "Prefer": "return=representation",
}


@app.after_request
def add_cors_headers(response):
    response.headers['Access-Control-Allow-Origin'] = '*'
    response.headers['Access-Control-Allow-Methods'] = 'GET, POST, PUT, DELETE, OPTIONS'
    response.headers['Access-Control-Allow-Headers'] = 'Content-Type, Authorization'
    return response


@app.before_request
def handle_preflight():
    if request.method == 'OPTIONS':
        response = app.make_default_options_response()
        response.headers['Access-Control-Allow-Origin'] = '*'
        response.headers['Access-Control-Allow-Methods'] = 'GET, POST, PUT, DELETE, OPTIONS'
        response.headers['Access-Control-Allow-Headers'] = 'Content-Type, Authorization'
        return response


# ── Supabase REST 헬퍼 ────────────────────────────────────────

def sb_select(table: str, select: str = "*", limit: int = None, filters: dict = None) -> list:
    params = {"select": select}
    if filters:
        for k, v in filters.items():
            params[k] = f"eq.{v}"
    if limit:
        params["limit"] = str(limit)
    r = requests.get(f"{_SB_REST}/{table}", params=params, headers=_SB_HEADERS, timeout=10)
    r.raise_for_status()
    return r.json()


def sb_insert(table: str, data: dict) -> list:
    r = requests.post(f"{_SB_REST}/{table}", json=data, headers=_SB_HEADERS, timeout=10)
    r.raise_for_status()
    return r.json()


def sb_update(table: str, data: dict, filters: dict) -> list:
    params = {k: f"eq.{v}" for k, v in filters.items()}
    r = requests.patch(f"{_SB_REST}/{table}", params=params, json=data, headers=_SB_HEADERS, timeout=10)
    r.raise_for_status()
    return r.json()


def sb_delete(table: str, filters: dict) -> None:
    params = {k: f"eq.{v}" for k, v in filters.items()}
    r = requests.delete(f"{_SB_REST}/{table}", params=params, headers=_SB_HEADERS, timeout=10)
    r.raise_for_status()


def sb_select_ordered(table: str, select: str = "*", order_col: str = "created_at", order_asc: bool = True, filters: dict = None) -> list:
    params = {"select": select, "order": f"{order_col}.{'asc' if order_asc else 'desc'}"}
    if filters:
        for k, v in filters.items():
            params[k] = f"eq.{v}"
    r = requests.get(f"{_SB_REST}/{table}", params=params, headers=_SB_HEADERS, timeout=10)
    r.raise_for_status()
    return r.json()


def sb_select_in(table: str, in_col: str, in_values: list, select: str = "*") -> list:
    """PostgREST IN 필터: parentheses URL 인코딩 방지를 위해 URL 수동 구성"""
    if not in_values:
        return []
    values_str = ",".join(str(v) for v in in_values)
    url = f"{_SB_REST}/{table}?select={select}&{in_col}=in.({values_str})"
    r = requests.get(url, headers=_SB_HEADERS, timeout=10)
    r.raise_for_status()
    return r.json()


# ── 내부 헬퍼 ────────────────────────────────────────────────

def _hash_pw(password: str) -> str:
    return hashlib.sha256(password.encode()).hexdigest()


def _mask_username(username: str) -> str:
    """아이디 일부 마스킹: 앞 3자리 공개 + 나머지 *"""
    n = len(username)
    if n <= 2:
        return username[0] + "*" * (n - 1)
    show = min(3, max(2, n // 3))
    return username[:show] + "*" * (n - show)


def _get_or_create_guest_user(name: str) -> dict | None:
    """닉네임으로 users 테이블 조회. 없으면 게스트 계정 생성."""
    try:
        rows = sb_select("users", filters={"name": name}, limit=1)
        if rows:
            return rows[0]
        suffix = uuid.uuid4().hex[:6]
        guest_username = f"guest_{name.replace(' ', '_')}_{suffix}"
        guest_email = f"{guest_username}@guest.local"
        guest_pw = _hash_pw(uuid.uuid4().hex)
        inserted = sb_insert("users", {
            "name": name,
            "username": guest_username,
            "email": guest_email,
            "password": guest_pw,
        })
        return inserted[0] if inserted else None
    except Exception as e:
        print(f"[ERROR] _get_or_create_guest_user: {e}")
        return None


def _get_members(room_id: str) -> list:
    return sb_select("members", filters={"room_id": room_id})


def _format_member(m: dict) -> dict:
    return {
        "name": m["name"],
        "address": m["address"],
        "transport": m["transport"],
        "is_direct_added": m.get("is_direct_added", False),
    }


def geocode_address(address: str):
    try:
        address = address.encode("latin-1").decode("cp949")
    except (UnicodeEncodeError, UnicodeDecodeError):
        pass
    kakao_key = os.getenv("KAKAO_API_KEY")
    if not kakao_key:
        return None
    headers = {"Authorization": f"KakaoAK {kakao_key}"}
    try:
        resp = requests.get(
            "https://dapi.kakao.com/v2/local/search/address.json",
            params={"query": address},
            headers=headers,
            timeout=5,
        )
        resp.raise_for_status()
        docs = resp.json().get("documents", [])
        if docs:
            return float(docs[0]["y"]), float(docs[0]["x"])
        # 주소 검색 실패 시 키워드 검색으로 폴백
        resp = requests.get(
            "https://dapi.kakao.com/v2/local/search/keyword.json",
            params={"query": address, "size": 1},
            headers=headers,
            timeout=5,
        )
        resp.raise_for_status()
        docs = resp.json().get("documents", [])
        if docs:
            return float(docs[0]["y"]), float(docs[0]["x"])
        return None
    except Exception:
        return None


@app.route("/geocode", methods=["GET"])
def geocode_endpoint():
    address = request.args.get("address", "").strip()
    if not address:
        return jsonify({"error": "address가 필요합니다."}), 400
    coords = geocode_address(address)
    if coords:
        return jsonify({"lat": coords[0], "lng": coords[1]})
    return jsonify({"error": "주소를 찾을 수 없습니다."}), 404


@app.route("/reverse-geocode", methods=["GET"])
def reverse_geocode():
    lat = request.args.get("lat", "").strip()
    lng = request.args.get("lng", "").strip()
    if not lat or not lng:
        return jsonify({"error": "lat, lng가 필요합니다."}), 400
    kakao_key = os.getenv("KAKAO_API_KEY")
    if not kakao_key:
        return jsonify({"address": ""})
    try:
        resp = requests.get(
            "https://dapi.kakao.com/v2/local/geo/coord2address.json",
            params={"x": lng, "y": lat},
            headers={"Authorization": f"KakaoAK {kakao_key}"},
            timeout=5,
        )
        resp.raise_for_status()
        docs = resp.json().get("documents", [])
        if docs:
            road = docs[0].get("road_address") or {}
            addr = docs[0].get("address") or {}
            address = road.get("address_name") or addr.get("address_name", "")
            return jsonify({"address": address})
        return jsonify({"address": ""})
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.route("/places/search", methods=["GET"])
def search_places():
    query = request.args.get("query", "").strip()
    if not query:
        return jsonify({"places": []})
    kakao_key = os.getenv("KAKAO_API_KEY")
    if not kakao_key:
        return jsonify({"places": []})
    try:
        resp = requests.get(
            "https://dapi.kakao.com/v2/local/search/keyword.json",
            params={"query": query, "size": 10},
            headers={"Authorization": f"KakaoAK {kakao_key}"},
            timeout=5,
        )
        resp.raise_for_status()
        docs = resp.json().get("documents", [])
        places = [
            {
                "name": d.get("place_name", ""),
                "address": d.get("road_address_name") or d.get("address_name", ""),
            }
            for d in docs
        ]
        return jsonify({"places": places})
    except Exception as e:
        return jsonify({"error": str(e)}), 500


# ── 인증 ─────────────────────────────────────────────────────

@app.route("/auth/check-username/<username>", methods=["GET"])
def check_username(username):
    rows = sb_select("users", select="id", filters={"username": username}, limit=1)
    return jsonify({"available": len(rows) == 0})


@app.route("/auth/check-email", methods=["GET"])
def check_email():
    email = request.args.get("email", "").strip()
    if not email:
        return jsonify({"error": "email이 필요합니다."}), 400
    rows = sb_select("users", select="id", filters={"email": email}, limit=1)
    return jsonify({"available": len(rows) == 0})


@app.route("/auth/register", methods=["POST"])
def register():
    data = request.json or {}
    name = data.get("name", "").strip()
    username = data.get("username", "").strip()
    email = data.get("email", "").strip()
    password = data.get("password", "").strip()

    if not name or not username or not email or not password:
        return jsonify({"error": "name, username, email, password가 필요합니다."}), 400

    try:
        if sb_select("users", select="id", filters={"username": username}, limit=1):
            return jsonify({"error": "이미 사용 중인 아이디입니다."}), 409
        if sb_select("users", select="id", filters={"email": email}, limit=1):
            return jsonify({"error": "이미 사용 중인 이메일입니다."}), 409

        inserted = sb_insert("users", {
            "name": name,
            "username": username,
            "email": email,
            "password": _hash_pw(password),
        })
        if not inserted:
            return jsonify({"error": "회원가입 실패"}), 500

        user = inserted[0]
        return jsonify({
            "ok": True,
            "user": {
                "id": user["id"],
                "name": user["name"],
                "username": user["username"],
                "email": user["email"],
            },
        }), 201
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.route("/auth/login", methods=["POST"])
def login():
    data = request.json or {}
    username = data.get("username", "").strip()
    password = data.get("password", "").strip()

    if not username or not password:
        return jsonify({"error": "username과 password가 필요합니다."}), 400

    try:
        rows = sb_select("users", filters={"username": username, "password": _hash_pw(password)}, limit=1)
        if not rows:
            return jsonify({"error": "아이디 또는 비밀번호가 올바르지 않습니다."}), 401

        user = rows[0]
        return jsonify({
            "ok": True,
            "user": {
                "id": user["id"],
                "name": user["name"],
                "username": user["username"],
                "email": user["email"],
            },
        })
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.route("/auth/find-username", methods=["POST"])
def find_username():
    data = request.json or {}
    name = data.get("name", "").strip()
    email = data.get("email", "").strip()

    if not name or not email:
        return jsonify({"error": "name과 email이 필요합니다."}), 400

    try:
        rows = sb_select("users", select="username", filters={"name": name, "email": email}, limit=1)
        if not rows:
            return jsonify({"error": "일치하는 계정이 없습니다."}), 404

        return jsonify({"username": _mask_username(rows[0]["username"])})
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.route("/auth/find-pw/verify", methods=["POST"])
def find_pw_verify():
    """아이디 + 이메일로 본인 확인 (비밀번호 재설정 전 1단계)"""
    data = request.json or {}
    username = data.get("username", "").strip()
    email = data.get("email", "").strip()

    if not username or not email:
        return jsonify({"error": "username과 email이 필요합니다."}), 400

    try:
        rows = sb_select("users", select="id", filters={"username": username, "email": email}, limit=1)
        if not rows:
            return jsonify({"error": "아이디 또는 이메일이 올바르지 않습니다."}), 404
        return jsonify({"ok": True})
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.route("/auth/reset-password", methods=["POST"])
def reset_password():
    data = request.json or {}
    username = data.get("username", "").strip()
    email = data.get("email", "").strip()
    new_password = data.get("new_password", "").strip()

    if not username or not email or not new_password:
        return jsonify({"error": "username, email, new_password가 필요합니다."}), 400

    try:
        rows = sb_select("users", select="id", filters={"username": username, "email": email}, limit=1)
        if not rows:
            return jsonify({"error": "아이디 또는 이메일이 올바르지 않습니다."}), 404

        sb_update("users", {"password": _hash_pw(new_password)}, filters={"id": rows[0]["id"]})
        return jsonify({"ok": True})
    except Exception as e:
        return jsonify({"error": str(e)}), 500


# ── 방 목록 ───────────────────────────────────────────────────

@app.route("/rooms", methods=["GET"])
def get_rooms():
    try:
        user_id = request.args.get("user_id", "").strip()

        if user_id:
            member_rows = sb_select("members", select="room_id", filters={"user_id": user_id})
            room_ids = list({m["room_id"] for m in member_rows})
            if not room_ids:
                return jsonify({"rooms": []})
            rooms = sb_select_in("rooms", "id", room_ids, select="id,room_name,host_id,created_at")
        else:
            rooms = sb_select("rooms", select="id,room_name,host_id,created_at")

        result = []
        for room in rooms:
            members = _get_members(room["id"])
            host_name = ""
            try:
                u = sb_select("users", select="name", filters={"id": room["host_id"]}, limit=1)
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
        return jsonify({"rooms": result})
    except Exception as e:
        return jsonify({"error": str(e)}), 500


# ── 전체 방 목록 (참여 중 제외) ─────────────────────────────────

@app.route("/rooms/all", methods=["GET"])
def get_rooms_all():
    """해당 user_id가 members에 없는 방만 반환 (방 찾기용)"""
    try:
        user_id = request.args.get("user_id", "").strip()
        search = request.args.get("search", "").strip().lower()

        rooms = sb_select("rooms", select="id,room_name,host_id,created_at")

        if user_id:
            member_rows = sb_select("members", select="room_id", filters={"user_id": user_id})
            my_room_ids = {m["room_id"] for m in member_rows}
            rooms = [r for r in rooms if r["id"] not in my_room_ids]

        if search:
            rooms = [r for r in rooms if search in r["room_name"].lower()]

        result = []
        for room in rooms:
            members = _get_members(room["id"])
            result.append({
                "room_id": room["id"],
                "room_name": room["room_name"],
                "member_count": len(members),
            })
        return jsonify({"rooms": result})
    except Exception as e:
        return jsonify({"error": str(e)}), 500


# ── 방 만들기 ─────────────────────────────────────────────────

@app.route("/room", methods=["POST"])
def create_room():
    data = request.json or {}
    room_name = data.get("room_name", "").strip()
    host_name = data.get("host_name", "").strip()
    host_uuid = data.get("host_uuid", "").strip()

    if not room_name:
        return jsonify({"error": "room_name이 필요합니다."}), 400
    if not host_name and not host_uuid:
        return jsonify({"error": "host_name 또는 host_uuid가 필요합니다."}), 400

    try:
        if host_uuid:
            u = sb_select("users", select="id,name", filters={"id": host_uuid}, limit=1)
            if not u:
                return jsonify({"error": "존재하지 않는 사용자입니다."}), 404
            host = u[0]
        else:
            host = _get_or_create_guest_user(host_name)
            if not host:
                return jsonify({"error": "사용자 처리 실패"}), 500

        room_res = sb_insert("rooms", {"room_name": room_name, "host_id": host["id"]})
        if not room_res:
            return jsonify({"error": "방 생성 실패"}), 500

        room = room_res[0]
        sb_insert("members", {
            "room_id": room["id"],
            "user_id": host["id"],
            "name": host["name"],
            "address": "",
            "transport": "transit",
        })

        members = _get_members(room["id"])
        return jsonify({
            "room_id": room["id"],
            "room_name": room["room_name"],
            "host_id": host["name"],
            "host_uuid": host["id"],
            "members": [_format_member(m) for m in members],
        })
    except Exception as e:
        return jsonify({"error": str(e)}), 500


# ── 방 참여 ───────────────────────────────────────────────────

@app.route("/room/<room_id>/join", methods=["POST"])
def join_room(room_id: str):
    raw = request.data
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
        return jsonify({"error": "name이 필요합니다."}), 400

    try:
        if not sb_select("rooms", select="id", filters={"id": room_id}, limit=1):
            return jsonify({"error": "존재하지 않는 방입니다."}), 404

        resolved_user_id = None
        if user_uuid:
            resolved_user_id = user_uuid
        else:
            guest = _get_or_create_guest_user(name)
            if guest:
                resolved_user_id = guest["id"]

        existing = sb_select("members", select="id", filters={"room_id": room_id, "name": name}, limit=1)
        if existing:
            sb_update("members", {"address": address, "transport": transport}, filters={"id": existing[0]["id"]})
        else:
            member_data = {
                "room_id": room_id,
                "user_id": resolved_user_id,
                "name": name,
                "address": address,
                "transport": transport,
            }
            if is_direct_added:
                try:
                    sb_insert("members", {**member_data, "is_direct_added": True})
                except Exception:
                    sb_insert("members", member_data)
            else:
                sb_insert("members", member_data)

        members = _get_members(room_id)
        return jsonify({"ok": True, "members": [_format_member(m) for m in members]})
    except Exception as e:
        return jsonify({"error": str(e)}), 500


# ── 멤버 정보 변경 (방장이 직접 추가한 멤버만) ────────────────────────

@app.route("/room/<room_id>/member", methods=["PUT"])
def update_member(room_id: str):
    data = request.json or {}
    requester_name = data.get("requester_name", "").strip()
    old_name = data.get("old_name", "").strip()
    new_name = data.get("new_name", old_name).strip() or old_name
    address = data.get("address", "").strip()
    transport = data.get("transport", "transit")

    if not old_name:
        return jsonify({"error": "old_name이 필요합니다."}), 400

    try:
        room_res = sb_select("rooms", select="host_id", filters={"id": room_id}, limit=1)
        if not room_res:
            return jsonify({"error": "존재하지 않는 방입니다."}), 404

        host_uuid = room_res[0]["host_id"]
        host_user = sb_select("users", select="name", filters={"id": host_uuid}, limit=1)
        host_name = host_user[0]["name"] if host_user else ""

        if host_name != requester_name:
            return jsonify({"error": "방장만 정보를 변경할 수 있습니다."}), 403

        member_res = sb_select("members", select="id", filters={"room_id": room_id, "name": old_name}, limit=1)
        if not member_res:
            return jsonify({"error": "해당 멤버가 없습니다."}), 404

        sb_update("members",
                  {"name": new_name, "address": address, "transport": transport},
                  filters={"id": member_res[0]["id"]})

        members = _get_members(room_id)
        return jsonify({"ok": True, "members": [_format_member(m) for m in members]})
    except Exception as e:
        return jsonify({"error": str(e)}), 500


# ── 강퇴 ─────────────────────────────────────────────────────

@app.route("/room/<room_id>/kick", methods=["POST"])
def kick_member(room_id: str):
    data = request.json or {}
    requester_name = data.get("requester_name", "").strip()
    target_name = data.get("target_name", "").strip()

    if not requester_name or not target_name:
        return jsonify({"error": "requester_name과 target_name이 필요합니다."}), 400

    try:
        room_res = sb_select("rooms", select="host_id", filters={"id": room_id}, limit=1)
        if not room_res:
            return jsonify({"error": "존재하지 않는 방입니다."}), 404

        host_uuid = room_res[0]["host_id"]
        host_user = sb_select("users", select="name", filters={"id": host_uuid}, limit=1)
        host_name = host_user[0]["name"] if host_user else ""

        if host_name != requester_name:
            return jsonify({"error": "방장만 강퇴할 수 있습니다."}), 403

        target_res = sb_select("members", select="id", filters={"room_id": room_id, "name": target_name}, limit=1)
        if not target_res:
            return jsonify({"error": "해당 멤버가 없습니다."}), 404

        sb_delete("members", filters={"id": target_res[0]["id"]})
        members = _get_members(room_id)
        return jsonify({"ok": True, "members": [_format_member(m) for m in members]})
    except Exception as e:
        return jsonify({"error": str(e)}), 500


# ── 방장 양도 ─────────────────────────────────────────────────

@app.route("/room/<room_id>/transfer-host", methods=["POST"])
def transfer_host(room_id: str):
    data = request.json or {}
    requester_name = data.get("requester_name", "").strip()
    new_host_name = data.get("new_host_name", "").strip()

    if not requester_name or not new_host_name:
        return jsonify({"error": "requester_name과 new_host_name이 필요합니다."}), 400

    try:
        room_res = sb_select("rooms", select="host_id", filters={"id": room_id}, limit=1)
        if not room_res:
            return jsonify({"error": "존재하지 않는 방입니다."}), 404

        host_uuid = room_res[0]["host_id"]
        host_user = sb_select("users", select="name", filters={"id": host_uuid}, limit=1)
        host_name = host_user[0]["name"] if host_user else ""

        if host_name != requester_name:
            return jsonify({"error": "방장만 권한을 양도할 수 있습니다."}), 403

        new_host_member = sb_select(
            "members", select="user_id,name",
            filters={"room_id": room_id, "name": new_host_name}, limit=1,
        )
        if not new_host_member:
            return jsonify({"error": "해당 멤버가 없습니다."}), 404

        new_host_user_id = new_host_member[0]["user_id"]
        if not new_host_user_id:
            guest = _get_or_create_guest_user(new_host_name)
            new_host_user_id = guest["id"] if guest else None

        if not new_host_user_id:
            return jsonify({"error": "새 방장의 사용자 정보를 찾을 수 없습니다."}), 500

        sb_update("rooms", {"host_id": new_host_user_id}, filters={"id": room_id})
        members = _get_members(room_id)
        return jsonify({
            "ok": True,
            "host_id": new_host_name,
            "host_uuid": new_host_user_id,
            "members": [_format_member(m) for m in members],
        })
    except Exception as e:
        return jsonify({"error": str(e)}), 500


# ── 방 나가기 ─────────────────────────────────────────────────

@app.route("/room/<room_id>/leave", methods=["POST"])
def leave_room(room_id: str):
    data = request.json or {}
    user_name = data.get("user_name", "").strip()

    if not user_name:
        return jsonify({"error": "user_name이 필요합니다."}), 400

    try:
        room_res = sb_select("rooms", select="id,host_id", filters={"id": room_id}, limit=1)
        if not room_res:
            return jsonify({"error": "존재하지 않는 방입니다."}), 404

        host_uuid = room_res[0]["host_id"]

        leaving_member = sb_select("members", select="id,user_id,name",
                                   filters={"room_id": room_id, "name": user_name}, limit=1)
        if not leaving_member:
            return jsonify({"error": "해당 멤버가 없습니다."}), 404

        sb_delete("members", filters={"id": leaving_member[0]["id"]})

        remaining = _get_members(room_id)

        if not remaining:
            sb_delete("rooms", filters={"id": room_id})
            return jsonify({"ok": True, "room_deleted": True})

        host_user = sb_select("users", select="name", filters={"id": host_uuid}, limit=1)
        host_name = host_user[0]["name"] if host_user else ""
        new_host_name = host_name

        if host_name == user_name:
            new_host = remaining[0]
            new_host_user_id = new_host.get("user_id")
            if not new_host_user_id:
                guest = _get_or_create_guest_user(new_host["name"])
                new_host_user_id = guest["id"] if guest else None
            if new_host_user_id:
                sb_update("rooms", {"host_id": new_host_user_id}, filters={"id": room_id})
                new_host_name = new_host["name"]

        return jsonify({
            "ok": True,
            "room_deleted": False,
            "host_id": new_host_name,
            "members": [_format_member(m) for m in remaining],
        })
    except Exception as e:
        return jsonify({"error": str(e)}), 500


# ── 중간지점 ──────────────────────────────────────────────────

@app.route("/midpoint/<room_id>", methods=["GET"])
def get_midpoint(room_id: str):
    try:
        if not sb_select("rooms", select="id", filters={"id": room_id}, limit=1):
            return jsonify({"error": "존재하지 않는 방입니다."}), 404

        members = _get_members(room_id)
        if not members:
            return jsonify({"error": "멤버가 없습니다."}), 400

        located = []
        for m in members:
            if not m["address"]:
                continue
            coords = geocode_address(m["address"])
            if coords:
                located.append({**m, "lat": coords[0], "lng": coords[1]})

        if not located:
            return jsonify({"error": "좌표를 확인할 수 있는 멤버가 없습니다."}), 400

        criteria = request.args.get("criteria", "distanceFair")
        time_map = {}
        if criteria == "timeFair" and len(located) >= 2:
            mid_lat, mid_lng, time_map = _time_fair_midpoint(located)
        elif criteria == "distanceFair" and len(located) >= 2:
            mid_lat, mid_lng = _fair_midpoint(
                [(m["lat"], m["lng"]) for m in located]
            )
        elif criteria == "majority" and len(located) >= 2:
            mid_lat, mid_lng = _majority_midpoint(located)
        else:
            mid_lat = sum(m["lat"] for m in located) / len(located)
            mid_lng = sum(m["lng"] for m in located) / len(located)
        if not time_map:
            time_map = {m["name"]: _travel_minutes(m["lat"], m["lng"], mid_lat, mid_lng, m["transport"]) for m in located}

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
        # 중간지점: 주변 랜드마크 우선, 없으면 역지오코딩 주소
        mid_address = _find_nearby_landmark(mid_lat, mid_lng) or "중간 지점"
        if mid_address == "중간 지점":
            try:
                kakao_key = os.getenv("KAKAO_API_KEY")
                if kakao_key:
                    resp = requests.get(
                        "https://dapi.kakao.com/v2/local/geo/coord2address.json",
                        params={"x": mid_lng, "y": mid_lat},
                        headers={"Authorization": f"KakaoAK {kakao_key}"},
                        timeout=5,
                    )
                    docs = resp.json().get("documents", [])
                    if docs:
                        road = docs[0].get("road_address")
                        addr = docs[0].get("address")
                        mid_address = (road or addr or {}).get("address_name", "중간 지점")
            except Exception:
                pass

        return jsonify({
            "midpoint": {"lat": mid_lat, "lng": mid_lng},
            "address": mid_address,
            "travel_times": travel_times,
        })
    except Exception as e:
        return jsonify({"error": str(e)}), 500


# ── 실시간 위치 공유 ──────────────────────────────────────────

@app.route("/room/<room_id>/location", methods=["POST"])
def update_location(room_id: str):
    data = request.json or {}
    member_name = data.get("member_name", "").strip()
    lat = data.get("lat")
    lng = data.get("lng")
    shared = data.get("shared", True)

    if not member_name:
        return jsonify({"error": "member_name이 필요합니다."}), 400

    try:
        members = sb_select("members", select="id", filters={"room_id": room_id, "name": member_name}, limit=1)
        if not members:
            return jsonify({"error": "멤버를 찾을 수 없습니다."}), 404

        update_data = {"location_shared": shared}
        if shared and lat is not None and lng is not None:
            update_data["current_lat"] = lat
            update_data["current_lng"] = lng
        else:
            update_data["current_lat"] = None
            update_data["current_lng"] = None

        sb_update("members", update_data, {"id": members[0]["id"]})
        return jsonify({"ok": True})
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.route("/room/<room_id>/locations", methods=["GET"])
def get_locations(room_id: str):
    try:
        members = sb_select(
            "members",
            select="name,current_lat,current_lng,location_shared",
            filters={"room_id": room_id},
        )
        locations = [
            {"name": m["name"], "lat": m["current_lat"], "lng": m["current_lng"]}
            for m in members
            if m.get("location_shared") and m.get("current_lat") is not None and m.get("current_lng") is not None
        ]
        return jsonify({"locations": locations})
    except Exception as e:
        return jsonify({"error": str(e)}), 500


if __name__ == "__main__":
    app.run(host='0.0.0.0', debug=True)
