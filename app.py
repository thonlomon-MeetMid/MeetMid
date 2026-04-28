from flask import Flask, render_template, request, jsonify, session
from flask_cors import CORS
from google import genai
from google.genai import types
from dotenv import load_dotenv
import os
import re
import uuid
import sys
import json
import requests

load_dotenv()

# PowerShell 터미널이 CP949일 때 print 출력이 깨지는 것을 방지
if sys.platform == "win32":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

app = Flask(__name__)
CORS(app, resources={r"/*": {"origins": "*"}})
app.secret_key = os.getenv("SECRET_KEY", "meetmid-secret-2026")

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
client = genai.Client(api_key=os.getenv("GEMINI_API_KEY"))

# 방 데이터 인메모리 저장소
rooms: dict = {}


def geocode_address(address: str) -> tuple[float, float] | None:
    """카카오 로컬 API로 주소 → (lat, lng) 변환. 실패 시 None 반환."""
    # CP949 바이트가 latin-1로 잘못 해석된 경우 복원 시도
    try:
        address = address.encode("latin-1").decode("cp949")
    except (UnicodeEncodeError, UnicodeDecodeError):
        pass  # 이미 정상 UTF-8 유니코드

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

# 장소 관련 키워드 목록 (필터링용)
PLACE_KEYWORDS = [
    # 위치
    '역', '동', '구', '시', '도', '로', '길', '근처', '주변', '앞', '옆',
    # 장소 유형
    '카페', '식당', '맛집', '술집', '바', '레스토랑', '커피', '이자카야', '포차', '주점',
    '호텔', '모텔', '숙박', '펜션', '게스트하우스',
    '공원', '관광', '명소', '놀이공원', '테마파크',
    '쇼핑', '마트', '백화점', '시장', '쇼핑몰',
    '영화관', '극장', '노래방', '볼링', 'pc방',
    '전시', '미술관', '박물관', '갤러리',
    '헬스장', '사우나', '스파',
    '병원', '약국', '치과',
    # 음식 종류
    '치킨', '피자', '파스타', '중식', '일식', '한식', '분식', '국밥',
    '삼겹살', '고기', '횟집', '해산물', '스시', '라멘', '우동', '떡볶이',
    '순대', '김밥', '비빔밥', '냉면', '탕수육', '짜장', '짬뽕',
    '디저트', '케이크', '아이스크림', '베이커리', '빵집', '도넛',
    '브런치', '샌드위치', '버거', '햄버거',
    # 목적/의도
    '데이트', '여행', '모임', '회식', '소개팅',
    '추천', '코스', '어디', '갈만한', '좋은',
]


def is_valid_query(query: str) -> bool:
    """검색어가 장소 추천 관련 요청인지 판단"""
    q = query.lower()
    return any(kw in q for kw in PLACE_KEYWORDS)


def _sort_by_rating(result_text: str) -> str:
    """별점 높은 순으로 정렬 후 번호 재부여. 별점 동일 시 원래 순서 유지."""
    lines = result_text.strip().splitlines()
    entries = []
    for line in lines:
        m = re.match(r"^\d+\.\s+(.+)$", line)
        if m:
            content = m.group(1)
            rating_m = re.search(r"\|\s*([\d.]+)\s*\|", content)
            rating = float(rating_m.group(1)) if rating_m else 0.0
            entries.append((rating, content))

    if not entries:
        return result_text

    entries.sort(key=lambda x: x[0], reverse=True)
    return "\n".join(f"{i+1}. {content}" for i, (_, content) in enumerate(entries))


@app.route("/")
def index():
    session.clear()
    return render_template("index.html")


@app.route("/recommend", methods=["POST"])
def recommend():
    query = request.json.get("query", "").strip()
    if not query:
        return jsonify({"error": "검색어를 입력해주세요."}), 400

    # 장소 관련 검색어인지 먼저 확인
    if not is_valid_query(query):
        return jsonify({"error": "올바른 검색어를 입력해주세요. (예: 강남역 근처 카페)"}), 200

    # 대화 기록 유지
    history = session.get("history", [])
    history_text = ""
    if history:
        history_text = "이전 대화:\n"
        for h in history[-4:]:  # 최근 4개만
            history_text += f"사용자: {h['query']}\n추천: {h['result']}\n\n"

    prompt = f"""{history_text}사용자가 "{query}"를 검색했습니다.
실제로 존재하고 현재 영업 중인 장소 3곳을 추천해주세요.
가상의 장소, 폐업한 곳, 존재하지 않는 장소는 절대 포함하지 마세요.
이전 대화 맥락이 있다면 참고해서 답변하세요.

반드시 아래 형식으로만 답변하세요. 다른 설명은 일절 하지 마세요:

1. [장소명] | [도로명 주소] | [별점(1.0~5.0)] | [한 줄 설명]
2. [장소명] | [도로명 주소] | [별점(1.0~5.0)] | [한 줄 설명]
3. [장소명] | [도로명 주소] | [별점(1.0~5.0)] | [한 줄 설명]

예시:
1. 이름없는맥주집 안양점 | 경기도 안양시 만안구 안양로 123 | 4.5 | 수제맥주와 다양한 안주가 있는 분위기 좋은 맥줏집"""

    response = client.models.generate_content(
        model="gemini-2.5-flash-lite",
        contents=prompt,
        config=types.GenerateContentConfig(
            tools=[types.Tool(google_search=types.GoogleSearch())]
        )
    )

    result_text = response.text.strip()
    result_text = _sort_by_rating(result_text)

    # 대화 기록 저장
    history.append({"query": query, "result": result_text})
    session["history"] = history

    return jsonify({"result": result_text})


@app.route("/clear", methods=["POST"])
def clear():
    session.clear()
    return jsonify({"ok": True})


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
    if coords is None:
        return jsonify({"error": "주소를 좌표로 변환할 수 없습니다."}), 422

    lat, lng = coords
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

    mid_lat = sum(m["lat"] for m in members) / len(members)
    mid_lng = sum(m["lng"] for m in members) / len(members)

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
