"""ThinGate 로직 + draft 분석 + Leary 분석."""
from typing import List, Optional, Tuple

from models.schemas import AnalyzeDraftRequest, AssistMessage
from services.nlu import (
    get_emotion_scores, get_speech_act, get_leary_speech_act,
    estimate_formal_prob, negative_emotion_sum, safe_score,
    is_nlu_available,
)
from services.gpt import normalize_register_mode, infer_register_mode


# ── 텍스트 패턴 판별 ──────────────────────────────────────────────────────

def _is_question(text: str) -> bool:
    markers = ["?", "왜", "뭐", "무엇", "어디", "언제", "누구", "어떻게",
               "가능", "되나", "되나요", "할까", "해줄래", "할까요",
               "괜찮을까요", "가능할까요", "맞아"]
    return any(m in text.strip().lower() for m in markers)


def _is_too_short(text: str) -> bool:
    return len(text.strip()) < 4


def _has_harsh_expression(text: str) -> bool:
    patterns = [
        "됐", "싫", "짜증", "몰라", "그만", "안 해", "귀찮", "꺼져", "알아서",
        "개같", "개소리", "ㅈ같", "좆같", "씨발", "시발", "병신", "지랄", "닥쳐",
        "극혐", "멍청", "한심", "어쩌라고", "그래서 뭐", "상관없어",
    ]
    return any(p in text for p in patterns)


def _is_dismissive(text: str) -> bool:
    patterns = [
        "알아서", "어쩌라고", "그건 네가", "나도 몰라", "됐어", "그만해", "귀찮아",
        "그래서 뭐", "상관없어", "나한테 왜", "내가 뭘", "그게 나랑", "그냥 참아",
        "별거 아니네", "그 정도는",
    ]
    return any(p in text for p in patterns)


def _has_distress_words(text: str) -> bool:
    return any(p in text for p in [
        "힘들", "지쳤", "속상", "우울", "불안", "부담", "걱정",
        "짜증나", "답답", "슬프", "슬픈", "슬펐", "괴롭", "괴로",
        "외로", "쓸쓸", "죽고싶", "죽고 싶",
    ])


def _is_invitation(text: str) -> bool:
    return any(p in text for p in ["같이", "함께", "어때", "할래", "할까", "하자", "가자", "먹자", "보자"])


def _is_complaint(text: str) -> bool:
    return any(p in text for p in [
        "왜 그렇게", "기분 나빠", "기분 나쁘", "서운해", "서운했",
        "화났어", "화나", "짜증나", "짜증났", "상처받았", "실망했",
        "실망이야", "왜 그래", "왜 그러는", "너 때문에", "그게 뭐야",
    ])


def _is_simple_exchange(text: str) -> bool:
    return any(p in text for p in [
        "고마워", "감사해", "감사합니다", "ㄱㅅ",
        "수고했어", "수고해", "수고하세요", "수고했습니다",
        "잘 자", "잘자", "안녕히 주무세요", "굿나잇",
        "내일 봐", "나중에 봐", "다음에 봐",
        "확인했어", "확인했습니다", "알겠어", "알겠습니다", "ㅇㅋ",
        "다행이다", "다행이야", "잘됐다", "잘됐네",
    ])


def _looks_like_answer(partner: str, draft: str) -> bool:
    if not _is_question(partner):
        return True
    if _has_harsh_expression(draft) or _is_dismissive(draft):
        return False
    s = draft.strip()
    if s.endswith(("서", "는데", "지만", "고", "며", "니까", "거든")):
        return False
    answer_patterns = [
        "응", "ㅇㅇ", "아니", "아니야", "아니에요",
        "가능", "불가능", "어려워", "어렵", "괜찮", "좋아", "좋아요",
        "안 돼", "안돼", "돼", "될 것", "할게", "할게요", "못", "못 해", "못해",
        "갈게", "갈 수", "못 가", "못가", "할 수 없", "할 수 있",
        "ㄱㄴ", "ㄴㄴ", "맞아", "맞아요", "있어", "없어", "있어요", "없어요",
    ]
    return any(p in s for p in answer_patterns) or len(s) >= 15


# ── ThinGate ──────────────────────────────────────────────────────────────

