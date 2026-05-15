"""
3i4K 화행 분류 모델 (speech_act.py)

실제 모델: bespin-global/klue-roberta-small-3i4k-intent-classification
  - Base: KLUE-RoBERTa-small
  - Task: 7-class classification (softmax)
  - Dataset: 3i4K (Cho et al. 2019)
  - 실제 출력 레이블 (확인됨):
      'fragment'
      'statement'
      'question'
      'command'
      'rhetorical question'         → rhetorical_question
      'rhetorical command'          → rhetorical_command
      'intonation-dependent utterance' → intonation_dependent

source 필드:
  "3i4k"        - bespin-global 실제 추론
  "unavailable" - 모델 로드 실패 또는 추론 오류 (휴리스틱 대체 없음)
"""

import os
import logging
from typing import Dict

logger = logging.getLogger(__name__)

SPEECH_ACT_MODEL_ID = os.getenv(
    "SPEECH_ACT_MODEL_ID",
    "bespin-global/klue-roberta-small-3i4k-intent-classification",
)

_pipeline = None
_model_loaded = False


def _load_model() -> None:
    global _pipeline, _model_loaded
    if _model_loaded:
        return
    _model_loaded = True
    if not SPEECH_ACT_MODEL_ID:
        return
    try:
        from transformers import pipeline as hf_pipeline
        logger.info(f"[speech_act] Loading: {SPEECH_ACT_MODEL_ID}")
        _pipeline = hf_pipeline(
            "text-classification",
            model=SPEECH_ACT_MODEL_ID,
            truncation=True,
            max_length=512,
        )
        logger.info("[speech_act] Loaded.")
    except Exception as e:
        logger.warning(f"[speech_act] Load failed ({e}). Returning unavailable (no heuristic fallback).")
        _pipeline = None


# ──────────────────────────────────────────────────────────────
# bespin-global 레이블 → SpeechAct 정규화 테이블
# (실제 model output 레이블 확인 후 하드코딩)
# ──────────────────────────────────────────────────────────────
_LABEL_TO_SPEECH_ACT = {
    "fragment": "fragment",
    "statement": "statement",
    "question": "question",
    "command": "command",
    "rhetorical question": "rhetorical_question",
    "rhetorical command": "rhetorical_command",
    "intonation-dependent utterance": "intonation_dependent",
    # 방어적 별칭
    "intonation-dependent": "intonation_dependent",
    "intonation dependent utterance": "intonation_dependent",
    "intonation dependent": "intonation_dependent",
    "rhetorical_question": "rhetorical_question",
    "rhetorical_command": "rhetorical_command",
}

_VALID_SPEECH_ACTS = {
    "fragment", "statement", "question", "command",
    "rhetorical_question", "rhetorical_command",
    "intonation_dependent", "unknown",
}


def _normalize_label(label: str) -> str:
    """bespin-global 모델 레이블 → SpeechAct enum 값."""
    # 직접 매핑
    mapped = _LABEL_TO_SPEECH_ACT.get(label) or _LABEL_TO_SPEECH_ACT.get(label.lower())
    if mapped:
        return mapped
    # 이미 정규화된 값
    normed = label.lower().replace("-", "_").replace(" ", "_")
    if normed in _VALID_SPEECH_ACTS:
        return normed
    # 서브스트링 추론
    if "rhetorical" in normed and "command" in normed:
        return "rhetorical_command"
    if "rhetorical" in normed:
        return "rhetorical_question"
    if "question" in normed:
        return "question"
    if "command" in normed:
        return "command"
    if "statement" in normed:
        return "statement"
    if "fragment" in normed:
        return "fragment"
    if "intonation" in normed:
        return "intonation_dependent"
    return "unknown"


def _make_unavailable() -> Dict:
    """모델 미가용 상태. speechAct='unknown', source='unavailable'."""
    return {"speechAct": "unknown", "source": "unavailable"}


# ──────────────────────────────────────────────────────────────
# Public API
# ──────────────────────────────────────────────────────────────
def predict_speech_act(text: str) -> Dict:
    """
    3i4K 화행 분류.

    Returns: {"speechAct": str, "source": "3i4k" | "unavailable"}

    모델이 미가용(로드 실패, 추론 오류)인 경우:
      → source='unavailable', speechAct='unknown' 반환. 휴리스틱 대체 없음.
    """
    if not text or not text.strip():
        return {"speechAct": "unknown", "source": "3i4k"}

    _load_model()

    if _pipeline is None:
        logger.warning("[speech_act] Model not loaded. Returning unavailable (no heuristic fallback).")
        return _make_unavailable()

    try:
        result = _pipeline(text)
        # top_k=1(default) → [{"label":..., "score":...}] or [[...]]
        item = result[0] if isinstance(result[0], dict) else result[0][0]
        act = _normalize_label(item["label"])
        return {"speechAct": act, "source": "3i4k"}
    except Exception as e:
        logger.warning(f"[speech_act] Inference failed ({e}). Returning unavailable.")
        return _make_unavailable()
