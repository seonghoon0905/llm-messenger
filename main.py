from fastapi import FastAPI, WebSocket, WebSocketDisconnect, HTTPException
from pydantic import BaseModel
from typing import List, Dict
import sqlite3
import json
import os
import re
import urllib.request
import urllib.error

app = FastAPI()

def get_db():
    conn = sqlite3.connect("auth_server.db")
    conn.row_factory = sqlite3.Row
    return conn

def init_db():
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS rooms (
            room_id TEXT PRIMARY KEY,
            title TEXT,
            relation TEXT
        )
    """)
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS room_members (
            room_id TEXT,
            user_id TEXT,
            PRIMARY KEY(room_id, user_id)
        )
    """)
    conn.commit()
    conn.close()

init_db()

# Pydantic Models
class User(BaseModel):
    username: str
    password: str

# WebSocket Connection Manager
class ConnectionManager:
    def __init__(self):
        self.active_connections: Dict[str, WebSocket] = {}

    async def connect(self, user_id: str, websocket: WebSocket):
        await websocket.accept()
        self.active_connections[user_id] = websocket
        print(f"Connected: {user_id}")

    def disconnect(self, user_id: str):
        if user_id in self.active_connections:
            del self.active_connections[user_id]
            print(f"Disconnected: {user_id}")

    async def send_personal_message(self, message: dict, user_id: str):
        if user_id in self.active_connections:
            await self.active_connections[user_id].send_json(message)

manager = ConnectionManager()

# WebSocket Endpoints
@app.websocket("/ws/{user_id}")
async def websocket_endpoint(websocket: WebSocket, user_id: str):
    await manager.connect(user_id, websocket)
    try:
        while True:
            data = await websocket.receive_json()
            
            # Invite logic
            if data.get("type") == "INVITE":
                room_id = data.get("room_id")
                room_title = data.get("room_title")
                relation = data.get("relation")
                invitee_id = data.get("invitee_id")
                
                # Save room and add member
                conn = get_db()
                cursor = conn.cursor()
                try:
                    # Create room if not exists
                    cursor.execute(
                        "INSERT OR IGNORE INTO rooms (room_id, title, relation) VALUES (?, ?, ?)",
                        (room_id, room_title, relation)
                    )
                    # Add invitee
                    cursor.execute(
                        "INSERT OR IGNORE INTO room_members (room_id, user_id) VALUES (?, ?)",
                        (room_id, invitee_id)
                    )
                    # Add inviter
                    cursor.execute(
                        "INSERT OR IGNORE INTO room_members (room_id, user_id) VALUES (?, ?)",
                        (room_id, user_id)
                    )
                    conn.commit()
                except Exception as e:
                    print(f"DB Error: {e}")
                finally:
                    conn.close()

                # Send invite event to invitee
                invite_packet = {
                    "type": "INVITE_EVENT",
                    "room_id": room_id,
                    "inviter_id": user_id,
                    "room_title": room_title,
                    "relation": relation,
                    "timestamp": data.get("timestamp")
                }
                
                if invitee_id in manager.active_connections:
                    await manager.send_personal_message(invite_packet, invitee_id)
                    print(f"Invite: {user_id} -> {invitee_id} ({room_title}, {relation})")
                continue

            # Message logic
            room_id = data.get("receiver_id")
            content = data.get("content")
            
            conn = get_db()
            cursor = conn.cursor()
            
            cursor.execute("SELECT nickname FROM users WHERE user_id = ?", (user_id,))
            sender_row = cursor.fetchone()
            sender_nickname = sender_row["nickname"] if sender_row and sender_row["nickname"] else user_id

            message_packet = {
                "room_id": room_id,
                "sender_id": user_id,
                "sender_nickname": sender_nickname,
                "content": content,
                "timestamp": data.get("timestamp")
            }
            
            cursor.execute("SELECT user_id FROM room_members WHERE room_id = ?", (room_id,))
            members = cursor.fetchall()
            conn.close()

            for member in members:
                member_id = member["user_id"]
                if member_id != user_id and member_id in manager.active_connections:
                    await manager.send_personal_message(message_packet, member_id)
                    print(f"Message: {user_id} -> {member_id} (Room: {room_id}): {content}")

    except WebSocketDisconnect:
        manager.disconnect(user_id)
    except Exception as e:
        print(f"WebSocket Error: {e}")
        manager.disconnect(user_id)