def is_safe_to_skip(
    partner: str,
    draft: str,
    register_mode: str,
    formal_prob: float,
    partner_speech: dict,
    draft_emotion: dict,
    emotion_shift: dict,
    neg_streak: dict,
    nlu_source: str,
) -> Tuple[bool, List[str], List[str]]:
    """Returns (clearly_safe, safe_skip_reasons, llm_review_reasons)."""
    s_partner = partner.strip()
    s_draft   = draft.strip()
    review: List[str] = []

    act = partner_speech.get("speechAct", "unknown")
    is_q = act == "question" or _is_question(s_partner)
    is_r = act in ["command", "rhetorical_command", "request"] or any(
        m in s_partner for m in ["해줘", "보내줘", "확인해줘", "부탁", "주세요", "해주시", "전달해"]
    )
    is_inv = _is_invitation(s_partner)

    if is_q:   review.append("partner_question")
    if is_r:   review.append("partner_request_or_command")
    if is_inv and not is_r: review.append("partner_invitation_or_proposal")
    if _has_distress_words(s_partner): review.append("partner_distress")
    if _is_complaint(s_partner):       review.append("partner_conflict_or_complaint")
    if _has_harsh_expression(s_draft): review.append("draft_harsh_expression")
    if _is_dismissive(s_draft):        review.append("draft_dismissive")
    if negative_emotion_sum(draft_emotion) >= 0.4: review.append("draft_high_negative_emotion")
    if register_mode == "formal" and formal_prob < 0.5: review.append("formal_mismatch")
    if neg_streak.get("active"):       review.append("negative_emotion_streak_active")
    if emotion_shift.get("direction") == "worsened": review.append("emotion_shift_worsened")

    if review:
        return False, [], review

    if nlu_source in ("fallback", "unavailable") and not _is_simple_exchange(s_partner):
        return False, [], ["not_clearly_safe"]

    reason = "simple_social_exchange" if _is_simple_exchange(s_partner) else "no_risk_signals_nlu_available"
    return True, [reason], []


def build_thin_gate_reasons(
    register_mode: str,
    formal_prob: float,
    partner: str,
    draft: str,
    partner_speech: dict,
    my_speech: dict,
    partner_emotion: dict,
    draft_emotion: dict,
    emotion_shift: dict,
    neg_streak: dict,
) -> List[dict]:
    act     = partner_speech.get("speechAct", "unknown")
    my_act  = my_speech.get("speechAct", "unknown")
    is_q    = act == "question" or _is_question(partner)
    is_cmd  = act in ["command", "rhetorical_command", "request"] or any(
        m in partner for m in ["해줘", "보내줘", "확인해", "부탁", "주세요"]
    )
    too_short      = _is_too_short(draft)
    has_answer     = _looks_like_answer(partner, draft)
    harsh          = _has_harsh_expression(draft)
    dismissive     = _is_dismissive(draft)
    p_neg          = negative_emotion_sum(partner_emotion)
    d_neg          = negative_emotion_sum(draft_emotion)

    return [
        {"id": "formal_mismatch",           "label": "격식체 대화에서 답장이 너무 캐주얼함",        "matched": register_mode == "formal" and formal_prob < 0.5,                                                    "severity": "medium"},
        {"id": "question_not_answered",      "label": "상대방 질문에 대한 답이 부족함",              "matched": is_q and (too_short or not has_answer),                                                             "severity": "high"},
        {"id": "request_not_addressed",      "label": "상대방 요청/부탁에 대한 반응이 부족함",       "matched": is_cmd and (too_short or my_act == "statement" and not has_answer),                                 "severity": "medium"},
        {"id": "harsh_expression",           "label": "답장에 차갑거나 강한 표현이 포함됨",          "matched": harsh or d_neg >= 0.6 or safe_score(draft_emotion.get("angerScore")) >= 0.4,                       "severity": "high"},
        {"id": "emotion_shift_worsened",     "label": "답장으로 감정 톤이 악화될 가능성",            "matched": emotion_shift.get("direction") == "worsened",                                                       "severity": "high"},
        {"id": "distress_dismissive",        "label": "상대가 힘든 상황인데 답장이 무심하게 들릴 수 있음", "matched": (p_neg >= 0.8 or _has_distress_words(partner)) and dismissive,                              "severity": "high"},
        {"id": "negative_streak_cold_reply", "label": "상대방의 부정 감정이 이어지는 상황에서 답장이 짧거나 차가움", "matched": neg_streak.get("active") and (dismissive or harsh or too_short),             "severity": "medium"},
    ]


