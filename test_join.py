"""
/room/<room_id>/join 엔드포인트 테스트 스크립트.
실행: python test_join.py <room_id>
      python test_join.py          (room_id를 직접 입력)
"""
import sys
import requests

BASE_URL = "http://localhost:5000"

if len(sys.argv) > 1:
    room_id = sys.argv[1]
else:
    room_id = input("room_id 입력: ").strip()

res = requests.post(
    f"{BASE_URL}/room/{room_id}/join",
    json={
        "name": "남규혁",
        "address": "인천광역시 미추홀구 인하로 100",
        "transport": "transit",
    },
)

print(f"HTTP 상태: {res.status_code}")
print(f"응답: {res.json()}")
