from fastapi import FastAPI, WebSocket, WebSocketDisconnect, HTTPException
from pydantic import BaseModel
from typing import List, Dict, Optional
import sqlite3
import json
import os
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


def _build_llm_assist_system_prompt() -> str:
    return """
당신은 사용자의 한국어 메신저 답장을 다듬는 실용적인 코칭 도우미입니다.
반드시 최근 대화 맥락과 상대방의 마지막 발화를 함께 보고 판단하십시오.

목표:
- 현재 draft가 너무 차갑거나 공격적이거나 맥락에 어긋나는지 판단합니다.
- 피드백이 필요하면 짧은 코칭 메시지와 이유, 그리고 실제로 보낼 수 있는 더 자연스러운 rewrite 1개를 제안합니다.
- 피드백이 필요 없으면 shouldFeedback=false로 반환합니다.

원칙:
- 사용자의 의도는 유지하되 표현만 더 자연스럽게 정리합니다.
- 상대방의 마지막 발화에 직접 반응하는 답장을 우선합니다.
- 지나치게 교과서적이거나 상담체인 표현은 피합니다.
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

위 내용을 바탕으로, 현재 draft가 충분히 자연스러운지 판단하고 지정된 JSON 형식으로만 답변해주세요.
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


def _heuristic_llm_assist(payload: LlmAssistRequest) -> dict:
    draft = payload.draft.strip()
    partner_last = payload.partnerLastMessage.strip()

    if not draft:
        return {
            "shouldFeedback": False,
            "feedback": None,
            "reason": None,
            "rewrite": None,
        }

    harsh_tokens = ["됐", "싫", "짜증", "왜", "그만", "몰라", "바빠", "안 해"]
    harsh = any(token in draft for token in harsh_tokens)

    if harsh:
        rewrite = draft
        if not any(ending in draft for ending in ["요", "습니다", "해줘", "할게"]):
            rewrite = f"{draft} 조금만 부드럽게 말해줄래?"

        return {
            "shouldFeedback": True,
            "feedback": "조금 직설적으로 들릴 수 있어요. 상대방 말에 반응하는 완충 표현을 한 줄 더 넣는 편이 안전합니다.",
            "reason": "현재 초안은 의도는 전달되지만 상대방이 차갑게 받아들일 가능성이 있습니다.",
            "rewrite": rewrite,
        }

    if partner_last and "?" in partner_last and len(draft) < 4:
        return {
            "shouldFeedback": True,
            "feedback": "상대방 질문에 조금 더 직접 반응하면 자연스럽습니다.",
            "reason": "마지막 메시지가 질문인데 현재 초안은 답으로 읽히기엔 정보가 부족합니다.",
            "rewrite": f"{draft} 자세한 건 조금 있다가 말해줄게." if draft else None,
        }

    return {
        "shouldFeedback": False,
        "feedback": None,
        "reason": None,
        "rewrite": None,
    }


def _call_openai_llm_assist(payload: LlmAssistRequest) -> Optional[dict]:
    api_key = os.getenv("OPENAI_API_KEY")
    if not api_key:
        return None

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
    except (urllib.error.URLError, urllib.error.HTTPError, KeyError, json.JSONDecodeError):
        return None


@app.post("/llm-assist")
async def llm_assist(req: LlmAssistRequest):
    if not req.draft.strip():
        return {
            "shouldFeedback": False,
            "feedback": None,
            "reason": None,
            "rewrite": None,
        }

    llm_result = _call_openai_llm_assist(req)
    if llm_result is not None:
        return llm_result

    return _heuristic_llm_assist(req)

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