# API: User Rooms
@app.get("/users/{user_id}/rooms")
async def get_user_rooms(user_id: str):
    conn = get_db()
    cursor = conn.cursor()
    # Fetch rooms user belongs to
    query = """
        SELECT r.room_id, r.title, r.relation 
        FROM rooms r
        JOIN room_members rm ON r.room_id = rm.room_id
        WHERE rm.user_id = ?
    """
    cursor.execute(query, (user_id,))
    rooms = [dict(row) for row in cursor.fetchall()]
    conn.close()
    return {"success": True, "rooms": rooms}



@app.post("/login")
async def login(user: User):
    conn = get_db()
    cursor = conn.cursor()
    # Check user in DB
    cursor.execute(
        "SELECT user_id, nickname, status_message FROM users WHERE user_id = ? AND password = ?", 
        (user.username, user.password)
    )
    result = cursor.fetchone()
    conn.close()
    
    if result:
        return {
            "success": True, 
            "user_id": result["user_id"], 
            "nickname": result["nickname"] if result["nickname"] else result["user_id"],
            "status_message": result["status_message"]
        }
    else:
        # Auth failed
        raise HTTPException(status_code=401, detail="인증 실패")

@app.get("/users/search/{search_id}")
async def search_user(search_id: str):
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute(
        "SELECT user_id, nickname FROM users WHERE user_id = ?", 
        (search_id,)
    )
    result = cursor.fetchone()
    conn.close()
    
    if result:
        return {
            "success": True, 
            "user_id": result["user_id"], 
            "nickname": result["nickname"] if result["nickname"] else result["user_id"]
        }
    else:
        return {"success": False, "message": "해당 아이디의 사용자를 찾을 수 없습니다."}

class UpdateNicknameRequest(BaseModel):
    user_id: str
    nickname: str

@app.post("/users/update_nickname")
async def update_nickname(req: UpdateNicknameRequest):
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute("UPDATE users SET nickname = ? WHERE user_id = ?", (req.nickname, req.user_id))
    conn.commit()
    conn.close()
    return {"success": True}

class UpdateStatusRequest(BaseModel):
    user_id: str
    status_message: str


class AssistMessage(BaseModel):
    role: str
    text: str


class LlmAssistRequest(BaseModel):
    recentMessages: List[AssistMessage]
    partnerLastMessage: str
    draft: str


class AutoReplyRequest(BaseModel):
    recentMessages: List[AssistMessage]
    partnerLastMessage: str


class AnalyzeDraftRequest(BaseModel):
    recentMessages: List[AssistMessage]
    partnerLastMessage: str
    draft: str


def _build_llm_assist_system_prompt() -> str:
    return """
당신은 사용자의 한국어 메신저 답장을 다듬는 실용적인 코칭 도우미입니다.
반드시 최근 대화 맥락과 상대방의 마지막 발화를 함께 보고 판단하십시오.

목표:
- 현재 draft가 상대방 마지막 말에 제대로 반응하는지 판단합니다.
- 현재 draft가 너무 차갑거나 무례하거나 애매하거나 관계상 부적절한지 판단합니다.
- 상대방이 질문했는데 답을 피하거나 놓치고 있는지도 판단합니다.
- 피드백이 필요하면 짧은 코칭 메시지와 이유, 그리고 실제로 보낼 수 있는 더 자연스러운 rewrite 1개를 제안합니다.
- 피드백이 필요 없으면 shouldFeedback=false로 반환합니다.

원칙:
- 사용자의 의도는 유지하되 표현만 더 자연스럽게 정리합니다.
- 상대방의 마지막 발화에 직접 반응하는 답장을 우선합니다.
- 지나치게 교과서적이거나 상담체인 표현은 피합니다.
- rewrite는 실제 메신저에서 바로 보낼 수 있는 짧고 자연스러운 한국어로 작성합니다.
- JSON 외 다른 텍스트는 출력하지 않습니다.

응답 JSON 형식:
{
  "shouldFeedback": boolean,
  "feedback": "코칭 메시지 또는 null",
  "reason": "간단한 이유 또는 null",
  "rewrite": "추천 답장 또는 null"
}
""".strip()