# ── 감정 shift / streak ────────────────────────────────────────────────────

def detect_emotion_shift(partner_scores: dict, draft_scores: dict) -> dict:
    p_neg  = negative_emotion_sum(partner_scores)
    d_neg  = negative_emotion_sum(draft_scores)
    p_warm = safe_score(partner_scores.get("warmthScore"))
    d_warm = safe_score(draft_scores.get("warmthScore"))
    delta  = round(d_neg - p_neg, 3)

    if (p_warm >= 0.3 and d_neg >= 0.45) or (p_neg >= 0.35 and d_neg > p_neg + 0.25 and d_warm < 0.2):
        return {"direction": "worsened",  "reason": "답장의 부정 감정이 상대방 발화보다 더 강하게 나타납니다.", "scoreDelta": delta}
    if d_warm > p_warm + 0.2 and d_neg + 0.1 < p_neg:
        return {"direction": "improved",  "reason": "답장이 상대방의 감정을 다소 완화하는 방향으로 보입니다.", "scoreDelta": delta}
    return     {"direction": "neutral",   "reason": "뚜렷한 감정 악화 신호는 보이지 않습니다.",            "scoreDelta": delta}


def compute_neg_streak(messages: List[AssistMessage]) -> dict:
    partners = [m for m in messages if m.role == "partner" and m.text.strip()]
    count = 0
    for m in reversed(partners[-5:]):
        if negative_emotion_sum(get_emotion_scores(m.text)) >= 0.35:
            count += 1
        else:
            break
    active = count >= 2
    return {"count": count, "active": active,
            "reason": "최근 상대방의 부정 감정이 이어지고 있습니다." if active else "부정 감정 연속 신호가 뚜렷하지 않습니다."}


# ── draft 분석 메인 ───────────────────────────────────────────────────────

def analyze_draft(payload: AnalyzeDraftRequest) -> dict:
    draft   = payload.draft.strip()
    partner = payload.partnerLastMessage.strip()

    mode = (normalize_register_mode(payload.registerMode)
            if payload.registerMode
            else infer_register_mode(payload.recentMessages, partner))

    formal_prob    = estimate_formal_prob(draft)
    partner_speech = get_speech_act(partner)
    draft_speech   = get_speech_act(draft)
    partner_emo    = get_emotion_scores(partner)
    draft_emo      = get_emotion_scores(draft)
    emo_shift      = detect_emotion_shift(partner_emo, draft_emo)
    neg_streak     = compute_neg_streak(payload.recentMessages)

    sources = [partner_emo.get("source"), draft_emo.get("source"),
               partner_speech.get("source"), draft_speech.get("source")]
    if "kote" in sources or "3i4k" in sources:
        nlu_source = "available"
    elif "fallback" in sources:
        nlu_source = "fallback"
    else:
        nlu_source = "unavailable"

    gate_reasons = build_thin_gate_reasons(
        mode, formal_prob, partner, draft,
        partner_speech, draft_speech,
        partner_emo, draft_emo, emo_shift, neg_streak,
    )

    if not draft:
        should, gate_mode, safe_reasons, review_reasons, msg = (
            False, "safe_skip", ["empty_draft"], [], "초안을 먼저 입력해주세요."
        )
    elif len(draft) < 2:
        should, gate_mode, safe_reasons, review_reasons, msg = (
            False, "safe_skip", ["draft_too_short"], [], "초안이 너무 짧아 아직 큰 문제를 판단하기 어렵습니다."
        )
    else:
        clearly_safe, safe_reasons, review_reasons = is_safe_to_skip(
            partner, draft, mode, formal_prob,
            partner_speech, draft_emo, emo_shift, neg_streak, nlu_source,
        )
        should     = not clearly_safe
        gate_mode  = "safe_skip" if clearly_safe else "llm_review"
        msg        = "표현을 한 번 다듬어보는 편이 좋겠습니다." if should else "큰 문제는 감지되지 않았습니다."

    candidate = {
        "recentMessages": [{"role": m.role, "text": m.text} for m in payload.recentMessages[-6:]],
        "partnerLastMessage": payload.partnerLastMessage,
        "draft": payload.draft,
        "registerMode": mode,
        "formalProb": formal_prob,
        "partnerSpeechAct": partner_speech.get("speechAct", "unknown"),
        "mySpeechAct": draft_speech.get("speechAct", "unknown"),
        "partnerEmotionScores": partner_emo,
        "myDraftEmotionScores": draft_emo,
        "emotionShift": emo_shift,
        "negativeEmotionStreak": neg_streak,
        "thinGateReasons": gate_reasons,
        "llmReviewReasons": review_reasons,
        "gateMode": gate_mode,
    }

    return {
        "registerMode": mode,
        "formalProb": formal_prob,
        "partnerEmotionScores": partner_emo,
        "myDraftEmotionScores": draft_emo,
        "emotionShift": emo_shift,
        "negativeEmotionStreak": neg_streak,
        "partnerSpeechAct": partner_speech.get("speechAct", "unknown"),
        "mySpeechAct": draft_speech.get("speechAct", "unknown"),
        "thinGateReasons": gate_reasons,
        "gateMode": gate_mode,
        "clearlySafeToSkip": not should,
        "safeSkipReasons": safe_reasons,
        "llmReviewReasons": review_reasons,
        "shouldInvokeLlm": should,
        "observedFeatures": {
            "draftLength": len(draft),
            "partnerLooksLikeQuestion": _is_question(partner),
            "draftLooksTooShort": _is_too_short(draft),
            "draftLooksLikeAnswer": _looks_like_answer(partner, draft),
            "containsHarshExpression": _has_harsh_expression(draft),
            "draftLooksDismissive": _is_dismissive(draft),
            "registerMode": mode,
            "formalProb": formal_prob,
            "partnerSpeechAct": partner_speech.get("speechAct", "unknown"),
            "mySpeechAct": draft_speech.get("speechAct", "unknown"),
            "partnerEmotionScores": partner_emo,
            "myDraftEmotionScores": draft_emo,
            "emotionShift": emo_shift,
            "negativeEmotionStreak": neg_streak,
            "nluSource": nlu_source,
        },
        "llmCandidatePayload": candidate,
        "message": msg,
    }


