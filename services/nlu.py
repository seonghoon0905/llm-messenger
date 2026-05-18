"""한국어 NLU 서비스 호출 + 규칙 기반 fallback."""
import json
import time
import urllib.request
from typing import List

from config import KOREAN_NLU_BASE_URL

# ── NLU 가용 여부 캐시 ──────────────────────────────────────────────────────
_nlu_available: bool | None = None
_nlu_last_check: float = 0.0
_NLU_RECHECK_INTERVAL = 30.0


def _fetch_json(url: str, payload: dict | None = None, timeout: int = 2) -> dict:
    if payload is None:
        req = urllib.request.Request(url, method="GET")
    else:
        req = urllib.request.Request(
            url,
            data=json.dumps(payload).encode("utf-8"),
            headers={"Content-Type": "application/json"},
            method="POST",
        )
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read().decode("utf-8"))


def is_nlu_available() -> bool:
    global _nlu_available, _nlu_last_check
    now = time.time()
    if _nlu_available is not None and now - _nlu_last_check < _NLU_RECHECK_INTERVAL:
        return _nlu_available
    prev = _nlu_available
    try:
        _fetch_json(f"{KOREAN_NLU_BASE_URL}/health", timeout=1)
        _nlu_available = True
        if prev is not True:
            print(f"[NLU] Available at {KOREAN_NLU_BASE_URL}")
    except Exception as e:
        _nlu_available = False
        if prev is not False:
            print(f"[NLU] Unavailable ({KOREAN_NLU_BASE_URL}): {e}")
    _nlu_last_check = now
    return bool(_nlu_available)


# ── 빈 결과 템플릿 ─────────────────────────────────────────────────────────

def _empty_emotion(source: str = "unavailable") -> dict:
    return {
        "distressScore": 0.0, "angerScore": 0.0,
        "burdenScore": 0.0, "warmthScore": 0.0,
        "neutralScore": 0.0, "topEmotionLabels": [],
        "source": source,
    }


def _empty_speech_act(source: str = "unavailable") -> dict:
    return {"speechAct": "unknown", "source": source}


# ── NLU 서버 호출 ──────────────────────────────────────────────────────────

def get_nlu_emotion(text: str) -> dict:
    if not text.strip() or not is_nlu_available():
        return _empty_emotion()
    try:
        data = _fetch_json(f"{KOREAN_NLU_BASE_URL}/emotion-scores", {"text": text})
        if not isinstance(data.get("distressScore"), (float, int)):
            return _empty_emotion()
        result = _empty_emotion()
        result.update(data)
        result["source"] = "kote" if data.get("source") == "kote" else "unavailable"
        return result
    except Exception as e:
        print(f"[NLU] /emotion-scores error: {e}")
        return _empty_emotion()


def get_nlu_speech_act(text: str) -> dict:
    if not text.strip() or not is_nlu_available():
        return _empty_speech_act()
    try:
        data = _fetch_json(f"{KOREAN_NLU_BASE_URL}/speech-act", {"text": text})
        act = data.get("speechAct", "unknown")
        source = data.get("source", "unavailable")
        return {
            "speechAct": act if isinstance(act, str) else "unknown",
            "source": source if source in ("3i4k",) else "unavailable",
        }
    except Exception as e:
        print(f"[NLU] /speech-act error: {e}")
        return _empty_speech_act()


# ── 규칙 기반 fallback ────────────────────────────────────────────────────

