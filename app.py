from flask import Flask, request, jsonify
from flask_cors import CORS
from dotenv import load_dotenv
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

# 방 데이터 인메모리 저장소
rooms: dict = {}


def geocode_address(address: str) -> tuple[float, float] | None:
    """카카오 로컬 API로 주소 → (lat, lng) 변환. 실패 시 None 반환."""
    try:
        address = address.encode("latin-1").decode("cp949")
    except (UnicodeEncodeError, UnicodeDecodeError):
        pass

    kakao_key = os.getenv("KAKAO_API_KEY")
    print(f"[DEBUG] geocode_address 호출됨")
    print(f"[DEBUG]   입력 주소: {repr(address)}")
    print(f"[DEBUG]   KAKAO_API_KEY: {kakao_key[:6]}...{kakao_key[-4:] if kakao_key else 'None'}")
    if not kakao_key:
        print("[DEBUG]   오류: KAKAO_API_KEY 없음")
        return None
    try:
        resp = requests.get(
            "https://dapi.kakao.com/v2/local/search/address.json",
            params={"query": address},
            headers={"Authorization": f"KakaoAK {kakao_key}"},
            timeout=5,
        )
        print(f"[DEBUG]   HTTP 상태: {resp.status_code}")
        print(f"[DEBUG]   응답 본문: {resp.text[:500]}")
        resp.raise_for_status()
        docs = resp.json().get("documents", [])
        print(f"[DEBUG]   documents 개수: {len(docs)}")
        if not docs:
            print(f"[DEBUG]   결과 없음 → None 반환")
            return None
        print(f"[DEBUG]   첫 번째 결과: {docs[0]}")
        return float(docs[0]["y"]), float(docs[0]["x"])  # (lat, lng)
    except requests.exceptions.HTTPError as e:
        print(f"[DEBUG]   HTTP 오류: {e}")
        return None
    except requests.exceptions.RequestException as e:
        print(f"[DEBUG]   요청 실패: {e}")
        return None


@app.route("/rooms", methods=["GET"])
def get_rooms():
    result = [
        {
            "room_id": room_id,
            "room_name": room_data["room_name"],
            "members": room_data["members"],
        }
        for room_id, room_data in rooms.items()
    ]
    return jsonify({"rooms": result})


@app.route("/room", methods=["POST"])
def create_room():
    data = request.json or {}
    room_name = data.get("room_name", "").strip()
    if not room_name:
        return jsonify({"error": "room_name이 필요합니다."}), 400

    room_id = uuid.uuid4().hex[:6]
    rooms[room_id] = {"room_name": room_name, "members": []}
    return jsonify({"room_id": room_id, "room_name": room_name, "members": []})


@app.route("/room/<room_id>/join", methods=["POST"])
def join_room(room_id: str):
    if room_id not in rooms:
        return jsonify({"error": "존재하지 않는 방입니다."}), 404

    raw = request.data
    try:
        data = json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError):
        try:
            data = json.loads(raw.decode("cp949"))
        except Exception:
            data = {}
    print(f"[DEBUG] /join 요청 수신: {data}")
    name = data.get("name", "").strip()
    address = data.get("address", "").strip()
    transport = data.get("transport", "transit")
    print(f"[DEBUG]   name={repr(name)}, address={repr(address)}, transport={repr(transport)}")

    if not name or not address:
        return jsonify({"error": "name과 address가 필요합니다."}), 400

    coords = geocode_address(address)
    print(f"[DEBUG]   geocode 결과: {coords}")
    lat, lng = coords if coords else (None, None)

    member = {"name": name, "address": address, "lat": lat, "lng": lng, "transport": transport}
    rooms[room_id]["members"].append(member)

    return jsonify({"ok": True, "members": rooms[room_id]["members"]})


@app.route("/midpoint/<room_id>", methods=["GET"])
def get_midpoint(room_id: str):
    if room_id not in rooms:
        return jsonify({"error": "존재하지 않는 방입니다."}), 404

    members = rooms[room_id]["members"]
    if not members:
        return jsonify({"error": "멤버가 없습니다."}), 400

    located = [m for m in members if m["lat"] is not None and m["lng"] is not None]
    if not located:
        return jsonify({"error": "좌표를 확인할 수 있는 멤버가 없습니다."}), 400

    mid_lat = sum(m["lat"] for m in located) / len(located)
    mid_lng = sum(m["lng"] for m in located) / len(located)

    # TODO: 카카오 모빌리티 API로 실제 이동 시간 계산
    travel_times = [
        {"name": m["name"], "minutes": 0, "transport": m["transport"]}
        for m in members
    ]

    return jsonify({
        "midpoint": {"lat": mid_lat, "lng": mid_lng},
        "address": "중간 지점",
        "travel_times": travel_times,
    })


if __name__ == "__main__":
    app.run(host='0.0.0.0', debug=True)