# ── Leary 분석 ────────────────────────────────────────────────────────────

_SPEECH_DOM = {
    "command": 1.0, "rhetorical_command": 1.0,
    "request": 0.5, "question": 0.25,
    "rhetorical_question": 0.15, "intonation_dependent": 0.1,
    "statement": 0.0, "fragment": 0.0, "unknown": 0.0,
}


def _leary_quadrant(dom: float, aff: float) -> str:
    d = "leading" if dom >= 60 else ("following" if dom <= 40 else "balanced")
    a = "friendly" if aff >= 60 else ("hostile"   if aff <= 40 else "neutral")
    return f"{d}-{a}"


def _normalize_leary_source(source: str, kind: str) -> str:
    source = source or "unavailable"
    if kind == "speechAct":
        if source == "3i4k":         return "model"
        if "3i4k" in source:         return "model_assisted"
        if source == "fallback":     return "fallback"
        return "unavailable"
    if source == "kote":             return "model"
    if source == "fallback":         return "fallback"
    return "unavailable"


def _leary_reliability(emo_sources: List[str], act_sources: List[str]) -> dict:
    def _agg(normalized: List[str]) -> str:
        if not normalized:
            return "unavailable"
        n = len(normalized)
        m_n = sum(1 for s in normalized if s == "model")
        a_n = sum(1 for s in normalized if s == "model_assisted")
        if (m_n + a_n) / n >= 0.8:
            return "model" if m_n / n >= 0.8 else "model-assisted"
        if (m_n + a_n) / n >= 0.3:
            return "mixed"
        return "fallback" if sum(1 for s in normalized if s == "fallback") / n >= 0.5 else "unavailable"

    emo_norm = [_normalize_leary_source(s, "emotion")  for s in emo_sources]
    act_norm = [_normalize_leary_source(s, "speechAct") for s in act_sources]
    e_agg, a_agg = _agg(emo_norm), _agg(act_norm)

    def _display(sources: List[str], exact: str) -> str:
        if not sources: return "unavailable"
        n = len(sources)
        ex  = sum(1 for s in sources if s == exact)
        ast = sum(1 for s in sources if exact in s and s != exact)
        fb  = sum(1 for s in sources if s == "fallback")
        if ex / n >= 0.8:         return exact
        if (ex + ast) / n >= 0.3: return f"{exact}+fallback" if ast > 0 else "mixed"
        return "fallback" if fb / n >= 0.5 else "unavailable"

    e_ok = e_agg in ("model", "model-assisted", "mixed")
    a_ok = a_agg in ("model", "model-assisted", "mixed")
    if e_agg == "model" and a_agg == "model":   reliability = "high"
    elif e_ok and a_ok:                          reliability = "medium"
    elif e_ok or a_ok:                           reliability = "medium"
    else:                                        reliability = "low"

    return {
        "reliability": reliability,
        "sources": {
            "emotion":   _display(emo_sources, "kote"),
            "speechAct": _display(act_sources, "3i4k"),
        },
    }


