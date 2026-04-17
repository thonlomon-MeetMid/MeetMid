# MeetMid

**N명의 공평한 중간지점 탐색 서비스**

> 여러 사람이 모일 때, 모두에게 공평한 중간지점을 찾아드립니다.

---

## 팀 소개

**팀명:** Thonlomon

| 이름 | 역할 |
|------|------|
| 남규혁 | 팀장 / 백엔드 / AI / 일정관리 |
| 김현 | 외부 API / QA |
| 윤채은 | 프론트엔드 |
| 양동준 | 알고리즘 |

---

## 핵심 기능

### 중간지점 탐색
- **시간 공평** — 모든 참여자의 이동 시간이 최대한 균등한 지점 탐색
- **거리 공평** — 모든 참여자의 이동 거리가 최대한 균등한 지점 탐색
- **다수결 중간** — 참여자들의 선호를 반영한 중간지점 탐색

### 방 시스템
- 방 만들기 / 방 참여 (방장 시스템)
- 각자 출발지 및 이동수단 개별 입력

### 지도 & 위치
- 실시간 위치 공유 (ON/OFF 선택 가능)
- 중간지점 지도 시각화 (Kakao Maps)
- 추천 장소 핀 표시

### AI 장소 추천
- Gemini AI 기반 자연어 장소 추천
  - 예: *"4명이서 재밌게 놀만한 술집"*
- 카카오 로컬 API로 주변 장소 목록 수집 → Gemini가 필터링 및 추천

### 공유
- 결과 링크 카카오톡 공유

---

## 기술 스택

| 분류 | 기술 |
|------|------|
| Frontend | React |
| Backend | FastAPI (Python) |
| AI | Google Gemini API |
| 지도 | Kakao Maps SDK |
| 외부 API | 카카오 로컬 API, 카카오 모빌리티 API, ODsay API |
| 알고리즘 | Weighted Centroid, Isochrone 분석 |

---

## 시작하기

### 요구사항
- Python 3.10+
- Node.js 18+

### 설치

```bash
# 저장소 클론
git clone https://github.com/thonlomon-MeetMid/MeetMid.git
cd MeetMid

# 백엔드 의존성 설치
pip install -r requirements.txt

# 프론트엔드 의존성 설치
cd frontend
npm install
```

### 환경 변수 설정

`.env` 파일을 생성하고 아래 키를 설정하세요:

```env
GEMINI_API_KEY=your_gemini_api_key
KAKAO_REST_API_KEY=your_kakao_rest_api_key
KAKAO_MOBILITY_API_KEY=your_kakao_mobility_api_key
ODSAY_API_KEY=your_odsay_api_key
```

### 실행

```bash
# 백엔드 서버
uvicorn main:app --reload

# 프론트엔드 (별도 터미널)
cd frontend
npm start
```

---

## 라이선스

MIT License
