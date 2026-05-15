"""
KOTE 44감정 분류 모델 (emotion.py)

실제 모델: tobykim/koelectra-44emotions
  - Base: monologg/koelectra-base-v3-discriminator
  - Task: Multi-label classification (sigmoid, threshold=0.6)
  - Dataset: searle-j/kote + 추가 수집 데이터
  - Output: LABEL_0 ~ LABEL_43 → 아래 KOTE_ORDERED_LABELS 순서로 매핑

감정군 매핑 (koteEmotionGroups.ts와 동일, 정책 엔진 설계 그룹):
  distress / anger / burden / warmth / neutral

source 필드:
  "kote"        - tobykim/koelectra-44emotions 실제 추론
  "unavailable" - 모델 로드 실패 또는 추론 오류 (키워드 대체 없음)
"""

import os
import logging
import traceback
from typing import Dict, List, Optional

logger = logging.getLogger(__name__)

EMOTION_MODEL_ID = os.getenv("EMOTION_MODEL_ID", "tobykim/koelectra-44emotions")

# ──────────────────────────────────────────────────────────────
# KOTE 44 레이블 순서 (tobykim README 기준, LABEL_N 인덱스와 1:1 대응)
# ──────────────────────────────────────────────────────────────
KOTE_ORDERED_LABELS: List[str] = [
    "불평/불만",        # 0
    "환영/호의",        # 1
    "감동/감탄",        # 2
    "지긋지긋",         # 3
    "고마움",           # 4
    "슬픔",             # 5
    "화남/분노",        # 6
    "존경",             # 7
    "기대감",           # 8
    "우쭐댐/무시함",    # 9
    "안타까움/실망",    # 10
    "비장함",           # 11
    "의심/불신",        # 12
    "뿌듯함",           # 13
    "편안/쾌적",        # 14
    "신기함/관심",      # 15
    "아껴주는",         # 16
    "부끄러움",         # 17
    "공포/무서움",      # 18
    "절망",             # 19
    "한심함",           # 20
    "역겨움/징그러움",  # 21
    "짜증",             # 22
    "어이없음",         # 23
    "없음",             # 24
    "패배/자기혐오",    # 25
    "귀찮음",           # 26
    "힘듦/지침",        # 27
    "즐거움/신남",      # 28
    "깨달음",           # 29
    "죄책감",           # 30
    "증오/혐오",        # 31
    "흐뭇함(귀여움/예쁨)", # 32
    "당황/난처",        # 33
    "경악",             # 34
    "부담/안_내킴",     # 35
    "서러움",           # 36
    "재미없음",         # 37
    "불쌍함/연민",      # 38
    "놀람",             # 39
    "행복",             # 40
    "불안/걱정",        # 41
    "기쁨",             # 42
    "안심/신뢰",        # 43
]

# ──────────────────────────────────────────────────────────────
# KOTE 44-label → 5개 감정군 매핑 (koteEmotionGroups.ts와 동일)
# ──────────────────────────────────────────────────────────────
KOTE_44_TO_GROUP: Dict[str, str] = {
    # distress (13)
    "슬픔": "distress",
    "안타까움/실망": "distress",
    "공포/무서움": "distress",
    "절망": "distress",
    "패배/자기혐오": "distress",
    "힘듦/지침": "distress",
    "당황/난처": "distress",
    "서러움": "distress",
    "불쌍함/연민": "distress",
    "불안/걱정": "distress",
    "죄책감": "distress",
    "경악": "distress",
    "놀람": "distress",
    # anger (10)
    "불평/불만": "anger",
    "화남/분노": "anger",
    "우쭐댐/무시함": "anger",
    "의심/불신": "anger",
    "한심함": "anger",
    "역겨움/징그러움": "anger",
    "짜증": "anger",
    "어이없음": "anger",
    "증오/혐오": "anger",
    "지긋지긋": "anger",
    # burden (3)
    "귀찮음": "burden",
    "부담/안_내킴": "burden",
    "재미없음": "burden",
    # warmth (15)
    "환영/호의": "warmth",
    "감동/감탄": "warmth",
    "고마움": "warmth",
    "존경": "warmth",
    "기대감": "warmth",
    "뿌듯함": "warmth",
    "편안/쾌적": "warmth",
    "신기함/관심": "warmth",
    "아껴주는": "warmth",
    "즐거움/신남": "warmth",
    "깨달음": "warmth",
    "흐뭇함(귀여움/예쁨)": "warmth",
    "행복": "warmth",
    "기쁨": "warmth",
    "안심/신뢰": "warmth",
    # neutral (3)
    "없음": "neutral",
    "부끄러움": "neutral",
    "비장함": "neutral",
}

# ──────────────────────────────────────────────────────────────
# Lazy model loading
# ──────────────────────────────────────────────────────────────
_pipeline = None
_model_loaded: bool = False
_load_error: Optional[str] = None   # 로드 실패 시 오류 메시지 보존

# tobykim 모델 권장 threshold (README 기준)
_THRESHOLD = float(os.getenv("EMOTION_THRESHOLD", "0.6"))


def get_load_error() -> Optional[str]:
    """외부(디버그 엔드포인트 등)에서 로드 오류 원인을 조회할 수 있도록 공개."""
    return _load_error