def _build_llm_assist_user_prompt(payload: LlmAssistRequest) -> str:
    context_lines = []
    for message in payload.recentMessages:
        speaker = "상대방" if message.role == "partner" else "나"
        context_lines.append(f"[{speaker}] {message.text}")
    context_text = "\n".join(context_lines) if context_lines else "(대화 내역 없음)"

    return f"""
[최근 대화 맥락]
{context_text}

[상대방 마지막 메시지]
{payload.partnerLastMessage or "(없음)"}

[현재 draft]
{payload.draft}

판단 기준:
1. draft가 상대방의 마지막 메시지에 실제로 반응하는가
2. 말투가 차갑거나 무례하거나 지나치게 짧아 오해를 부를 수 있는가
3. 상대방이 질문했는데 draft가 답을 하지 못하고 있는가
4. 더 자연스럽고 덜 상처 주는 rewrite가 필요한가

위 내용을 바탕으로 지정된 JSON 형식으로만 답변해주세요.
""".strip()


def _sanitize_assist_response(raw: dict) -> dict:
    should_feedback = bool(raw.get("shouldFeedback"))
    feedback = raw.get("feedback") if isinstance(raw.get("feedback"), str) else None
    reason = raw.get("reason") if isinstance(raw.get("reason"), str) else None
    rewrite = raw.get("rewrite") if isinstance(raw.get("rewrite"), str) else None

    if not should_feedback:
        feedback = None
        reason = None
        rewrite = None

    return {
        "shouldFeedback": should_feedback,
        "feedback": feedback,
        "reason": reason,
        "rewrite": rewrite,
    }


def _sanitize_auto_reply_response(raw: dict) -> dict:
    reply = raw.get("reply") if isinstance(raw.get("reply"), str) else ""
    reason = raw.get("reason") if isinstance(raw.get("reason"), str) else None
    return {
        "reply": reply.strip(),
        "reason": reason,
    }


def _looks_like_question(text: str) -> bool:
    question_markers = [
        "?",
        "왜",
        "뭐",
        "무엇",
        "어디",
        "언제",
        "누구",
        "어떻게",
        "가능",
        "돼",
        "되나",
        "할까",
        "해줄래",
        "있어",
        "맞아",
    ]
    lowered = text.strip().lower()
    return any(marker in lowered for marker in question_markers)


def _looks_too_short(text: str) -> bool:
    return len(text.strip()) < 4


def _contains_harsh_expression(text: str) -> bool:
    harsh_patterns = [
        "됐",
        "싫",
        "짜증",
        "몰라",
        "그만",
        "안 해",
        "귀찮",
        "꺼져",
        "알아서",
    ]
    return any(pattern in text for pattern in harsh_patterns)


def _contains_distress_words(text: str) -> bool:
    distress_patterns = [
        "힘들",
        "지쳤",
        "속상",
        "우울",
        "불안",
        "부담",
        "걱정",
        "짜증나",
        "답답",
    ]
    return any(pattern in text for pattern in distress_patterns)


def _is_dismissive(text: str) -> bool:
    dismissive_patterns = [
        "알아서",
        "어쩌라고",
        "그건 네가",
        "나도 몰라",
        "됐어",
        "그만해",
        "귀찮아",
    ]
    return any(pattern in text for pattern in dismissive_patterns)


def _looks_like_answer(partner_last_message: str, draft: str) -> bool:
    if not _looks_like_question(partner_last_message):
        return True
    answer_patterns = [
        "응",
        "아니",
        "가능",
        "어려워",
        "괜찮",
        "좋아",
        "안 돼",
        "돼",
        "할게",
        "못",
    ]
    if any(pattern in draft for pattern in answer_patterns):
        return True
    return len(draft.strip()) >= 8 and not _contains_harsh_expression(draft)


_nlu_service_available = None
_nlu_last_check_time = 0.0
_nlu_recheck_interval = 30.0


def _get_nlu_base_url() -> str:
    return os.getenv("KOREAN_NLU_BASE_URL", "http://localhost:8001")


def _nlu_unavailable_emotion() -> dict:
    return {
        "distressScore": 0.0,
        "angerScore": 0.0,
        "burdenScore": 0.0,
        "warmthScore": 0.0,
        "neutralScore": 0.0,
        "topEmotionLabels": [],
        "source": "unavailable",
    }


