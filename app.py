from flask import Flask, request, jsonify
from flask_cors import CORS
from dotenv import load_dotenv
import hashlib
import os
import uuid
import sys
import json
import requests

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
    return {"name": m["name"], "address": m["address"], "transport": m["transport"]}


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
            sb_insert("members", {
                "room_id": room_id,
                "user_id": resolved_user_id,
                "name": name,
                "address": address,
                "transport": transport,
            })

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

        mid_lat = sum(m["lat"] for m in located) / len(located)
        mid_lng = sum(m["lng"] for m in located) / len(located)

        travel_times = [
            {"name": m["name"], "minutes": 0, "transport": m["transport"]}
            for m in members
        ]
        return jsonify({
            "midpoint": {"lat": mid_lat, "lng": mid_lng},
            "address": "중간 지점",
            "travel_times": travel_times,
        })
    except Exception as e:
        return jsonify({"error": str(e)}), 500


if __name__ == "__main__":
    app.run(host='0.0.0.0', debug=True)