def rule_based_emotion(text: str) -> dict:
    result = _empty_emotion("fallback")
    s = text.strip()
    if not s:
        result["neutralScore"] = 1.0
        result["topEmotionLabels"] = ["neutral"]
        return result

    distress = ["힘들", "불안", "걱정", "무서", "슬퍼", "우울", "지쳤", "속상", "답답"]
    anger    = ["짜증", "화나", "열받", "싫어", "그만", "하지마", "빡", "별로", "어이없"]
    burden   = ["부담", "귀찮", "피곤", "바빠", "못하겠", "번거", "벅차", "가능할까요"]
    warmth   = ["고마워", "감사", "좋아", "괜찮아", "도와", "응원", "수고", "미안", "고생"]
    neutral  = ["알겠", "확인", "오케이", "ㅇㅋ", "그래", "네"]

    def _score(markers: List[str]) -> float:
        return min(1.0, sum(1 for m in markers if m in s) * 0.35)

    result["distressScore"] = max(_score(distress), 0.45 if "힘들" in s else 0.0)
    result["angerScore"]    = max(_score(anger),    0.45 if ("짜증" in s or "하지마" in s) else 0.0)
    result["burdenScore"]   = max(_score(burden),   0.45 if "부담" in s else 0.0)
    result["warmthScore"]   = _score(warmth)

    has_emotion = any(result[k] > 0 for k in ("distressScore", "angerScore", "burdenScore", "warmthScore"))
    result["neutralScore"] = _score(neutral) if has_emotion else max(_score(neutral), 0.55)

    groups = [
        ("distress", result["distressScore"]),
        ("anger",    result["angerScore"]),
        ("burden",   result["burdenScore"]),
        ("warmth",   result["warmthScore"]),
        ("neutral",  result["neutralScore"]),
    ]
    result["topEmotionLabels"] = [
        n for n, v in sorted(groups, key=lambda x: x[1], reverse=True)[:3] if v > 0
    ]
    return result


def rule_based_speech_act(text: str) -> dict:
    s = text.strip()
    if not s:
        return {"speechAct": "statement", "source": "fallback"}
    if any(m in s for m in ["해줘", "보내줘", "확인해줘", "부탁", "요청", "주세요", "해주시", "전달해"]):
        return {"speechAct": "request", "source": "fallback"}
    if any(m in s for m in ["?", "가능", "가능할까요", "해줄", "되나", "할까", "어때", "왜", "언제", "괜찮을까요"]):
        return {"speechAct": "question", "source": "fallback"}
    return {"speechAct": "statement", "source": "fallback"}


# ── 통합 호출 (NLU 우선, fallback 자동) ──────────────────────────────────

def get_emotion_scores(text: str) -> dict:
    result = get_nlu_emotion(text)
    return result if result.get("source") == "kote" else rule_based_emotion(text)


def get_speech_act(text: str) -> dict:
    result = get_nlu_speech_act(text)
    return result if result.get("source") == "3i4k" else rule_based_speech_act(text)


def get_leary_speech_act(text: str) -> dict:
    """Leary 전용: fragment/unknown/statement 반환 시 rule-based 보정."""
    primary = get_speech_act(text)
    if primary.get("speechAct") in ("fragment", "unknown", "statement", "intonation_dependent", None, ""):
        fallback = rule_based_speech_act(text)
        if fallback.get("speechAct") in ("request", "question"):
            return {"speechAct": fallback["speechAct"], "source": f"{primary.get('source')}+fallback"}
    return primary


# ── 격식도 추정 ────────────────────────────────────────────────────────────

def estimate_formal_prob(text: str) -> float:
    s = text.strip()
    if not s:
        return 0.0
    positive = {"습니다": 0.25, "입니다": 0.2, "해요": 0.15, "드려요": 0.2,
                "주세요": 0.2, "드립니다": 0.25, "가능할까요": 0.25,
                "괜찮으실까요": 0.25, "부탁드립니다": 0.3}
    negative = {"해": 0.1, "야": 0.1, "ㅇㅇ": 0.25, "ㄱㄱ": 0.25,
                "몰라": 0.2, "짜증나": 0.3, "싫어": 0.2, "귀찮": 0.25}
    score = 0.5
    for marker, w in positive.items():
        if marker in s:
            score += w
    for marker, w in negative.items():
        if marker in s:
            score -= w
    if s.endswith(("요", "니다", "까요")):
        score += 0.1
    if s.endswith(("야", "네", "ㅋ", "ㅎ")):
        score -= 0.1
    return max(0.0, min(1.0, score))


def safe_score(value) -> float:
    try:
        return max(0.0, min(1.0, float(value)))
    except (TypeError, ValueError):
        return 0.0


def negative_emotion_sum(scores: dict) -> float:
    return (
        safe_score(scores.get("distressScore"))
        + safe_score(scores.get("angerScore"))
        + safe_score(scores.get("burdenScore"))
    )
