# Korean NLU Service

Next.js `analyze-draft` 파이프라인에 실제 모델 추론을 제공하는 FastAPI 서비스.

## 아키텍처

```
Next.js (/api/analyze-draft)
    └── nluClient.ts (HTTP 요청, 2s 타임아웃, stub fallback)
            └── Korean NLU Service (FastAPI, port 8000)
                    ├── /formal-prob   → models/formal.py
                    ├── /emotion-scores → models/emotion.py
                    └── /speech-act    → models/speech_act.py
```

## 모델 구성

| 엔드포인트 | 모델 | 환경변수 | Fallback |
|-----------|------|---------|---------|
| `/formal-prob` | 없음(휴리스틱) | `FORMAL_MODEL_ID` | 향상된 어미 패턴 |
| `/emotion-scores` | `hun3359/klue-bert-base-sentiment` | `EMOTION_MODEL_ID` | 키워드 휴리스틱 |
| `/speech-act` | 없음(휴리스틱) | `SPEECH_ACT_MODEL_ID` | 향상된 패턴 매칭 |

모든 모델은 **lazy loading** 방식으로, 처음 요청 시에만 다운로드/로드됩니다.
모델 로드 실패 시 자동으로 fallback 휴리스틱을 사용합니다.

## 로컬 실행

```bash
cd services/korean_nlu

# 가상환경 생성 (권장)
python -m venv .venv
source .venv/bin/activate  # Windows: .venv\Scripts\activate

# 의존성 설치
pip install -r requirements.txt

# 서버 실행 (기본 포트 8000)
uvicorn main:app --host 0.0.0.0 --port 8000 --reload
```

## 환경변수

| 변수명 | 기본값 | 설명 |
|-------|--------|------|
| `EMOTION_MODEL_ID` | `hun3359/klue-bert-base-sentiment` | HuggingFace 감정 분류 모델 |
| `FORMAL_MODEL_ID` | `` (비어있음) | 격식도 모델 (비어있으면 휴리스틱) |
| `SPEECH_ACT_MODEL_ID` | `` (비어있음) | 화행 모델 (비어있으면 휴리스틱) |

```bash
# 예시: 실제 KOTE 44-class 모델 사용 시
EMOTION_MODEL_ID=your-kote-44-class-model uvicorn main:app --port 8000
```

## Next.js 연결

`src/lib/analyzer/v1/nluClient.ts`의 `NLU_SERVICE_URL`이 이 서비스의 주소입니다.
`.env.local`에 설정:

```env
KOREAN_NLU_URL=http://localhost:8000
```

## 로컬 개발 vs 배포 차이

| 환경 | NLU 서비스 | 동작 |
|------|-----------|------|
| 로컬 개발 | 별도 실행 (`uvicorn main:app`) | 실제 모델 또는 휴리스틱 |
| Vercel/CDN 배포 | 미실행 상태 | nluClient fallback stub 자동 사용 |
| 전체 배포 | Railway/Fly.io 등에 별도 배포 | 환경변수 `KOREAN_NLU_URL` 설정 필요 |

## API 명세

### GET /health
```json
{"status": "ok", "service": "korean_nlu", "version": "1.0.0"}
```

### POST /formal-prob
**Request:** `{"text": "안녕하세요 교수님"}`
**Response:** `{"formalProb": 0.85}`

### POST /emotion-scores
**Request:** `{"text": "정말 힘들고 불안해"}`
**Response:**
```json
{
  "distressScore": 0.75,
  "angerScore": 0.1,
  "burdenScore": 0.05,
  "warmthScore": 0.0,
  "neutralScore": 0.1,
  "topEmotionLabels": ["슬픔", "공포"]
}
```

### POST /speech-act
**Request:** `{"text": "이거 언제까지 해줄 수 있어요?"}`
**Response:** `{"speechAct": "question"}`
