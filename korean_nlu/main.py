"""
Korean NLU Service - FastAPI Server
=====================================
Next.js analyze-draft 파이프라인에 실제 모델 추론을 제공합니다.

엔드포인트:
  GET  /health          서비스 헬스 체크
  GET  /emotion-debug   감정 모델 로드 상태 및 오류 진단 (개발용)
  POST /formal-prob     격식도 점수 (0.0 ~ 1.0)
  POST /emotion-scores  KOTE 5개 감정군 스코어
  POST /speech-act      3i4K 화행 분류

실행:
  cd services/korean_nlu
  pip install -r requirements.txt
  uvicorn main:app --host 0.0.0.0 --port 8000

환경변수 (선택):
  EMOTION_MODEL_ID      HuggingFace 감정 분류 모델 ID
                        기본값: tobykim/koelectra-44emotions
  EMOTION_THRESHOLD     감정 레이블 활성화 threshold
                        기본값: 0.6
  FORMAL_MODEL_ID       HuggingFace 격식도 분류 모델 ID
  SPEECH_ACT_MODEL_ID   HuggingFace 3i4K 화행 분류 모델 ID
                        기본값: bespin-global/klue-roberta-small-3i4k-intent-classification
"""

import sys
import logging
from contextlib import asynccontextmanager
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

from models.formal import predict_formal_prob
from models.emotion import predict_emotion_scores, get_load_error
from models.speech_act import predict_speech_act

logging.basicConfig(level=logging.INFO, format="%(levelname)s %(name)s: %(message)s")
logger = logging.getLogger(__name__)


# ──────────────────────────────────────────────────────────────
# Startup: 모델 프리워밍
# 서버 기동 시 즉시 모델 로드를 시도해 오류가 터미널에 즉시 출력되도록 함.
# 이전에는 lazy loading만 있어 첫 요청 시에야 오류를 알 수 있었음.
# ──────────────────────────────────────────────────────────────
@asynccontextmanager
async def lifespan(app: FastAPI):
    logger.info(f"[startup] Python {sys.version}")
    logger.info("[startup] Pre-warming emotion model...")
    # 빈 문자열이 아닌 짧은 텍스트로 실제 모델 로드 트리거
    result = predict_emotion_scores("테스트")
    if result["source"] == "unavailable":
        err = get_load_error()
        logger.error(
            "[startup] Emotion model failed to load. "
            "All /emotion-scores calls will return unavailable. "
            "Check the traceback above. "
            f"Stored error snippet: {str(err)[:200] if err else 'none'}"
        )
    else:
        logger.info("[startup] Emotion model ready.")
    yield


app = FastAPI(title="Korean NLU Service", version="1.0.0", lifespan=lifespan)

# CORS: Next.js 개발 서버 및 배포 도메인 허용
app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:3000", "http://127.0.0.1:3000", "*"],
    allow_methods=["GET", "POST"],
    allow_headers=["Content-Type"],
)


class TextRequest(BaseModel):
    text: str


# ──────────────────────────────────────────────────────────────
# 헬스 체크
# ──────────────────────────────────────────────────────────────
@app.get("/health")
def health():
    return {"status": "ok", "service": "korean_nlu", "version": "1.0.0"}


# ──────────────────────────────────────────────────────────────
# 감정 모델 진단 엔드포인트 (개발/디버깅 전용)
# curl http://localhost:8000/emotion-debug
# ──────────────────────────────────────────────────────────────
@app.get("/emotion-debug")
def emotion_debug():
    """
    감정 모델 로드 상태와 오류 원인을 반환.
    서버 터미널에서 traceback을 확인하는 것이 가장 정확하지만,
    이 엔드포인트로도 저장된 오류 메시지를 확인할 수 있다.
    """
    import os
    err = get_load_error()
    probe = predict_emotion_scores("테스트")
    return {
        "emotionModelId": os.getenv("EMOTION_MODEL_ID", "tobykim/koelectra-44emotions"),
        "modelLoaded": probe["source"] == "kote",
        "probeSource": probe["source"],
        "probeResult": probe,
        "loadError": err,
        "pythonVersion": sys.version,
    }


# ──────────────────────────────────────────────────────────────
# 격식도 분류
# ──────────────────────────────────────────────────────────────
@app.post("/formal-prob")
def formal_prob_endpoint(req: TextRequest):
    """
    격식도 점수 반환.
    Returns: {"formalProb": float}  (0.0=캐주얼, 1.0=격식)
    """
    try:
        prob = predict_formal_prob(req.text)
        return {"formalProb": prob}
    except Exception as e:
        logger.error(f"/formal-prob error: {e}")
        raise


# ──────────────────────────────────────────────────────────────
# KOTE 5개 감정군 스코어
# ──────────────────────────────────────────────────────────────
@app.post("/emotion-scores")
def emotion_scores_endpoint(req: TextRequest):
    """
    KOTE 5개 감정군 스코어 반환.
    Returns: EmotionGroupScores JSON
      {distressScore, angerScore, burdenScore, warmthScore, neutralScore,
       topEmotionLabels, source}
    source: "kote" (정상 추론) | "unavailable" (모델 미가용)
    """
    try:
        scores = predict_emotion_scores(req.text)
        return scores
    except Exception as e:
        logger.error(f"/emotion-scores error: {e}")
        raise


# ──────────────────────────────────────────────────────────────
# 3i4K 화행 분류
# ──────────────────────────────────────────────────────────────
@app.post("/speech-act")
def speech_act_endpoint(req: TextRequest):
    """
    3i4K 화행 분류 반환.
    Returns: {"speechAct": string, "source": "3i4k" | "unavailable"}
    """
    try:
        result = predict_speech_act(req.text)
        return result
    except Exception as e:
        logger.error(f"/speech-act error: {e}")
        raise