def _nlu_unavailable_speech_act() -> dict:
    return {
        "speechAct": "unknown",
        "source": "unavailable",
    }


def _fetch_json(url: str, payload: dict = None, timeout: int = 2):
    if payload is None:
        req = urllib.request.Request(url, method="GET")
    else:
        req = urllib.request.Request(
            url,
            data=json.dumps(payload).encode("utf-8"),
            headers={"Content-Type": "application/json"},
            method="POST",
        )
    with urllib.request.urlopen(req, timeout=timeout) as response:
        return json.loads(response.read().decode("utf-8"))


def _is_nlu_service_available() -> bool:
    global _nlu_service_available, _nlu_last_check_time
    if _nlu_service_available is True:
        return True
    if _nlu_service_available is False:
        import time
        if time.time() - _nlu_last_check_time < _nlu_recheck_interval:
            return False
    try:
        _fetch_json(f"{_get_nlu_base_url()}/health", timeout=1)
        _nlu_service_available = True
    except Exception:
        _nlu_service_available = False
    import time
    _nlu_last_check_time = time.time()
    return bool(_nlu_service_available)


def _get_nlu_speech_act(text: str) -> dict:
    if not text.strip() or not _is_nlu_service_available():
        return _nlu_unavailable_speech_act()
    try:
        data = _fetch_json(
            f"{_get_nlu_base_url()}/speech-act",
            {"text": text},
            timeout=2,
        )
        act = data.get("speechAct", "unknown")
        source = data.get("source", "unavailable")
        return {
            "speechAct": act if isinstance(act, str) else "unknown",
            "source": source if source in ["3i4k", "unavailable"] else "unavailable",
        }
    except Exception:
        return _nlu_unavailable_speech_act()


def _get_nlu_emotion(text: str) -> dict:
    if not text.strip() or not _is_nlu_service_available():
        return _nlu_unavailable_emotion()
    try:
        data = _fetch_json(
            f"{_get_nlu_base_url()}/emotion-scores",
            {"text": text},
            timeout=2,
        )
        if not isinstance(data.get("distressScore"), (float, int)):
            return _nlu_unavailable_emotion()
        normalized = _nlu_unavailable_emotion()
        normalized.update(data)
        normalized["source"] = "kote" if data.get("source") == "kote" else "unavailable"
        return normalized
    except Exception:
        return _nlu_unavailable_emotion()


def _build_auto_reply_system_prompt() -> str:
    return """
당신은 사용자의 카카오톡 답장 초안을 작성하는 도우미입니다.
최근 대화 맥락과 상대방의 마지막 발화를 보고, 사용자 입장에서 자연스럽고 짧은 답장 초안 하나를 생성합니다.

원칙:
- 상대방의 마지막 메시지에 직접 반응해야 합니다.
- 실제 메신저에서 바로 보낼 수 있는 한국어 문장으로 작성합니다.
- 질문이면 답하거나 자연스럽게 보류합니다.
- 요청이나 부탁이면 수락, 보류, 거절 중 맥락상 자연스러운 방향으로 답합니다.
- 감정 표현이면 짧은 공감이나 반응을 우선합니다.
- JSON 외 다른 텍스트는 출력하지 않습니다.

응답 JSON 형식:
{
  "reply": "생성된 답장 초안",
  "reason": "짧은 생성 이유"
}
""".strip()


def _build_auto_reply_user_prompt(payload: AutoReplyRequest) -> str:
    context_lines = []
    for message in payload.recentMessages:
      speaker = "상대방" if message.role == "partner" else "나"
      context_lines.append(f"[{speaker}] {message.text}")
    context_text = "\n".join(context_lines) if context_lines else "(대화 내역 없음)"

    return f"""
[최근 대화 맥락]
{context_text}

[상대방 마지막 메시지]
{payload.partnerLastMessage}

위 맥락을 바탕으로 사용자 입장에서 자연스러운 답장 초안 하나를 JSON 형식으로만 반환해주세요.
""".strip()


