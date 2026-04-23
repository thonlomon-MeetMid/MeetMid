"""
카카오 로컬 API 및 .env 로드 검증 테스트.
실행: python test_kakao.py
"""
import os
import sys
from unittest.mock import patch, MagicMock

from dotenv import load_dotenv

load_dotenv()


# ── 1. .env 로드 확인 ──────────────────────────────────────────────
def test_env_loaded():
    key = os.getenv("KAKAO_API_KEY")
    assert key, "KAKAO_API_KEY가 .env에서 로드되지 않았습니다."
    assert not key.startswith(" "), "KAKAO_API_KEY 값 앞에 공백이 있습니다."
    assert not key.endswith(" "), "KAKAO_API_KEY 값 뒤에 공백이 있습니다."
    print(f"[PASS] KAKAO_API_KEY 로드됨: {key[:6]}...{key[-4:]}")


# ── 2. geocode_address — 정상 응답 ────────────────────────────────
def test_geocode_success():
    fake_response = MagicMock()
    fake_response.status_code = 200
    fake_response.text = '{"documents":[{"x":"127.027","y":"37.497"}]}'
    fake_response.json.return_value = {"documents": [{"x": "127.027", "y": "37.497"}]}
    fake_response.raise_for_status = MagicMock()

    with patch("requests.get", return_value=fake_response):
        # app 모듈을 직접 임포트해서 함수 호출
        import app as flask_app
        result = flask_app.geocode_address("서울 강남구 테헤란로 123")

    assert result is not None, "정상 응답인데 None 반환"
    lat, lng = result
    assert abs(lat - 37.497) < 0.001
    assert abs(lng - 127.027) < 0.001
    print(f"[PASS] 좌표 변환 성공: lat={lat}, lng={lng}")


# ── 3. geocode_address — 빈 documents (주소 불일치) ───────────────
def test_geocode_empty_docs():
    fake_response = MagicMock()
    fake_response.status_code = 200
    fake_response.text = '{"documents":[]}'
    fake_response.json.return_value = {"documents": []}
    fake_response.raise_for_status = MagicMock()

    with patch("requests.get", return_value=fake_response):
        import app as flask_app
        result = flask_app.geocode_address("존재하지않는주소12345")

    assert result is None, "빈 documents인데 None이 아님"
    print("[PASS] 빈 결과 → None 반환 정상")


# ── 4. geocode_address — HTTP 401 (키 오류) ───────────────────────
def test_geocode_http_error():
    import requests as req

    fake_response = MagicMock()
    fake_response.status_code = 401
    fake_response.raise_for_status.side_effect = req.exceptions.HTTPError("401 Unauthorized")

    with patch("requests.get", return_value=fake_response):
        import app as flask_app
        result = flask_app.geocode_address("서울 강남구")

    assert result is None, "HTTP 오류인데 None이 아님"
    print("[PASS] HTTP 오류 → None 반환 정상 (예외 누출 없음)")


# ── 5. 실제 API 호출 (선택적, 네트워크 필요) ──────────────────────
def test_geocode_real_api():
    key = os.getenv("KAKAO_API_KEY")
    if not key:
        print("[SKIP] KAKAO_API_KEY 없음 — 실제 API 테스트 건너뜀")
        return

    import app as flask_app
    result = flask_app.geocode_address("서울특별시 강남구 테헤란로 152")
    if result is None:
        print("[WARN] 실제 API 결과 없음 — 키 권한 또는 주소 형식 확인 필요")
        print("       카카오 개발자 콘솔에서 'Local API' 활성화 여부를 확인하세요.")
    else:
        lat, lng = result
        print(f"[PASS] 실제 API 좌표 변환 성공: lat={lat}, lng={lng}")


if __name__ == "__main__":
    tests = [
        test_env_loaded,
        test_geocode_success,
        test_geocode_empty_docs,
        test_geocode_http_error,
        test_geocode_real_api,
    ]
    failed = 0
    for t in tests:
        try:
            t()
        except Exception as e:
            print(f"[FAIL] {t.__name__}: {e}")
            failed += 1

    print(f"\n{'='*40}")
    print(f"결과: {len(tests) - failed}/{len(tests)} 통과")
    sys.exit(1 if failed else 0)
