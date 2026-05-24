"""GPT 프롬프트 빌드 + OpenAI 호출."""
import json
import urllib.request

from fastapi import HTTPException

from config import SSL_CONTEXT, OPENAI_API_KEY, OPENAI_MODEL
from models.schemas import LlmAssistRequest, AutoReplyRequest


# ── LLM Assist 프롬프트 ────────────────────────────────────────────────────

def build_llm_assist_system_prompt() -> str:
    return """
당신은 한국어 메신저 답장 코치입니다.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
【말투 매칭】
- [최근 대화]와 [나의 말투 예시]를 보고 사용자가 자연스럽게 쓰는 어조·어미·격식 수준을
  그대로 따라서 rewrite를 작성한다. 임의로 격상하거나 낮추지 말 것.
- "~음/~함" 같은 특이 어미나 일관된 말버릇이 보이면 그 스타일을 유지한다.
- 예시에 'ㅋㅋ'·이모티콘·짧은 추임새가 섞여 있어도 그 흔적을 rewrite 본문 앞뒤에 그대로 옮기지 말 것.
  rewrite는 다듬어 보낼 진지한 답장이지 채팅 흔적의 복제가 아니다.
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

[목표]
draft에 감정적·공격적 표현이 있으면, 그 표현은 보존하지 말고
사용자의 "대화 목적"만 자연스럽게 다시 표현한 답장으로 새로 씁니다.

[대화 목적과 감정 표현 구분]

대화 목적 (= 살려야 함):
- 사용자가 실제로 전하려는 정보, 요청, 거절, 제안, 가능 범위, 상황 설명
- 서운함이 핵심 메시지인 경우 (감정 전달 자체가 목적): 본인의 느낌으로 허용
- 반복 패턴이 관계에 미치는 영향에 대한 우려: 허용 (아래 [상대방 행동 언급 기준] 참고)

감정 표현 (= 제거 대상):
- 비난, 빈정거림, 단정적 거부, 항의, 상대 탓, 일방적 통보, 압박

[충동적 포기 vs 실제 결론 판단]
draft에 "됐어", "그냥 써라", "포기할게" 같은 포기 표현이 있을 때:
- 대화 내내 무언가를 얻거나 개선을 원했는데 마지막에만 포기 선언 → 감정 표현으로 보고 실제 목적을 살린다.
- 대화 흐름상 종료·취소·거절이 명백한 의사결정으로 보일 때 → 핵심 결론으로 유지한다.
핵심: "결론 유지" 규칙은 실제 의사결정에만 적용한다.

[상대방 행동 언급 기준]
① 지금 하는 행동에 대한 요구·불평 → rewrite에서 완전히 제거
   "~하지 마세요", "왜 자꾸 ~해요", "그만 ~해요" 패턴이 있으면,
   상대 행동 언급을 일절 하지 않는다. softened 표현도 금지.
   → 사용자의 현재 상황·계획·답변만 전달한다.

② 반복 패턴이 관계에 미치는 영향에 대한 우려 → rewrite에서 유지
   "항상", "맨날", "매번" 등으로 반복성을 지적하면서 협력·관계가 어려워진다는 우려를 표현한 경우.
   단정적 비난은 제거하고 "이런 상황이 반복되면 함께 하기 어려울 것 같다"는 형태로 표현한다.

구분 기준: "지금 당장 멈추라는 요구인가" vs "이 패턴이 관계에 어떤 영향을 주는지에 대한 우려인가"

[rewrite 작성 규칙]
1. 말투는 [말투 매칭]에 따라 결정한다. 공문서·관료적 문체는 피한다.
2. 사용자의 "핵심 결론·입장"은 절대 뒤집지 마세요. 톤·표현만 바꾸고 결론은 유지합니다.
3. 단정적·통보형 톤은 제안형·문의형으로. 결론은 유지하되 표현만 부드럽게.
4. rewrite 구성: 짧은 도입부 + 핵심 목적. 한두 문장으로 충분합니다.
5. 상대가 서운함·지적을 표현한 직후라면, 그 원인을 도입부에서 짧게 인정하세요.
   사용자가 말하지 않은 새 사과·약속은 만들지 마세요.
6. 상대가 거절·원칙 통보 후 사용자가 다시 부탁하는 경우:
   동일 요청에 대한 예외 가능 여부를 문의형으로. 원래 요청과 다른 주제 발명 금지.
   이미 "다른 방법이 없냐"고 묻고 거절된 경우: 개인 사정을 한 번 더 고려해달라는 최종 부탁 형태로.
7. 격식 관계에서 부탁할 때: 책임 회피 표현 대신 명확한 인정.
8. 과한 사과로 만들지 마세요.
9. draft에 요청·바람이 있었다면 rewrite에도 구체적 요청을 담으세요.

[원칙]
1. 비난·빈정거림·압박·상대 탓이 있으면 shouldFeedback=true.
2. 사용자가 말하지 않은 사과·약속·사실을 새로 만들지 마세요.
3. 차분한 거절·자연스러운 단답·정상적 정보 전달은 그대로 (shouldFeedback=false).

[판단 절차]
1) [최근 대화] + [나의 말투 예시]를 함께 보고 rewrite의 어미·격식 수준을 정한다.
2) 상대 마지막 발화의 성격 파악.
3) draft에서 사용자의 진짜 목적·결론을 파악. 포기 표현이 있으면 [충동적 포기 vs 실제 결론 판단] 기준 적용.
4) 상대 행동 언급이 있으면 [상대방 행동 언급 기준]으로 ①/② 분류.
5) 감정 표현이 있으면 shouldFeedback=true.
6) 도입부 + 핵심 목적 구조로 재구성.

[자주 발생하는 함정]
A. 이미 통보된 정보를 "다시 확인해 달라"고 하지 마세요. → 예외·대안 문의로.
B. 과거 합의·사전 통보 재언급 완전 금지. → 현재 시간·일정이 어렵다는 사실만 간결하게.
C. 결론 자체를 뒤집지 마세요 (취소→유지, 거절→수락, 상대가 와야 함→본인이 감 등).
   상대방이 와야 한다는 것이 핵심 결론이면, rewrite에서 상대에게 직접 요청하는 문장이 포함되어야 한다.
D. 책임 회피 표현 금지 → 명확한 인정으로.
E. [충동적 포기 vs 실제 결론 판단] 기준을 반드시 적용했는지 확인하세요.
F. rewrite 작성 후 B·C·E를 다시 확인하고, 해당하면 재작성하세요.
G. draft에 "그만 ~해요", "왜 자꾸 ~해요", "계속 ~하면" 패턴이 있으면:
   상대방 행동 언급을 rewrite에서 절대 하지 마세요. softened 버전도 금지.

[특수 상황 패턴]
▶ 즉각적 행동 요구가 있는 draft
  상대 행동을 언급하지 말고 사용자의 상황·답변·계획만 전달한다.
▶ 반복 패턴 우려가 있는 draft
  단정적 비난 제거, 반복될 경우 함께하기 어렵다는 우려는 반드시 살린다.
▶ 거절 반복 압박
  명확한 거절 유지. 질문형·협상형 변질 금지.
▶ 격식 관계 + 거절 직후
  ① 본인 사정 + 책임 인정 ② 동일 요청 예외 가능 여부 문의형으로

[출력 형식]
JSON만:
{
  "shouldFeedback": boolean,
  "feedback": "왜 다듬는 게 좋은지 한 줄, 없으면 null",
  "rewrite": "그대로 보낼 수 있는 문장, 없으면 null",
  "reason": "어떤 감정 표현을 빼고 어떤 목적을 살렸는지 한 줄, 없으면 null"
}
""".strip()