def _call_openai_llm_assist(payload: LlmAssistRequest) -> dict:
    api_key = os.getenv("OPENAI_API_KEY")
    if not api_key:
        raise HTTPException(
            status_code=503,
            detail="OPENAI_API_KEY가 설정되지 않아 AI 피드백을 사용할 수 없습니다."
        )

    model_name = os.getenv("OPENAI_MODEL", "gpt-4o-mini")
    request_body = {
        "model": model_name,
        "response_format": {"type": "json_object"},
        "temperature": 0.5,
        "max_tokens": 500,
        "messages": [
            {"role": "system", "content": _build_llm_assist_system_prompt()},
            {"role": "user", "content": _build_llm_assist_user_prompt(payload)},
        ],
    }

    req = urllib.request.Request(
        "https://api.openai.com/v1/chat/completions",
        data=json.dumps(request_body).encode("utf-8"),
        headers={
            "Content-Type": "application/json",
            "Authorization": f"Bearer {api_key}",
        },
        method="POST",
    )

    try:
        with urllib.request.urlopen(req, timeout=20) as response:
            data = json.loads(response.read().decode("utf-8"))
            content = data["choices"][0]["message"]["content"]
            parsed = json.loads(content)
            return _sanitize_assist_response(parsed)
    except urllib.error.HTTPError as exc:
        raise HTTPException(
            status_code=502,
            detail=f"OpenAI 응답 오류: {exc.code}"
        ) from exc
    except urllib.error.URLError as exc:
        raise HTTPException(
            status_code=502,
            detail="OpenAI 서버에 연결하지 못했습니다."
        ) from exc
    except (KeyError, json.JSONDecodeError) as exc:
        raise HTTPException(
            status_code=502,
            detail="OpenAI 응답을 해석하지 못했습니다."
        ) from exc


def _call_openai_auto_reply(payload: AutoReplyRequest) -> dict:
    api_key = os.getenv("OPENAI_API_KEY")
    if not api_key:
        raise HTTPException(
            status_code=503,
            detail="OPENAI_API_KEY가 설정되지 않아 자동 응답 생성을 사용할 수 없습니다."
        )

    model_name = os.getenv("OPENAI_MODEL", "gpt-4o-mini")
    request_body = {
        "model": model_name,
        "response_format": {"type": "json_object"},
        "temperature": 0.7,
        "max_tokens": 300,
        "messages": [
            {"role": "system", "content": _build_auto_reply_system_prompt()},
            {"role": "user", "content": _build_auto_reply_user_prompt(payload)},
        ],
    }

    req = urllib.request.Request(
        "https://api.openai.com/v1/chat/completions",
        data=json.dumps(request_body).encode("utf-8"),
        headers={
            "Content-Type": "application/json",
            "Authorization": f"Bearer {api_key}",
        },
        method="POST",
    )

    try:
        with urllib.request.urlopen(req, timeout=20) as response:
            data = json.loads(response.read().decode("utf-8"))
            content = data["choices"][0]["message"]["content"]
            parsed = json.loads(content)
            result = _sanitize_auto_reply_response(parsed)
            if not result["reply"]:
                raise HTTPException(
                    status_code=502,
                    detail="OpenAI가 유효한 자동 응답을 반환하지 않았습니다."
                )
            return result
    except urllib.error.HTTPError as exc:
        raise HTTPException(
            status_code=502,
            detail=f"OpenAI 응답 오류: {exc.code}"
        ) from exc
    except urllib.error.URLError as exc:
        raise HTTPException(
            status_code=502,
            detail="OpenAI 서버에 연결하지 못했습니다."
        ) from exc
    except (KeyError, json.JSONDecodeError) as exc:
        raise HTTPException(
            status_code=502,
            detail="OpenAI 응답을 해석하지 못했습니다."
        ) from exc