def analyze_leary(messages: List[AssistMessage]) -> dict:
    all_msgs = [m for m in messages if m.text.strip()]
    recent   = all_msgs[-100:]
    my_msgs  = [m for m in recent if m.role == "me"]
    partner_msgs = [m for m in recent if m.role == "partner"]

    if not my_msgs:
        return {
            "dominance": 50.0, "affiliation": 50.0, "quadrant": "balanced-neutral",
            "analyzed_count": len(recent), "my_message_count": 0,
            "partner_message_count": len(partner_msgs), "window_size": 100,
            "reliability": "low", "sources": {"emotion": "unavailable", "speechAct": "unavailable"},
            "signals": {"avgWarmth": 0.0, "avgAnger": 0.0, "avgDistress": 0.0, "avgBurden": 0.0,
                        "harshDismissiveRatio": 0.0, "speechDominance": 0.0, "lengthRatio": 0.5, "countRatio": 0.5},
        }

    n = len(my_msgs)
    warmth_s = anger_s = distress_s = burden_s = 0.0
    emo_sources: List[str] = []
    harsh_count = 0

    for m in my_msgs:
        scores = get_emotion_scores(m.text)
        emo_sources.append(scores.get("source", "unavailable"))
        warmth_s   += safe_score(scores.get("warmthScore"))
        anger_s    += safe_score(scores.get("angerScore"))
        distress_s += safe_score(scores.get("distressScore"))
        burden_s   += safe_score(scores.get("burdenScore"))
        if _has_harsh_expression(m.text) or _is_dismissive(m.text):
            harsh_count += 1

    avg_warmth, avg_anger = warmth_s / n, anger_s / n
    avg_distress, avg_burden = distress_s / n, burden_s / n
    harsh_ratio = harsh_count / n

    affiliation = max(5.0, min(95.0,
        50.0 + avg_warmth * 35 - avg_anger * 35 - avg_burden * 10 - harsh_ratio * 20 - avg_distress * 5
    ))

    speech_dom_sum = 0.0
    act_sources: List[str] = []
    for m in my_msgs:
        speech = get_leary_speech_act(m.text)
        act_sources.append(speech.get("source", "unavailable"))
        speech_dom_sum += _SPEECH_DOM.get(speech.get("speechAct", "unknown"), 0.0)

    speech_dom = speech_dom_sum / n
    avg_my_len = sum(len(m.text) for m in my_msgs) / n
    avg_pt_len = (sum(len(m.text) for m in partner_msgs) / len(partner_msgs)
                  if partner_msgs else avg_my_len)
    total_len  = avg_my_len + avg_pt_len
    length_ratio = avg_my_len / total_len if total_len > 0 else 0.5
    total_count  = len(my_msgs) + len(partner_msgs)
    count_ratio  = len(my_msgs) / total_count if total_count > 0 else 0.5

    dominance = max(5.0, min(95.0,
        50.0 + speech_dom * 30 + (length_ratio - 0.5) * 30 + (count_ratio - 0.5) * 20
    ))

    rel = _leary_reliability(emo_sources, act_sources)
    return {
        "dominance":   round(dominance,   1),
        "affiliation": round(affiliation, 1),
        "quadrant":    _leary_quadrant(dominance, affiliation),
        "analyzed_count": len(recent),
        "my_message_count": n,
        "partner_message_count": len(partner_msgs),
        "window_size": 100,
        "reliability": rel["reliability"],
        "sources":     rel["sources"],
        "signals": {
            "avgWarmth":            round(avg_warmth,    3),
            "avgAnger":             round(avg_anger,     3),
            "avgDistress":          round(avg_distress,  3),
            "avgBurden":            round(avg_burden,    3),
            "harshDismissiveRatio": round(harsh_ratio,   3),
            "speechDominance":      round(speech_dom,    3),
            "lengthRatio":          round(length_ratio,  3),
            "countRatio":           round(count_ratio,   3),
        },
    }