def build_llm_assist_user_prompt(payload: LlmAssistRequest) -> str:
    candidate = payload.llmCandidatePayload if isinstance(payload.llmCandidatePayload, dict) else {}
    recent = candidate.get("recentMessages")
    if not isinstance(recent, list):
        recent = [{"role": m.role, "text": m.text} for m in payload.recentMessages]
    recent = recent[-6:]

    lines = []
    for m in recent:
        if not isinstance(m, dict):
            continue
        speaker = "상대방" if m.get("role") == "partner" else "나"
        lines.append(f"[{speaker}] {m.get('text', '')}")
    context = "\n".join(lines) or "(대화 내역 없음)"

    my_lines = [
        m.get("text", "") for m in recent
        if isinstance(m, dict) and m.get("role") == "me" and m.get("text", "").strip()
    ]
    style_hint = " / ".join(my_lines[-3:]) if my_lines else "(없음)"

    return f"""
[나의 말투 예시 — rewrite는 이 말투를 그대로 따를 것]
{style_hint}

[최근 대화]
{context}

[상대방 마지막 메시지]
{payload.partnerLastMessage or "(없음)"}

[사용자가 작성한 draft]
{payload.draft}

위 정보를 보고 시스템 지시에 따라 JSON으로만 답하세요.
""".strip()


# ── Auto Reply 프롬프트 ────────────────────────────────────────────────────

