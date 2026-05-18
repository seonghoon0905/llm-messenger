# LLM Messenger

> AI 답장 코칭 기능이 내장된 한국어 메신저 앱

Flutter + FastAPI 기반의 실시간 채팅 애플리케이션입니다. 사용자가 메시지를 작성하면 타이핑을 멈춘 후 자동으로 AI가 감정·화행을 분석하여 더 나은 답장을 제안합니다.

---

## 주요 기능

- **실시간 채팅** — WebSocket 기반 1:1 및 그룹 채팅
- **AI 자동 피드백** — 타이핑 중단 2초 후 자동으로 답장 코칭 실행 (On/Off 설정 가능)
- **AI 자동 응답 생성** — 상대방 메시지 맥락을 분석해 답장 초안 자동 생성
- **ThinGate 알고리즘** — 규칙 기반 사전 분석으로 불필요한 LLM 호출 최소화
- **한국어 NLU 분석** — KOTE 감정 분류 + 3i4K 화행 분류
- **메시지 수정·삭제 실시간 동기화** — 수정·삭제 이벤트 WebSocket 브로드캐스트
- **성격 분석 리포트** — 대화 기반 Leary 대인관계 모델 분석 (주도–순응 / 우호–적대 2축)
- **친구 관리** — 친구 추가·삭제, 1:1 채팅방 생성

---

## 기술 스택

| 구분 | 기술 |
|---|---|
| 프론트엔드 | Flutter (Dart) |
| 백엔드 | FastAPI (Python) |
| 실시간 통신 | WebSocket |
| 로컬 DB | SQLite (sqflite) |
| AI | OpenAI GPT-4.1 |
| 한국어 NLU | KOTE (감정), 3i4K (화행) |
| 설정 저장 | SharedPreferences |

---

## 프로젝트 구조

```
llm-messenger/
├── main.py                  # FastAPI 앱 진입점
├── config.py                # 환경변수, SSL 설정
├── database.py              # DB 연결 및 초기화
├── .env                     # 환경변수 파일 (직접 생성 필요)
│
├── models/
│   └── schemas.py           # Pydantic 요청/응답 모델
│
├── routers/
│   ├── auth.py              # 로그인, 회원가입, 프로필
│   ├── friends.py           # 친구 CRUD
│   ├── rooms.py             # 채팅방 관리
│   ├── analysis.py          # AI 분석 API
│   └── ws.py                # WebSocket 엔드포인트
│
├── services/
│   ├── nlu.py               # NLU 호출 + 규칙 기반 fallback
│   ├── gpt.py               # GPT 프롬프트 빌드 및 호출
│   └── analysis.py          # ThinGate, draft 분석, Leary 분석
│
├── websocket/
│   └── manager.py           # WebSocket 연결 관리
│
├── korean_nlu/              # 한국어 NLU 서버 (포트 8001)
│   ├── main.py
│   ├── requirements.txt
│   └── models/
│
└── lib/                     # Flutter 앱 소스
    ├── constants/
    ├── models/
    ├── screens/
    ├── services/
    └── widgets/
```

---

## 시작하기

### 1. 환경변수 설정

프로젝트 루트에 `.env` 파일을 생성합니다.

```env
OPENAI_API_KEY=sk-...
OPENAI_MODEL=gpt-4.1
```

### 2. Python 의존성 설치

```bash
pip install fastapi uvicorn websockets pydantic certifi

# NLU 서버 의존성
pip install -r korean_nlu/requirements.txt
```

### 3. Flutter 의존성 설치

```bash
flutter pub get
```

---

## 서버 실행

앱 실행 전에 서버 두 개를 모두 켜야 합니다.

**터미널 A — 메인 백엔드 (포트 8000)**
```bash
python3 -m uvicorn main:app --host 127.0.0.1 --port 8000
```

**터미널 B — 한국어 NLU 서버 (포트 8001)**
```bash
cd korean_nlu
python3 -m uvicorn main:app --host 0.0.0.0 --port 8001
```

> NLU 서버 없이도 앱은 정상 동작합니다. 단, 감정 분석이 키워드 매칭(fallback)으로 대체되어 정확도가 낮아집니다.

**서버 상태 확인**
```bash
curl http://127.0.0.1:8000/       # 메인 서버
curl http://127.0.0.1:8001/health # NLU 서버
```

---

## Flutter 앱 실행

```bash
flutter run
```

> `lib/constants/app_style.dart`의 `baseUrl`이 `http://127.0.0.1:8000`으로 고정되어 있으므로, 앱과 서버는 **같은 기기에서 실행**해야 합니다.

---

## API 엔드포인트

| Method | Path | 설명 |
|---|---|---|
| POST | `/login` | 로그인 |
| POST | `/signup` | 회원가입 |
| DELETE | `/users/{id}` | 계정 삭제 |
| GET | `/users/search/{id}` | 사용자 검색 |
| POST | `/users/update_nickname` | 닉네임 변경 |
| POST | `/users/update_status` | 상태 메시지 변경 |
| GET | `/users/{id}/friends` | 친구 목록 조회 |
| POST | `/friends/add` | 친구 추가 |
| DELETE | `/friends/remove` | 친구 삭제 |
| GET | `/users/{id}/rooms` | 채팅방 목록 조회 |
| POST | `/rooms/direct` | 1:1 채팅방 생성 |
| POST | `/analyze-draft` | 답장 초안 분석 (ThinGate) |
| POST | `/llm-assist` | GPT 피드백 및 rewrite 생성 |
| POST | `/auto-reply` | 자동 응답 초안 생성 |
| POST | `/analyze-leary` | Leary 대인관계 분석 |
| WS | `/ws/{user_id}` | WebSocket 연결 |

---

## AI 답장 코칭 알고리즘

타이핑을 2초 멈추면 자동으로 분석이 시작됩니다.

```
draft 입력
  └─→ /analyze-draft
        ├─ NLU 감정 분석 (KOTE)
        ├─ NLU 화행 분류 (3i4K)
        ├─ ThinGate 판단 (7가지 규칙)
        │    └─ shouldInvokeLlm = false → 피드백 없음 (종료)
        └─→ shouldInvokeLlm = true
              └─→ /llm-assist
                    └─ GPT 피드백 + rewrite 생성
```

자세한 알고리즘 설명은 [`보고서_답장코칭알고리즘.md`](./보고서_답장코칭알고리즘.md)를 참고하세요.

---

## 라이선스

MIT
