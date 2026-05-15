"""
격식도 분류 모델 (formal.py)

실제 모델: j5ng/kcbert-formal-classifier
  - Base: beomi/kcbert-base
  - Task: Binary classification (single_label, softmax)
  - Dataset: SmileStyle + AI허브 감성 대화 말뭉치
  - Labels:
      LABEL_0 = 반말(informal/casual)  → formalProb = 1 - score
      LABEL_1 = 존댓말(formal)          → formalProb = score

formalProb: 0.0(완전 캐주얼) ~ 1.0(완전 격식)
"""

import os
import logging

logger = logging.getLogger(__name__)

FORMAL_MODEL_ID = os.getenv("FORMAL_MODEL_ID", "j5ng/kcbert-formal-classifier")

_pipeline = None
_model_loaded = False


def _load_model() -> None:
    global _pipeline, _model_loaded
    if _model_loaded:
        return
    _model_loaded = True
    if not FORMAL_MODEL_ID:
        return
    try:
        from transformers import pipeline as hf_pipeline
        logger.info(f"[formal] Loading: {FORMAL_MODEL_ID}")
        # top_k=2: 두 레이블 모두 확보 (binary classifier)
        _pipeline = hf_pipeline(
            "text-classification",
            model=FORMAL_MODEL_ID,
            top_k=2,
            truncation=True,
            max_length=300,  # kcbert-base max_position_embeddings=300
        )
        logger.info("[formal] Loaded.")
    except Exception as e:
        logger.warning(f"[formal] Load failed ({e}). Using heuristic fallback.")
        _pipeline = None


# ──────────────────────────────────────────────────────────────
# 모델 출력 → formalProb 추출
# LABEL_0 = informal → formalProb = 1 - score
# LABEL_1 = formal   → formalProb = score
# ──────────────────────────────────────────────────────────────
def _extract_formal_prob(results) -> float:
    """
    top_k=2 결과 [{"label": "LABEL_0/1", "score": float}, ...]에서
    formal 레이블(LABEL_1) score를 formalProb으로 반환.
    """
    for r in results:
        if r["label"] == "LABEL_1":
            return round(float(r["score"]), 3)
    # LABEL_1을 찾지 못한 경우 (레이블 명 다른 경우) - top label로 판단
    top = results[0]
    label = top["label"].lower()
    score = float(top["score"])
    if any(x in label for x in ["formal", "존댓", "label_1", "1"]):
        return round(score, 3)
    return round(1.0 - score, 3)


# ──────────────────────────────────────────────────────────────
# 향상된 한국어 격식도 휴리스틱 (모델 로드 실패 시 fallback)
# ──────────────────────────────────────────────────────────────
import re
from typing import List, Tuple

_FORMAL_PATTERNS: List[Tuple[str, int]] = [
    (r"습니다", 2), (r"입니다", 2), (r"십시오", 2), (r"겠습니다", 2),
    (r"드립니다", 2), (r"합니다", 2), (r"있습니다", 2), (r"없습니다", 2),
    (r"어요", 1), (r"아요", 1), (r"네요", 1), (r"죠", 1),
    (r"할게요", 1), (r"할까요", 1), (r"인가요", 1), (r"은가요", 1),
    (r"여쭤", 2), (r"여쭙", 2), (r"드리", 1), (r"께서", 1), (r"께\b", 1),
]
_CASUAL_PATTERNS: List[Tuple[str, int]] = [
    (r"냐\b", 2), (r"니\b", 2), (r"거든\b", 2), (r"잖아\b", 2),
    (r"ㄴ데\b", 1), (r"는데\b", 1), (r"ㄹ게\b", 1),
    (r"어\b", 1), (r"아\b", 1), (r"야\b", 1), (r"지\b", 1),
    (r"다\b", 1), (r"자\b", 1), (r"대\b", 1),
    (r"ㅋ", 1), (r"ㅎ", 1), (r"ㅠ", 1), (r"ㅜ", 1),
]
_HONORIFIC_TITLES = ["교수님", "선생님", "선배님", "부장님", "과장님", "대표님"]


def _heuristic(text: str) -> float:
    fs, cs = 0, 0
    for pat, w in _FORMAL_PATTERNS:
        if re.search(pat, text):
            fs += w
    for pat, w in _CASUAL_PATTERNS:
        if re.search(pat, text):
            cs += w
    if any(t in text for t in _HONORIFIC_TITLES):
        fs += 2
    total = fs + cs
    return round(fs / total, 3) if total else 0.5


# ──────────────────────────────────────────────────────────────
# Public API
# ──────────────────────────────────────────────────────────────
def predict_formal_prob(text: str) -> float:
    """격식도 점수 예측. 0.0(캐주얼) ~ 1.0(격식)."""
    if not text or not text.strip():
        return 0.5

    _load_model()

    if _pipeline is not None:
        try:
            raw = _pipeline(text)
            # top_k=2 → [[{label,score}, {label,score}]] or [{...}, {...}]
            results = raw[0] if (raw and isinstance(raw[0], list)) else raw
            return _extract_formal_prob(results)
        except Exception as e:
            logger.warning(f"[formal] Inference failed ({e}), using heuristic")

    return _heuristic(text)