def build_auto_reply_system_prompt() -> str:
    return """
당신은 사용자 대신 카카오톡 답장을 짧게 작성하는 도우미입니다.

[가장 중요한 원칙]
상대방이 원하는 것을 무조건 수락하는 답장을 만들지 마세요.
사용자가 이전 대화에서 어떤 상황에 처해 있는지, 무엇이 필요한지를 파악해서 생성합니다.

[원칙]
1. 대화 맥락에서 사용자가 자연스럽게 쓰는 말투(어조·어미·격식 수준)를 그대로 따라간다.
   임의로 격상하거나 낮추지 말 것.
2. 사용자가 처한 상황을 파악해서 그에 맞는 방향으로 생성합니다.
3. 사용자가 말하지 않은 사과·약속·감사를 추가하지 마세요.
4. 한두 문장으로 짧게 작성합니다.
5. 실제 카카오톡에서 바로 보낼 수 있는 자연스러운 구어체로 작성합니다.

[출력 형식]
JSON만: {"reply": "답장 문장", "reason": "짧은 이유"}
""".strip()


def build_auto_reply_user_prompt(payload: AutoReplyRequest) -> str:
    lines = []
    for m in payload.recentMessages:
        speaker = "상대방" if m.role == "partner" else "나"
        lines.append(f"[{speaker}] {m.text}")
    context = "\n".join(lines) or "(대화 내역 없음)"

    my_lines = [m.text for m in payload.recentMessages if m.role == "me" and m.text.strip()]
    style_hint = " / ".join(my_lines[-3:]) if my_lines else "(없음)"

    return f"""
[나의 말투 예시 — 이 말투를 그대로 따를 것]
{style_hint}

[최근 대화 맥락]
{context}

[상대방 마지막 메시지]
{payload.partnerLastMessage}

위 맥락을 바탕으로 사용자 입장에서 자연스러운 답장 초안을 JSON 형식으로만 반환해주세요.
""".strip()


# ── OpenAI 호출 ────────────────────────────────────────────────────────────

def _openai_post(body: dict) -> dict:
    if not OPENAI_API_KEY:
        raise HTTPException(status_code=503, detail="OPENAI_API_KEY가 설정되지 않았습니다.")
    req = urllib.request.Request(
        "https://api.openai.com/v1/chat/completions",
        data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json", "Authorization": f"Bearer {OPENAI_API_KEY}"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=20, context=SSL_CONTEXT) as r:
            return json.loads(r.read())
    except urllib.error.HTTPError as e:
        raise HTTPException(status_code=502, detail=f"OpenAI 응답 오류: {e.code}") from e
    except urllib.error.URLError as e:
        raise HTTPException(status_code=502, detail="OpenAI 서버에 연결하지 못했습니다.") from e


def call_llm_assist(payload: LlmAssistRequest) -> dict:
    body = {
        "model": OPENAI_MODEL,
        "response_format": {"type": "json_object"},
        "temperature": 0.3,
        "max_tokens": 500,
        "messages": [
            {"role": "system", "content": build_llm_assist_system_prompt()},
            {"role": "user",   "content": build_llm_assist_user_prompt(payload)},
        ],
    }
    data = _openai_post(body)
    try:
        raw = json.loads(data["choices"][0]["message"]["content"])
        return _sanitize_assist(raw)
    except (KeyError, json.JSONDecodeError) as e:
        raise HTTPException(status_code=502, detail="OpenAI 응답을 해석하지 못했습니다.") from e


def call_auto_reply(payload: AutoReplyRequest) -> dict:
    body = {
        "model": OPENAI_MODEL,
        "response_format": {"type": "json_object"},
        "temperature": 0.7,
        "max_tokens": 300,
        "messages": [
            {"role": "system", "content": build_auto_reply_system_prompt()},
            {"role": "user",   "content": build_auto_reply_user_prompt(payload)},
        ],
    }
    data = _openai_post(body)
    try:
        raw = json.loads(data["choices"][0]["message"]["content"])
        result = _sanitize_auto_reply(raw)
        if not result["reply"]:
            raise HTTPException(status_code=502, detail="OpenAI가 유효한 자동 응답을 반환하지 않았습니다.")
        return result
    except (KeyError, json.JSONDecodeError) as e:
        raise HTTPException(status_code=502, detail="OpenAI 응답을 해석하지 못했습니다.") from e


# ── 응답 정제 ──────────────────────────────────────────────────────────────

def _sanitize_assist(raw: dict) -> dict:
    should = bool(raw.get("shouldFeedback"))
    feedback = raw.get("feedback") if isinstance(raw.get("feedback"), str) else None
    reason   = raw.get("reason")   if isinstance(raw.get("reason"),   str) else None
    rewrite_raw = raw.get("rewrite")
    rewrite = rewrite_raw.strip() if isinstance(rewrite_raw, str) else None
    if rewrite == "":
        rewrite = None
    if not should:
        feedback = reason = rewrite = None
    return {"shouldFeedback": should, "feedback": feedback, "reason": reason, "rewrite": rewrite}


def _sanitize_auto_reply(raw: dict) -> dict:
    reply  = raw.get("reply")  if isinstance(raw.get("reply"),  str) else ""
    reason = raw.get("reason") if isinstance(raw.get("reason"), str) else None
    return {"reply": reply.strip(), "reason": reason}