def _analyze_draft_rule_based(payload: AnalyzeDraftRequest) -> dict:
    draft = payload.draft.strip()
    partner_last = payload.partnerLastMessage.strip()

    partner_question = _looks_like_question(partner_last)
    draft_too_short = _looks_too_short(draft)
    harsh = _contains_harsh_expression(draft)
    partner_distress = _contains_distress_words(partner_last)
    dismissive = _is_dismissive(draft)
    looks_like_answer = _looks_like_answer(partner_last, draft)

    partner_speech = _get_nlu_speech_act(partner_last)
    draft_speech = _get_nlu_speech_act(draft)
    partner_emotion = _get_nlu_emotion(partner_last)
    draft_emotion = _get_nlu_emotion(draft)
    nlu_source = "kote" if (
        partner_emotion.get("source") == "kote" or
        draft_emotion.get("source") == "kote" or
        partner_speech.get("source") == "3i4k" or
        draft_speech.get("source") == "3i4k"
    ) else "unavailable"

    rules = [
        {
            "id": "draft_too_short",
            "label": "초안이 너무 짧음",
            "matched": bool(draft and draft_too_short),
        },
        {
            "id": "partner_question",
            "label": "상대방 발화가 질문임",
            "matched": partner_question or partner_speech.get("speechAct") == "question",
        },
        {
            "id": "question_not_answered",
            "label": "질문에 대한 답이 부족함",
            "matched": (
                (partner_question or partner_speech.get("speechAct") == "question") and
                (draft_too_short or not looks_like_answer)
            ),
        },
        {
            "id": "harsh_expression",
            "label": "차갑거나 강한 표현 포함",
            "matched": harsh,
        },
        {
            "id": "distress_dismissive",
            "label": "상대가 힘든데 초안이 무심함",
            "matched": (partner_distress or partner_emotion.get("distressScore", 0) > 0.45 or partner_emotion.get("burdenScore", 0) > 0.45) and dismissive,
        },
        {
            "id": "draft_negative_emotion",
            "label": "초안의 부정 감정이 높음",
            "matched": draft_emotion.get("angerScore", 0) > 0.45 or draft_emotion.get("burdenScore", 0) > 0.45,
        },
        {
            "id": "partner_request",
            "label": "상대방 발화가 요청/부탁 성격임",
            "matched": partner_speech.get("speechAct") in ["command", "rhetorical_command"],
        },
    ]

    if not draft or draft_too_short:
        should_invoke = False
        message = "초안이 너무 짧아 아직 큰 문제를 판단하기 어렵습니다."
    else:
        should_invoke = any(rule["matched"] for rule in rules if rule["id"] != "draft_too_short")
        message = "큰 문제는 감지되지 않았습니다."
        if should_invoke:
            message = "표현을 한 번 다듬어보는 편이 좋겠습니다."

    observed_features = {
        "draftLength": len(draft),
        "partnerLooksLikeQuestion": partner_question,
        "draftLooksTooShort": draft_too_short,
        "draftLooksLikeAnswer": looks_like_answer,
        "containsHarshExpression": harsh,
        "partnerContainsDistressWords": partner_distress,
        "draftLooksDismissive": dismissive,
        "partnerSpeechAct": partner_speech.get("speechAct", "unknown"),
        "draftSpeechAct": draft_speech.get("speechAct", "unknown"),
        "partnerEmotion": partner_emotion,
        "draftEmotion": draft_emotion,
        "nluSource": nlu_source,
    }

    return {
        "shouldInvokeLlm": should_invoke,
        "rules": rules,
        "observedFeatures": observed_features,
        "message": message,
    }


@app.post("/llm-assist")
async def llm_assist(req: LlmAssistRequest):
    draft = req.draft.strip()
    if not draft:
        return {
            "shouldFeedback": False,
            "feedback": "초안을 먼저 입력해주세요.",
            "reason": "빈 초안은 피드백할 수 없습니다.",
            "rewrite": None,
        }

    if len(draft) < 3:
        return {
            "shouldFeedback": False,
            "feedback": "초안이 너무 짧아서 아직 판단하기 어렵습니다.",
            "reason": "조금 더 구체적으로 입력하면 더 정확한 피드백을 줄 수 있습니다.",
            "rewrite": None,
        }

    return _call_openai_llm_assist(req)


@app.post("/auto-reply")
async def auto_reply(req: AutoReplyRequest):
    if not req.partnerLastMessage.strip():
        raise HTTPException(
            status_code=400,
            detail="상대방 마지막 메시지가 없어 자동 응답을 생성할 수 없습니다."
        )
    return _call_openai_auto_reply(req)


@app.post("/analyze-draft")
async def analyze_draft(req: AnalyzeDraftRequest):
    return _analyze_draft_rule_based(req)

@app.post("/users/update_status")
async def update_status(req: UpdateStatusRequest):
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute("UPDATE users SET status_message = ? WHERE user_id = ?", (req.status_message, req.user_id))
    conn.commit()
    conn.close()
    return {"success": True}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="127.0.0.1", port=8000)