def _load_model() -> None:
    global _pipeline, _model_loaded, _load_error

    if _model_loaded:
        return

    # NOTE: _model_loaded를 try 성공 이후에 True로 설정.
    # 이전 코드에서는 try 이전에 True로 설정해 예외 발생 시 영구적으로
    # 재시도 없이 None이 유지됐음. 현재 코드는 성공 시에만 True로 설정해
    # 다음 요청에서 재시도를 허용한다(의도적 재시도 허용 설계).
    try:
        from transformers import pipeline as hf_pipeline
        logger.info(f"[emotion] Loading model: {EMOTION_MODEL_ID}")

        _pipeline = hf_pipeline(
            "text-classification",
            model=EMOTION_MODEL_ID,
            top_k=None,       # 모든 44개 레이블 점수 반환 (transformers >= 4.30)
            truncation=True,
            max_length=128,
        )

        _model_loaded = True  # 성공 시에만 True
        _load_error = None
        logger.info(f"[emotion] Model loaded successfully. threshold={_THRESHOLD}")

    except Exception:
        # logger.exception → full traceback이 서버 터미널에 출력됨.
        # 이전 코드는 logger.warning(f"... ({e})") 로 str(e)만 출력해
        # 원인 파악이 불가능했음.
        full_tb = traceback.format_exc()
        _load_error = full_tb
        logger.error(
            f"[emotion] CRITICAL: Model load FAILED for '{EMOTION_MODEL_ID}'.\n"
            f"All /emotion-scores calls will return source='unavailable' until server restart.\n"
            f"Full traceback:\n{full_tb}"
        )
        _pipeline = None
        # _model_loaded는 False로 유지 → 다음 요청에서 재시도 가능


# ──────────────────────────────────────────────────────────────
# 모델 출력 → 5개 감정군 집계
# ──────────────────────────────────────────────────────────────
def _label_name(raw_label: str) -> str:
    """
    LABEL_N → 실제 KOTE 감정 이름.
    모델이 숫자 인덱스 레이블을 반환하는 경우 KOTE_ORDERED_LABELS로 역매핑.
    """
    if raw_label.startswith("LABEL_"):
        try:
            idx = int(raw_label.split("_")[1])
            return KOTE_ORDERED_LABELS[idx]
        except (IndexError, ValueError):
            return raw_label
    return raw_label  # 이미 이름 형태면 그대로


def _model_to_groups(results: List[Dict]) -> Dict:
    """
    pipeline(top_k=None) 출력 → 5개 감정군 스코어.
    Multi-label sigmoid 모델이므로 threshold 이상만 활성으로 처리.
    """
    group_scores: Dict[str, float] = {
        "distress": 0.0, "anger": 0.0, "burden": 0.0,
        "warmth": 0.0, "neutral": 0.0,
    }

    active: List[Dict] = []
    for item in results:
        kote_name = _label_name(item["label"])
        score: float = item["score"]
        group = KOTE_44_TO_GROUP.get(kote_name)
        if group:
            group_scores[group] += score
            if score >= _THRESHOLD:
                active.append({"label": kote_name, "score": score})

    # 아무 레이블도 threshold 초과하지 않으면 최고 점수 레이블 하나를 활성으로 처리
    if not active and results:
        best = max(results, key=lambda x: x["score"])
        best_name = _label_name(best["label"])
        active.append({"label": best_name, "score": best["score"]})

    # 정규화
    total = sum(group_scores.values())
    if total > 0:
        group_scores = {k: v / total for k, v in group_scores.items()}

    # topEmotionLabels: threshold 초과 레이블 이름 (점수 내림차순, 최대 3개)
    top_labels = [
        item["label"]
        for item in sorted(active, key=lambda x: x["score"], reverse=True)[:3]
    ] or ["없음"]

    return _make_result(
        group_scores["distress"], group_scores["anger"], group_scores["burden"],
        group_scores["warmth"], group_scores["neutral"], top_labels, source="kote",
    )


# ──────────────────────────────────────────────────────────────
# 결과 조립
# ──────────────────────────────────────────────────────────────
def _make_result(d, a, b, w, n, labels, source: str) -> Dict:
    return {
        "distressScore": round(d, 3),
        "angerScore": round(a, 3),
        "burdenScore": round(b, 3),
        "warmthScore": round(w, 3),
        "neutralScore": round(n, 3),
        "topEmotionLabels": labels,
        "source": source,
    }


def _make_unavailable() -> Dict:
    """모델 미가용 상태. 모든 점수 0, source='unavailable'."""
    return _make_result(0.0, 0.0, 0.0, 0.0, 0.0, [], source="unavailable")


# ──────────────────────────────────────────────────────────────
# Public API
# ──────────────────────────────────────────────────────────────
def predict_emotion_scores(text: str) -> Dict:
    """
    KOTE 5개 감정군 스코어 예측 (tobykim/koelectra-44emotions).

    모델이 미가용(로드 실패, 추론 오류)인 경우:
      → source='unavailable' 반환. 키워드 대체 없음.
    """
    if not text or not text.strip():
        # 빈 텍스트 = 분석 대상 없음 → neutral 확정, 모델 불필요
        return _make_result(0.0, 0.0, 0.0, 0.0, 1.0, ["없음"], source="kote")

    _load_model()

    if _pipeline is None:
        logger.warning(
            "[emotion] Model not loaded (load_error=%s). Returning unavailable.",
            "see server logs" if _load_error else "unknown",
        )
        return _make_unavailable()

    try:
        raw = _pipeline(text)
        # top_k=None → [[{label,score},...]] or [{label,score},...]
        items: List[Dict] = raw[0] if (raw and isinstance(raw[0], list)) else raw
        return _model_to_groups(items)
    except Exception:
        logger.exception("[emotion] Inference FAILED for input text. Returning unavailable.")
        return _make_unavailable()
