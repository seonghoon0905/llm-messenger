<div align="center">

# LLM Messenger

**AI 답장 코칭이 내장된 한국어 메신저 앱**

타이핑을 멈추면 GPT가 자동으로 감정·화행을 분석해 더 나은 답장을 제안합니다.

[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![FastAPI](https://img.shields.io/badge/FastAPI-Python_3.13-009688?logo=fastapi&logoColor=white)](https://fastapi.tiangolo.com)
[![OpenAI](https://img.shields.io/badge/OpenAI-GPT--4o--mini-412991?logo=openai&logoColor=white)](https://openai.com)
[![Korean NLU](https://img.shields.io/badge/Korean_NLU-KOTE_%2B_3i4K-FF6F00)](#한국어-nlu)

[주요 기능](#주요-기능) ·
[빠른 시작](#빠른-시작) ·
[아키텍처](#아키텍처) ·
[API](#api-엔드포인트) ·
[알고리즘](#ai-답장-코칭-알고리즘)

</div>

---

## 소개

LLM Messenger는 **Flutter + FastAPI 기반의 실시간 한국어 채팅 애플리케이션**입니다. 메시지를 작성하는 동안 타이핑을 잠시 멈추면, AI가 다음을 수행합니다.

1. **한국어 NLU**가 상대 메시지의 감정·화행을 분석
2. **ThinGate**가 규칙 기반으로 LLM 호출 필요성을 판단 (불필요 시 차단으로 비용·지연 최소화)
3. 필요 시 **GPT가 답장 초안에 대한 피드백과 rewrite 제안**을 생성

핵심은 **모든 메시지에 GPT를 호출하지 않고, 코칭이 필요한 순간만 식별해 호출**하는 ThinGate 알고리즘에 있습니다.

---

## 주요 기능

| 카테고리 | 기능 |
|---|---|
| **실시간 채팅** | WebSocket 기반 1:1 채팅, 메시지 수정·삭제 실시간 동기화 |
| **AI 답장 코칭** | 타이핑 2초 정지 시 자동 분석, 톤·감정 피드백 + rewrite 제안 |
| **자동 응답 생성** | 상대 메시지 맥락 분석해 답장 초안 자동 생성 |
| **한국어 NLU** | KOTE 감정 분류 (5개 군) + 3i4K 화행 분류 |
| **ThinGate 알고리즘** | 6개 규칙 기반 분석으로 불필요한 LLM 호출 최소화 |
| **성격 분석 리포트** | Leary 대인관계 모델 기반 (주도–순응 / 우호–적대 2축) |
| **친구 관리** | 친구 추가·삭제, 1:1 채팅방 생성 |
| **오프라인 동기화** | 재접속 시 누락된 일반 메시지 자동 동기화 (중복 방지) |

---

## 아키텍처

```
┌──────────────────────────────────────────────────────────────────┐
│                        Flutter Client                            │
│  ┌────────┐  ┌──────────┐  ┌─────────────┐  ┌──────────────┐  │
│  │  Auth  │  │   Chat   │  │  AI Coach   │  │   Analysis   │  │
│  │ Screen │  │  Screen  │  │   Overlay   │  │    Screen    │  │
│  └────────┘  └──────────┘  └─────────────┘  └──────────────┘  │
└────────────────────────────┬─────────────────────────────────────┘
                             │
              ┌──────────────┼──────────────┐
              │ HTTP / REST  │  WebSocket   │
              ▼              ▼              ▼
┌──────────────────────────────────────────────────────────────────┐
│              FastAPI Backend  (port 8000)                        │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌────────────────┐ │
│  │  auth.py │  │friends.py│  │ rooms.py │  │   ws.py         │ │
│  └──────────┘  └──────────┘  └──────────┘  └────────────────┘ │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │  analysis.py - ThinGate + draft 분석 + Leary 분석           │ │
│  └────────────────┬──────────────────────────┬────────────────┘ │
│         ┌─────────┘                          └─────────┐        │
│         ▼                                              ▼        │
│  ┌──────────────┐                          ┌────────────────┐  │
│  │  services/   │                          │  services/     │  │
│  │  nlu.py      │                          │  gpt.py        │  │
│  └──────┬───────┘                          └────────┬───────┘  │
└─────────┼───────────────────────────────────────────┼──────────┘
          │                                           │
          ▼                                           ▼
┌──────────────────────┐                ┌──────────────────────┐
│ Korean NLU Server    │                │     OpenAI API       │
│ (port 8001)          │                │  configured model    │
│  - KOTE  감정 분류    │                │  feedback / rewrite  │
│  - 3i4K  화행 분류    │                │  auto reply          │
└──────────────────────┘                └──────────────────────┘
```

---

## 기술 스택

| 영역 | 기술 |
|---|---|
| **클라이언트** | Flutter (Dart) · sqflite · SharedPreferences |
| **메인 백엔드** | FastAPI · WebSocket · SQLite |
| **NLU 서버** | FastAPI · HuggingFace Transformers · PyTorch |
| **AI 모델** | OpenAI Chat Completions API (기본값 `gpt-4o-mini`, 환경변수로 변경 가능) |
| **한국어 모델** | `tobykim/koelectra-44emotions` (KOTE) · `bespin-global/klue-roberta-small-3i4k-intent-classification` (3i4K) |
| **개발 환경** | Python 3.13 · Dart SDK 3.x |

---

## 빠른 시작

### 사전 요구사항

- Python 3.13 이상
- Flutter SDK 3.x 이상
- OpenAI API Key

### 1. 환경변수 설정

프로젝트 루트에 `.env` 파일을 생성합니다.

```env
OPENAI_API_KEY=your_openai_api_key_here
OPENAI_MODEL=gpt-4o-mini
KOREAN_NLU_BASE_URL=http://localhost:8001
```

### 2. 의존성 설치

```bash
# Python 백엔드
pip install fastapi "uvicorn[standard]" pydantic certifi

# 한국어 NLU 서버
pip install -r korean_nlu/requirements.txt

# Flutter 앱
flutter pub get
```

### 3. 서버 실행 (2개 터미널)

```bash
# Terminal A — 메인 백엔드 (포트 8000)
python3 -m uvicorn main:app --host 127.0.0.1 --port 8000

# Terminal B — 한국어 NLU 서버 (포트 8001)
cd korean_nlu && python3 -m uvicorn main:app --host 0.0.0.0 --port 8001
```

> NLU 서버 없이도 앱은 동작합니다. 다만 감정 분석이 키워드 매칭(fallback)으로 대체되어 정확도가 낮아집니다.

### 4. Flutter 앱 실행

```bash
flutter run
```

> `lib/constants/app_style.dart`의 `baseUrl`은 기본값이 `http://127.0.0.1:8000`입니다. 데스크톱 앱은 같은 컴퓨터에서 서버를 실행하면 연결할 수 있지만, Android 에뮬레이터나 실제 모바일 기기에서는 호스트 컴퓨터의 IP 주소로 변경해야 합니다.

### 5. 서버 상태 확인

```bash
curl http://127.0.0.1:8000/openapi.json  # 메인 서버
curl http://127.0.0.1:8001/health  # NLU 서버
```

---

## 프로젝트 구조

```
llm-messenger/
│
├── main.py                  FastAPI 앱 진입점
├── config.py                환경변수, SSL 설정
├── database.py              DB 연결 및 초기화
├── .env                     환경변수 (직접 생성)
│
├── models/
│   └── schemas.py           Pydantic 요청/응답 모델
│
├── routers/
│   ├── auth.py              로그인, 회원가입, 프로필
│   ├── friends.py           친구 CRUD
│   ├── rooms.py             채팅방 관리
│   ├── analysis.py          AI 분석 API
│   └── ws.py                WebSocket 엔드포인트
│
├── services/
│   ├── nlu.py               NLU 호출 + 규칙 기반 fallback
│   ├── gpt.py               GPT 프롬프트 빌드 및 호출
│   └── analysis.py          ThinGate, draft 분석, Leary 분석
│
├── websocket/
│   └── manager.py           WebSocket 연결 관리
│
├── korean_nlu/              한국어 NLU 서버 (포트 8001)
│   ├── main.py
│   ├── requirements.txt
│   └── models/
│       ├── emotion.py       KOTE 감정 분류
│       └── speech_act.py    3i4K 화행 분류
│
└── lib/                     Flutter 앱 소스
    ├── constants/
    ├── models/
    ├── screens/
    ├── services/
    └── widgets/
```

---

## API 엔드포인트

### 인증·사용자

| Method | Path | 설명 |
|---|---|---|
| `POST` | `/login` | 로그인 |
| `POST` | `/signup` | 회원가입 |
| `DELETE` | `/users/{id}` | 계정 삭제 |
| `GET` | `/users/search/{id}` | 사용자 검색 |
| `POST` | `/users/update_nickname` | 닉네임 변경 |
| `POST` | `/users/update_status` | 상태 메시지 변경 |

### 친구·채팅방

| Method | Path | 설명 |
|---|---|---|
| `GET` | `/users/{id}/friends` | 친구 목록 조회 |
| `POST` | `/friends/add` | 친구 추가 |
| `DELETE` | `/friends/remove` | 친구 삭제 |
| `GET` | `/users/{id}/rooms` | 채팅방 목록 조회 |
| `POST` | `/rooms/direct` | 1:1 채팅방 생성 |
| `GET` | `/rooms/{room_id}/messages` | 전체 또는 `since` 이후 누락 메시지 조회 |

### AI 분석

| Method | Path | 설명 |
|---|---|---|
| `POST` | `/analyze-draft` | 답장 초안 분석 (ThinGate) |
| `POST` | `/llm-assist` | GPT 피드백 및 rewrite 생성 |
| `POST` | `/auto-reply` | 자동 응답 초안 생성 |
| `POST` | `/analyze-leary` | Leary 대인관계 분석 |

### 실시간

| Method | Path | 설명 |
|---|---|---|
| `WS` | `/ws/{user_id}` | WebSocket 연결 |

---

## AI 답장 코칭 알고리즘

타이핑이 2초간 멈추면 자동으로 분석이 시작됩니다.

```
사용자 draft 입력
       │
       ▼
  ┌────────────────────────────────────────┐
  │           POST /analyze-draft          │
  │                                        │
  │  ┌──────────────┐  ┌──────────────┐   │
  │  │ KOTE 감정 분석│  │ 3i4K 화행 분류│   │
  │  └──────┬───────┘  └──────┬───────┘   │
  │         └────────┬────────┘            │
  │                  ▼                     │
  │         ┌─────────────────┐            │
  │         │ ThinGate 6규칙  │            │
  │         │   판단 로직     │            │
  │         └────────┬────────┘            │
  └──────────────────┼─────────────────────┘
                     ▼
        shouldInvokeLlm = ?
         ┌────────────┴────────────┐
         │                         │
       false                     true
   (코칭 불필요)              (코칭 필요)
         │                         │
       종료                        ▼
                  ┌────────────────────────┐
                  │   POST /llm-assist     │
                  │                        │
                  │   GPT 피드백 +         │
                  │   rewrite 생성         │
                  └────────────────────────┘
```

### ThinGate 6가지 규칙

초안과 대화 맥락을 다음 6개 규칙으로 분석합니다.

1. `question_not_answered` - 상대방 질문에 대한 답이 부족함
2. `request_not_addressed` - 상대방 요청 또는 부탁에 대한 반응이 부족함
3. `harsh_expression` - 답장에 차갑거나 강한 표현이 포함됨
4. `emotion_shift_worsened` - 답장으로 감정 톤이 악화될 가능성
5. `distress_dismissive` - 상대가 힘든 상황인데 답장이 무심하게 들릴 수 있음
6. `negative_streak_cold_reply` - 상대방의 부정 감정이 이어지는 상황에서 답장이 짧거나 차가움

자세한 알고리즘 설명은 [보고서_답장코칭알고리즘.md](./보고서_답장코칭알고리즘.md)를 참고하세요.

---

## 한국어 NLU

별도 FastAPI 서버(포트 8001)에서 HuggingFace 모델로 두 가지 분석을 제공합니다.

| 기능 | 모델 | 출력 |
|---|---|---|
| **감정 분류** | `tobykim/koelectra-44emotions` (KOTE 기반) | `distressScore`, `angerScore`, `burdenScore`, `warmthScore`, `neutralScore` (각 0.0~1.0) |
| **화행 분류** | `bespin-global/klue-roberta-small-3i4k-intent-classification` | 모델: `statement`, `question`, `command`, `rhetorical_*`, `fragment`, `intonation_dependent` / fallback: `request` 포함 |

NLU 서버가 비활성 상태일 때는 메인 백엔드가 자동으로 키워드 기반 fallback 규칙으로 전환됩니다 (`services/nlu.py`).

---

## 성격 분석 리포트

채팅 누적 메시지를 기반으로 [Leary 대인관계 모델](https://en.wikipedia.org/wiki/Interpersonal_circle)의 2축으로 사용자를 평가합니다.

- **주도성 (Dominance)**: 5~95 - 화행 분포 + 메시지 길이/수 비율 기반
- **우호성 (Affiliation)**: 5~95 - KOTE 감정 점수 기반

결과는 주도성 3단계(`leading`, `balanced`, `following`)와 우호성 3단계(`friendly`, `neutral`, `hostile`)를 조합한 9개 유형으로 분류됩니다.

자세한 알고리즘은 [보고서_성격분석리포트.md](./보고서_성격분석리포트.md)를 참고하세요.

---

## 라이선스

현재 저장소에는 별도 라이선스 파일이 포함되어 있지 않습니다.
