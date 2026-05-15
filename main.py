from fastapi import FastAPI, WebSocket, WebSocketDisconnect, HTTPException
from pydantic import BaseModel
from typing import List, Dict, Optional, Any
import sqlite3
import json
import os
import ssl
import urllib.request
import urllib.error
import certifi

app = FastAPI()


def load_dotenv_file(path: str = ".env") -> None:
    if not os.path.exists(path):
        return

    try:
        with open(path, "r", encoding="utf-8") as env_file:
            for raw_line in env_file:
                line = raw_line.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue

                key, value = line.split("=", 1)
                key = key.strip()
                value = value.strip().strip('"').strip("'")

                if key and key not in os.environ:
                    os.environ[key] = value
    except OSError:
        pass


load_dotenv_file()
SSL_CONTEXT = ssl.create_default_context(cafile=certifi.where())

def get_db():
    conn = sqlite3.connect("auth_server.db")
    conn.row_factory = sqlite3.Row
    return conn

def init_db():
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS users (
            user_id TEXT PRIMARY KEY,
            password TEXT NOT NULL,
            nickname TEXT,
            status_message TEXT
        )
    """)
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
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS friends (
            user_id TEXT,
            friend_id TEXT,
            PRIMARY KEY(user_id, friend_id)
        )
    """)
    conn.commit()
    conn.close()

init_db()

# Pydantic Models
class User(BaseModel):
    username: str
    password: str


class SignupRequest(BaseModel):
    user_id: str
    password: str
    nickname: str
    status_message: Optional[str] = None


class DirectRoomRequest(BaseModel):
    user_id: str
    friend_id: str


class FriendAddRequest(BaseModel):
    user_id: str
    friend_id: str

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
                invitee_nickname = invitee_id
                existing_members = []
                try:
                    cursor.execute(
                        "INSERT OR IGNORE INTO rooms (room_id, title, relation) VALUES (?, ?, ?)",
                        (room_id, room_title, relation)
                    )
                    # 기존 멤버 목록 저장 (invitee 추가 전)
                    cursor.execute(
                        "SELECT user_id FROM room_members WHERE room_id = ? AND user_id != ?",
                        (room_id, invitee_id)
                    )
                    existing_members = [row["user_id"] for row in cursor.fetchall()]
                    cursor.execute(
                        "INSERT OR IGNORE INTO room_members (room_id, user_id) VALUES (?, ?)",
                        (room_id, invitee_id)
                    )
                    cursor.execute(
                        "INSERT OR IGNORE INTO room_members (room_id, user_id) VALUES (?, ?)",
                        (room_id, user_id)
                    )
                    conn.commit()
                    cursor.execute("SELECT nickname FROM users WHERE user_id = ?", (invitee_id,))
                    row = cursor.fetchone()
                    invitee_nickname = row["nickname"] if row and row["nickname"] else invitee_id
                except Exception as e:
                    print(f"DB Error: {e}")
                finally:
                    conn.close()

                # invitee에게 INVITE_EVENT 전송
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

                # 기존 멤버들에게 MEMBER_JOINED 브로드캐스트
                member_joined_packet = {
                    "type": "MEMBER_JOINED",
                    "room_id": room_id,
                    "user_id": invitee_id,
                    "nickname": invitee_nickname,
                    "inviter_id": user_id,
                    "timestamp": data.get("timestamp")
                }
                for member_id in existing_members:
                    if member_id in manager.active_connections:
                        await manager.send_personal_message(member_joined_packet, member_id)
                print(f"Invite: {user_id} -> {invitee_id} ({room_title}), notified {len(existing_members)} members")
                continue

            # Leave logic
            if data.get("type") == "LEAVE":
                room_id = data.get("room_id")
                conn = get_db()
                cursor = conn.cursor()
                try:
                    cursor.execute(
                        "DELETE FROM room_members WHERE room_id = ? AND user_id = ?",
                        (room_id, user_id),
                    )
                    conn.commit()
                    cursor.execute(
                        "SELECT user_id FROM room_members WHERE room_id = ?",
                        (room_id,),
                    )
                    remaining = [row["user_id"] for row in cursor.fetchall()]
                    cursor.execute(
                        "SELECT nickname FROM users WHERE user_id = ?", (user_id,)
                    )
                    row = cursor.fetchone()
                    nickname = row["nickname"] if row and row["nickname"] else user_id
                finally:
                    conn.close()

                leave_packet = {
                    "type": "LEAVE_EVENT",
                    "room_id": room_id,
                    "user_id": user_id,
                    "nickname": nickname,
                    "timestamp": data.get("timestamp"),
                }
                for member_id in remaining:
                    if member_id in manager.active_connections:
                        await manager.send_personal_message(leave_packet, member_id)
                print(f"Leave: {user_id} left room {room_id}")
                continue

            # Edit logic
            if data.get("type") == "EDIT":
                room_id = data.get("room_id")
                msg_timestamp = data.get("msg_timestamp")
                new_text = data.get("new_text")
                conn = get_db()
                cursor = conn.cursor()
                cursor.execute("SELECT user_id FROM room_members WHERE room_id = ?", (room_id,))
                members = [row["user_id"] for row in cursor.fetchall()]
                conn.close()
                edit_packet = {
                    "type": "EDIT_EVENT",
                    "room_id": room_id,
                    "sender_id": user_id,
                    "msg_timestamp": msg_timestamp,
                    "new_text": new_text,
                }
                for member_id in members:
                    if member_id != user_id and member_id in manager.active_connections:
                        await manager.send_personal_message(edit_packet, member_id)
                print(f"Edit: {user_id} edited msg in {room_id}")
                continue

            # Delete logic
            if data.get("type") == "DELETE":
                room_id = data.get("room_id")
                msg_timestamp = data.get("msg_timestamp")
                conn = get_db()
                cursor = conn.cursor()
                cursor.execute("SELECT user_id FROM room_members WHERE room_id = ?", (room_id,))
                members = [row["user_id"] for row in cursor.fetchall()]
                conn.close()
                delete_packet = {
                    "type": "DELETE_EVENT",
                    "room_id": room_id,
                    "sender_id": user_id,
                    "msg_timestamp": msg_timestamp,
                }
                for member_id in members:
                    if member_id != user_id and member_id in manager.active_connections:
                        await manager.send_personal_message(delete_packet, member_id)
                print(f"Delete: {user_id} deleted msg in {room_id}")
                continue

            # Message logic
            room_id = data.get("receiver_id")
            content = data.get("content")
            
            conn = get_db()
            cursor = conn.cursor()
            
            cursor.execute("SELECT nickname FROM users WHERE user_id = ?", (user_id,))
            sender_row = cursor.fetchone()
            sender_nickname = sender_row["nickname"] if sender_row and sender_row["nickname"] else user_id

            cursor.execute("SELECT title, relation FROM rooms WHERE room_id = ?", (room_id,))
            room_row = cursor.fetchone()
            room_title = room_row["title"] if room_row else room_id
            room_relation = room_row["relation"] if room_row else "기타"

            message_packet = {
                "room_id": room_id,
                "sender_id": user_id,
                "sender_nickname": sender_nickname,
                "content": content,
                "timestamp": data.get("timestamp"),
                "room_title": room_title,
                "relation": room_relation,
            }
            
            cursor.execute("SELECT user_id FROM room_members WHERE room_id = ?", (room_id,))
            members = cursor.fetchall()
            conn.close()

            for member in members:
                member_id = member["user_id"]
                if member_id != user_id and member_id in manager.active_connections:
                    personalized_packet = dict(message_packet)
                    if room_id.startswith("dm:"):
                        personalized_packet["room_title"] = sender_nickname
                    await manager.send_personal_message(personalized_packet, member_id)
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
    query = """
        SELECT r.room_id, r.title, r.relation 
        FROM rooms r
        JOIN room_members rm ON r.room_id = rm.room_id
        WHERE rm.user_id = ?
    """
    cursor.execute(query, (user_id,))
    raw_rooms = [dict(row) for row in cursor.fetchall()]
    rooms = []

    for room in raw_rooms:
        room_dict = dict(room)
        room_id = room_dict["room_id"]
        if room_id.startswith("dm:"):
            cursor.execute(
                """
                SELECT u.user_id, u.nickname
                FROM room_members rm
                JOIN users u ON rm.user_id = u.user_id
                WHERE rm.room_id = ? AND rm.user_id != ?
                LIMIT 1
                """,
                (room_id, user_id),
            )
            other_user = cursor.fetchone()
            if other_user:
                room_dict["title"] = other_user["nickname"] or other_user["user_id"]
        rooms.append(room_dict)
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


@app.post("/signup")
async def signup(req: SignupRequest):
    user_id = req.user_id.strip()
    password = req.password.strip()
    nickname = req.nickname.strip()
    status_message = (req.status_message or "").strip() or "상태 메시지가 없습니다."

    if not user_id or not password or not nickname:
        raise HTTPException(status_code=400, detail="아이디, 비밀번호, 닉네임을 모두 입력해주세요.")

    conn = get_db()
    cursor = conn.cursor()
    cursor.execute("SELECT user_id FROM users WHERE user_id = ?", (user_id,))
    existing = cursor.fetchone()
    if existing:
        conn.close()
        raise HTTPException(status_code=409, detail="이미 존재하는 아이디입니다.")

    cursor.execute(
        "INSERT INTO users (user_id, password, nickname, status_message) VALUES (?, ?, ?, ?)",
        (user_id, password, nickname, status_message),
    )
    conn.commit()
    conn.close()

    return {
        "success": True,
        "user_id": user_id,
        "nickname": nickname,
        "status_message": status_message,
    }

@app.get("/users/search/{search_id}")
async def search_user(search_id: str):
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute(
        "SELECT user_id, nickname, status_message FROM users WHERE user_id = ?", 
        (search_id,)
    )
    result = cursor.fetchone()
    conn.close()
    
    if result:
        return {
            "success": True, 
            "user_id": result["user_id"], 
            "nickname": result["nickname"] if result["nickname"] else result["user_id"],
            "status_message": result["status_message"] if "status_message" in result.keys() else "상태 메시지가 없습니다.",
        }
    else:
        return {"success": False, "message": "해당 아이디의 사용자를 찾을 수 없습니다."}


@app.get("/users/{user_id}/friends")
async def get_user_friends(user_id: str):
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute(
        """
        SELECT u.user_id, u.nickname, u.status_message
        FROM friends f
        JOIN users u ON f.friend_id = u.user_id
        WHERE f.user_id = ?
        ORDER BY COALESCE(u.nickname, u.user_id)
        """,
        (user_id,),
    )
    friends = [
        {
            "user_id": row["user_id"],
            "nickname": row["nickname"] if row["nickname"] else row["user_id"],
            "status_message": row["status_message"] or "상태 메시지가 없습니다.",
        }
        for row in cursor.fetchall()
    ]
    conn.close()
    return {"success": True, "friends": friends}


@app.post("/friends/add")
async def add_friend(req: FriendAddRequest):
    user_id = req.user_id.strip()
    friend_id = req.friend_id.strip()

    if not user_id or not friend_id:
        raise HTTPException(status_code=400, detail="친구 추가 정보가 올바르지 않습니다.")
    if user_id == friend_id:
        raise HTTPException(status_code=400, detail="자기 자신은 친구로 추가할 수 없습니다.")

    conn = get_db()
    cursor = conn.cursor()
    cursor.execute(
        "SELECT user_id, nickname, status_message FROM users WHERE user_id IN (?, ?)",
        (user_id, friend_id),
    )
    user_rows = {row["user_id"]: row for row in cursor.fetchall()}
    if user_id not in user_rows or friend_id not in user_rows:
        conn.close()
        raise HTTPException(status_code=404, detail="추가할 친구를 찾을 수 없습니다.")

    cursor.execute(
        "INSERT OR IGNORE INTO friends (user_id, friend_id) VALUES (?, ?)",
        (user_id, friend_id),
    )
    cursor.execute(
        "INSERT OR IGNORE INTO friends (user_id, friend_id) VALUES (?, ?)",
        (friend_id, user_id),
    )
    conn.commit()
    conn.close()

    friend_packet = {
        "type": "FRIEND_EVENT",
        "user_id": user_id,
        "nickname": user_rows[user_id]["nickname"] or user_id,
        "status_message": user_rows[user_id]["status_message"] or "상태 메시지가 없습니다.",
    }
    if friend_id in manager.active_connections:
        await manager.send_personal_message(friend_packet, friend_id)

    return {"success": True}


@app.delete("/friends/remove")
async def remove_friend(req: FriendAddRequest):
    user_id = req.user_id.strip()
    friend_id = req.friend_id.strip()
    if not user_id or not friend_id:
        raise HTTPException(status_code=400, detail="친구 삭제 정보가 올바르지 않습니다.")
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute("DELETE FROM friends WHERE (user_id=? AND friend_id=?) OR (user_id=? AND friend_id=?)",
                   (user_id, friend_id, friend_id, user_id))
    conn.commit()
    conn.close()
    return {"success": True}


@app.post("/rooms/direct")
async def create_or_get_direct_room(req: DirectRoomRequest):
    user_id = req.user_id.strip()
    friend_id = req.friend_id.strip()

    if not user_id or not friend_id:
        raise HTTPException(status_code=400, detail="사용자 정보가 올바르지 않습니다.")
    if user_id == friend_id:
        raise HTTPException(status_code=400, detail="자기 자신과의 1:1 채팅은 만들 수 없습니다.")

    ordered = sorted([user_id, friend_id])
    room_id = f"dm:{ordered[0]}:{ordered[1]}"

    conn = get_db()
    cursor = conn.cursor()
    cursor.execute(
        "SELECT user_id, nickname FROM users WHERE user_id IN (?, ?)",
        (user_id, friend_id),
    )
    users = {row["user_id"]: row["nickname"] for row in cursor.fetchall()}
    if user_id not in users or friend_id not in users:
        conn.close()
        raise HTTPException(status_code=404, detail="채팅방을 만들 사용자를 찾을 수 없습니다.")

    room_title = users.get(friend_id) or friend_id
    relation = "기타"

    cursor.execute(
        "INSERT OR IGNORE INTO rooms (room_id, title, relation) VALUES (?, ?, ?)",
        (room_id, room_title, relation),
    )
    cursor.execute(
        "INSERT OR IGNORE INTO room_members (room_id, user_id) VALUES (?, ?)",
        (room_id, user_id),
    )
    cursor.execute(
        "INSERT OR IGNORE INTO room_members (room_id, user_id) VALUES (?, ?)",
        (room_id, friend_id),
    )
    conn.commit()
    conn.close()

    return {
        "success": True,
        "room_id": room_id,
        "title": room_title,
        "relation": relation,
        "friend_id": friend_id,
        "friend_nickname": room_title,
    }

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
    llmCandidatePayload: Optional[dict] = None


class AutoReplyRequest(BaseModel):
    recentMessages: List[AssistMessage]
    partnerLastMessage: str
    registerMode: Optional[str] = None


class AnalyzeDraftRequest(BaseModel):
    recentMessages: List[AssistMessage]
    partnerLastMessage: str
    draft: str
    registerMode: Optional[str] = None


def _build_llm_assist_system_prompt() -> str:
    return """
당신은 한국어 메신저 답장 코치입니다.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
【말투 규칙 — 2단계 기준】
1단계(절대): [대화 모드]가 존댓말이면 전체 존댓말, 반말이면 전체 반말. 예외 없음.
2단계(보정): [나의 말투 예시]로 어미·어휘 수준을 맞춤.
  - 예시 어미가 "~어요/~할게요" 계열 → rewrite도 동일 어미 사용
  - 예시 어미가 "~어/~할게" 계열 → rewrite도 동일 어미 사용
  - 예시가 없으면 1단계(대화 모드)만 따른다.
주의: 2단계는 1단계 범위 안에서만 적용한다.
  존댓말 모드에서 예시 어미가 "~어요"라면, 더 격식 높은 "~겠습니다/~드리겠습니다/~예정입니다"로
  올리지 않는다. 예시보다 격식이 높거나 낮아지지 않도록 수준을 맞춘다.
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
- 판단 기준: 대화 전체 맥락에서 사용자가 실제로 원하는 것이 무엇인가?
- 대화 내내 무언가를 얻거나 개선을 원했는데 마지막에만 포기 선언 → 감정 표현으로 보고, 실제 목적을 살린다.
- 대화 흐름상 종료·취소·거절이 명백한 의사결정으로 보일 때 → 핵심 결론으로 보고 그 방향을 유지한다.
핵심: "결론 유지" 규칙은 실제 의사결정에만 적용한다. 감정에서 나온 충동적 포기는 의사결정이 아니다.

[상대방 행동 언급 기준]
아래 두 가지를 반드시 구분한다.

① 지금 하는 행동에 대한 요구·불평 → rewrite에서 완전히 제거
   "~하지 마세요", "왜 자꾸 ~해요", "그만 ~해요" 패턴이 draft에 있으면,
   상대 행동에 대한 언급을 rewrite에서 일절 하지 않는다.
   softened 표현("~하셔서 부담스러운데", "~하시니까 좀 그렇지만")도 동일하게 금지.
   → 사용자의 현재 상황·계획·답변만 전달한다.

② 반복 패턴이 관계에 미치는 영향에 대한 우려 → rewrite에서 유지
   "항상", "맨날", "매번" 같은 단어로 반복성을 지적하면서,
   그로 인해 협력·관계가 어려워진다는 우려를 표현한 경우.
   이는 즉각적인 행동 요구가 아니라 관계에 대한 우려이므로 살린다.
   단, "무책임하다", "믿을 수 없다" 같은 단정적 비난은 제거하고
   "이런 상황이 반복되면 함께 하기 어려울 것 같다"는 형태로 표현한다.

구분 기준 한 줄: "지금 당장 멈추라는 요구인가" vs "이 패턴이 관계에 어떤 영향을 주는지에 대한 우려인가"

[rewrite 작성 규칙]
1. 말투는 [말투 규칙 2단계]에 따라 결정한다.
   [나의 말투 예시]의 어미·어휘 수준과 자연스럽게 어울려야 한다.
   공문서·관료적 문체는 피한다: "~하심을 이해합니다만", "~드리기 어려운 점", "~에 대해 말씀드립니다" 등.

2. 사용자의 "핵심 결론·입장"은 절대 뒤집지 마세요.
   거절은 거절로, 취소는 취소로, 상대가 와야 한다면 그 입장으로 유지.
   톤·표현만 바꾸고 결론은 그대로 유지합니다.

3. 단정적·통보형 톤은 제안형·문의형으로 풀어주세요. 결론은 유지하되 표현만 부드럽게.

4. rewrite 구성: 짧은 도입부(상황 인정 또는 본인 상황 설명) + 핵심 목적.
   한두 문장이면 충분합니다. 길게 늘리지 마세요.

5. 상대가 서운함·지적을 표현한 직후라면, 그 원인을 도입부에서 짧게 인정하세요.
   단, 사용자가 전혀 인정할 의도가 없어 보이면 생략.
   ※ 사용자가 말하지 않은 새 사과·약속·감정은 만들지 마세요.

6. 상대가 거절·원칙 통보 후 사용자가 다시 부탁하는 경우:
   이미 알려진 정보 재확인 요청은 금지. 본인 사정 짧게 → 동일 요청에 대한 예외 가능 여부를 문의형으로.

   ⚠️ 새로운 대안 발명 금지: 원래 요청이 A라면 → A에 대한 예외를 묻는 것만 허용.
   A와 다른 주제 B를 발명해서 제안하는 것은 금지.
   "연관되어 있다"는 이유로 다른 주제를 끌어와도 안 된다.

   ⚠️ 이미 "다른 방법이 없냐"고 묻고 거절된 경우:
   더 이상 새로운 방법·대안을 찾으려 하지 말 것.
   이 상황의 rewrite는 "개인 사정만이라도 한 번 더 고려해달라는 최종 부탁"이다.
   형태: "사정이 있어서 어렵게 부탁드리는 건데, 혹시 한 번 더 고려해주실 수 있을지요."

7. 격식 관계에서 부탁할 때: 책임 회피 표현 대신 명확한 인정.

8. 너무 비굴하거나 과한 사과로 만들지 마세요.

9. draft에 요청·바람이 있었다면 rewrite에도 구체적 요청을 담으세요.
   서운함·속상함 표현만으로 끝내지 마세요.

[원칙]
1. 비난·빈정거림·압박·상대 탓이 있으면 shouldFeedback=true.
2. 사용자가 말하지 않은 사과·약속·사실을 새로 만들지 마세요.
3. 차분한 거절·자연스러운 단답·정상적 정보 전달은 그대로 (shouldFeedback=false).

[판단 절차]
1) [대화 모드] + [나의 말투 예시] 확인 → rewrite 어미·어휘 수준 결정.
2) 상대 마지막 발화의 성격 파악.
3) draft에서 사용자의 진짜 목적·결론을 파악.
   포기 표현이 있으면 [충동적 포기 vs 실제 결론 판단] 기준으로 먼저 분류.
4) 상대 행동 언급이 있으면 [상대방 행동 언급 기준]으로 ①/② 분류.
5) 감정 표현이 있으면 shouldFeedback=true.
6) 도입부 + 핵심 목적 구조로 재구성.

[자주 발생하는 함정]
A. 이미 통보된 정보를 "다시 확인해 달라"고 하지 마세요. → 예외·대안 문의로.
B. 과거 합의·사전 통보 재언급 완전 금지.
   "어제 ~로 하기로 했는데", "미리 말씀드렸는데" 같은 표현은 반박처럼 들리므로 포함하지 마세요.
   → 현재 시간·일정이 어렵다는 사실만 간결하게.
C. 결론 자체를 뒤집지 마세요 (취소→유지, 거절→수락, 상대가 와야 함→본인이 감 등).
   ⚠️ 특히: 상대방이 와야 하거나 상대방이 특정 행동을 해야 한다는 것이 핵심 결론이면,
   rewrite에서 상대에게 그 행동을 명시적으로 요청하는 문장이 포함되어야 한다.
   "나는 여기 있을게", "나는 기다릴게"처럼 사용자 행동만 서술하고 끝내면 안 된다.
   반드시 "네가 올 수 있어?", "이쪽으로 와줄 수 있어?" 처럼 상대에게 직접 요청하는 문장을 포함할 것.
D. 책임 회피 표현 금지 → 명확한 인정으로.
E. [충동적 포기 vs 실제 결론 판단] 기준을 적용했는지 확인하세요.
F. rewrite 작성 후 B·C·E를 다시 확인하고, 해당하면 재작성하세요.

[특수 상황 패턴]

▶ 즉각적 행동 요구가 있는 draft
  draft의 핵심이 상대방에게 지금 하는 행동을 멈추라는 요구일 때:
  상대 행동을 언급하지 말고(softened 표현도 금지) 사용자의 상황·답변·계획만 전달한다.

▶ 반복 패턴 우려가 있는 draft
  draft에 "항상", "맨날", "매번" 등이 있고 협력·관계에 대한 우려를 담고 있을 때:
  단정적 비난 표현은 제거하되, 반복될 경우 함께하기 어렵다는 우려 자체는 반드시 살린다.
  우려를 "아쉽다"·"궁금하다" 수준으로 희석하지 마세요.

▶ 거절 반복 압박 패턴
  사용자가 이미 거절했는데 상대방이 계속 요청·압박하는 경우:
  부드럽지만 명확한 거절을 유지한다. 질문형·협상형으로 바꾸지 말 것.
  "다른 방법이 있는지 여쭤봐도 될까요?" 같은 표현은 거절이 협상으로 변질되므로 금지.

▶ 격식 관계 + 거절 직후 패턴
  상대가 원칙·거절을 통보한 직후 사용자가 다시 말을 거는 경우:
  ① 본인 사정 짧게 + 본인 책임 명확히 인정
  ② 예외·대안 가능 여부를 직접 문의형으로

[출력 형식]
JSON만:
{
  "shouldFeedback": boolean,
  "feedback": "왜 다듬는 게 좋은지 한 줄, 없으면 null",
  "rewrite": "그대로 보낼 수 있는 문장, 없으면 null",
  "reason": "어떤 감정 표현을 빼고 어떤 목적을 살렸는지 한 줄, 없으면 null"
}
""".strip()


def _build_llm_assist_user_prompt(payload: LlmAssistRequest) -> str:
    candidate = payload.llmCandidatePayload if isinstance(payload.llmCandidatePayload, dict) else {}

    recent_messages = candidate.get("recentMessages")
    if not isinstance(recent_messages, list):
        recent_messages = [
            {"role": m.role, "text": m.text}
            for m in payload.recentMessages
        ]
    recent_messages = recent_messages[-6:]

    context_lines = []
    for m in recent_messages:
        if not isinstance(m, dict):
            continue
        speaker = "상대방" if m.get("role") == "partner" else "나"
        context_lines.append(f"[{speaker}] {m.get('text', '')}")
    context_text = "\n".join(context_lines) if context_lines else "(대화 내역 없음)"

    register_mode = _normalize_register_mode(candidate.get("registerMode"))
    mode_hint = "존댓말(격식체)" if register_mode == "formal" else "반말(캐주얼)"

    # 사용자 발화만 뽑아 말투 예시 제공
    my_lines = [
        m.get("text", "") for m in recent_messages
        if isinstance(m, dict) and m.get("role") == "me" and m.get("text", "").strip()
    ]
    my_style_hint = " / ".join(my_lines[-3:]) if my_lines else "(없음)"

    return f"""
[대화 모드]
{mode_hint}

[나의 말투 예시 — rewrite는 이 말투를 그대로 따를 것]
{my_style_hint}

[최근 대화]
{context_text}

[상대방 마지막 메시지]
{payload.partnerLastMessage or "(없음)"}

[사용자가 작성한 draft]
{payload.draft}

위 정보를 보고 시스템 지시에 따라 JSON으로만 답하세요.
""".strip()


def _sanitize_assist_response(raw: dict) -> dict:
    should_feedback = bool(raw.get("shouldFeedback"))
    feedback = raw.get("feedback") if isinstance(raw.get("feedback"), str) else None
    reason = raw.get("reason") if isinstance(raw.get("reason"), str) else None
    rewrite_raw = raw.get("rewrite")
    rewrite = rewrite_raw.strip() if isinstance(rewrite_raw, str) else None
    if rewrite == "":
        rewrite = None

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
        "되나",
        "되나요",
        "할까",
        "해줄래",
        "할까요",
        "괜찮을까요",
        "가능할까요",
        "맞아",
    ]
    lowered = text.strip().lower()
    return any(marker in lowered for marker in question_markers)


def _looks_too_short(text: str) -> bool:
    return len(text.strip()) < 4


def _contains_harsh_expression(text: str) -> bool:
    harsh_patterns = [
        # 기존 패턴
        "됐", "싫", "짜증", "몰라", "그만", "안 해", "귀찮", "꺼져", "알아서",
        # 욕설/비하 (과도한 매칭 방지를 위해 "개" 단독 사용 안 함 — "개발", "개선" 오탐 방지)
        "개같",    # "개같이", "개같은"
        "개소리",
        "ㅈ같",
        "좆같",
        "씨발", "시발",
        "병신",
        "지랄",
        "닥쳐",
        "극혐",
        "멍청",
        "한심",
        # 공격적 무시
        "어쩌라고",
        "그래서 뭐",
        "상관없어",
    ]
    return any(pattern in text for pattern in harsh_patterns)


def _contains_distress_words(text: str) -> bool:
    distress_patterns = [
        "힘들", "지쳤", "속상", "우울", "불안", "부담", "걱정",
        "짜증나", "답답",
        "슬프", "슬픈", "슬펐",
        "괴롭", "괴로",
        "외로", "쓸쓸",
        "죽고싶", "죽고 싶",
    ]
    return any(pattern in text for pattern in distress_patterns)


def _is_dismissive(text: str) -> bool:
    dismissive_patterns = [
        # 기존 패턴
        "알아서", "어쩌라고", "그건 네가", "나도 몰라", "됐어", "그만해", "귀찮아",
        # 냉담/무관심 추가
        "그래서 뭐",
        "상관없어",
        "나한테 왜",
        "내가 뭘",
        "그게 나랑",
        "그냥 참아",
        "별거 아니네",
        "그 정도는",
    ]
    return any(pattern in text for pattern in dismissive_patterns)


def _looks_like_answer(partner_last_message: str, draft: str) -> bool:
    if not _looks_like_question(partner_last_message):
        return True
    # 공격적이거나 무시하는 답변은 정상 답변으로 인정하지 않음
    if _contains_harsh_expression(draft) or _is_dismissive(draft):
        return False
    stripped = draft.strip()
    # 이유/배경만 서술하는 미완성 답변 어미 감지 — 패턴 체크보다 먼저 수행
    incomplete_endings = ("서", "는데", "지만", "고", "며", "니까", "거든")
    if stripped.endswith(incomplete_endings):
        return False
    answer_patterns = [
        "응", "ㅇㅇ",
        "아니", "아니야", "아니에요",
        "가능", "불가능",
        "어려워", "어렵",
        "괜찮", "좋아", "좋아요",
        "안 돼", "안돼", "돼", "될 것",
        "할게", "할게요",
        "못", "못 해", "못해",
        "갈게", "갈 수", "못 가", "못가",
        "할 수 없", "할 수 있",
        "ㄱㄴ", "ㄴㄴ",
        "맞아", "맞아요",
        "있어", "없어", "있어요", "없어요",
    ]
    if any(pattern in stripped for pattern in answer_patterns):
        return True
    # 그 외 충분히 긴 문장은 답변으로 간주 (기준 높임)
    return len(stripped) >= 15


def _looks_like_invitation_or_proposal(text: str) -> bool:
    patterns = [
        "같이", "함께", "어때", "할래", "할까",
        "하자", "가자", "먹자", "보자", "해볼래", "해볼까",
    ]
    return any(p in text for p in patterns)


def _looks_like_complaint_or_conflict(text: str) -> bool:
    patterns = [
        "왜 그렇게", "기분 나빠", "기분 나쁘", "서운해", "서운했",
        "화났어", "화나", "짜증나", "짜증났",
        "상처받았", "실망했", "실망이야",
        "왜 그래", "왜 그러는", "너 때문에", "그게 뭐야",
    ]
    return any(p in text for p in patterns)


def _looks_like_simple_social_exchange(text: str) -> bool:
    patterns = [
        "고마워", "감사해", "감사합니다", "ㄱㅅ",
        "수고했어", "수고해", "수고하세요", "수고했습니다",
        "잘 자", "잘자", "안녕히 주무세요", "굿나잇",
        "내일 봐", "나중에 봐", "다음에 봐",
        "확인했어", "확인했습니다",
        "알겠어", "알겠습니다", "ㅇㅋ",
        "다행이다", "다행이야", "잘됐다", "잘됐네",
    ]
    return any(p in text for p in patterns)


def _is_clearly_safe_to_skip_llm(
    partner_last_message: str,
    draft: str,
    register_mode: str,
    formal_prob: float,
    partner_speech_act: dict,
    my_draft_emotion_scores: dict,
    emotion_shift: dict,
    negative_emotion_streak: dict,
    nlu_source: str,
) -> tuple:
    """Returns (clearly_safe, safe_skip_reasons, llm_review_reasons)."""
    stripped_partner = partner_last_message.strip()
    stripped_draft = draft.strip()
    review_reasons: List[str] = []

    partner_act = partner_speech_act.get("speechAct", "unknown")

    is_question = partner_act == "question" or _looks_like_question(stripped_partner)
    if is_question:
        review_reasons.append("partner_question")

    is_request = (
        partner_act in ["command", "rhetorical_command", "request"]
        or any(m in stripped_partner for m in ["해줘", "보내줘", "확인해줘", "부탁", "주세요", "해주시", "전달해"])
    )
    if is_request:
        review_reasons.append("partner_request_or_command")

    is_invitation = _looks_like_invitation_or_proposal(stripped_partner)
    if is_invitation and not is_request:
        review_reasons.append("partner_invitation_or_proposal")

    if _contains_distress_words(stripped_partner):
        review_reasons.append("partner_distress")
    if _looks_like_complaint_or_conflict(stripped_partner):
        review_reasons.append("partner_conflict_or_complaint")

    if _contains_harsh_expression(stripped_draft):
        review_reasons.append("draft_harsh_expression")
    if _is_dismissive(stripped_draft):
        review_reasons.append("draft_dismissive")

    if _negative_emotion_sum(my_draft_emotion_scores) >= 0.4:
        review_reasons.append("draft_high_negative_emotion")

    if register_mode == "formal" and formal_prob < 0.5:
        review_reasons.append("formal_mismatch")

    if negative_emotion_streak.get("active"):
        review_reasons.append("negative_emotion_streak_active")

    if emotion_shift.get("direction") == "worsened":
        review_reasons.append("emotion_shift_worsened")

    if review_reasons:
        return False, [], review_reasons

    is_simple_social = _looks_like_simple_social_exchange(stripped_partner)

    if nlu_source in ("fallback", "unavailable") and not is_simple_social:
        review_reasons.append("not_clearly_safe")
        return False, [], review_reasons

    safe_skip_reasons: List[str] = []
    if is_simple_social:
        safe_skip_reasons.append("simple_social_exchange")
    else:
        safe_skip_reasons.append("no_risk_signals_nlu_available")

    return True, safe_skip_reasons, []


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
    """30초마다 NLU 서버 상태를 재확인한다. True 캐시가 영구 지속되는 버그를 방지."""
    global _nlu_service_available, _nlu_last_check_time
    import time
    now = time.time()
    # 마지막 확인 후 30초 이내이면 캐시 반환 (True든 False든 동일)
    if _nlu_service_available is not None and now - _nlu_last_check_time < _nlu_recheck_interval:
        return bool(_nlu_service_available)
    prev = _nlu_service_available
    try:
        _fetch_json(f"{_get_nlu_base_url()}/health", timeout=1)
        _nlu_service_available = True
        if prev is not True:
            print(f"[NLU] Service available at {_get_nlu_base_url()}")
    except Exception as e:
        _nlu_service_available = False
        if prev is not False:
            print(f"[NLU] Service unavailable ({_get_nlu_base_url()}): {e}")
    _nlu_last_check_time = now
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
    except Exception as e:
        print(f"[NLU] /speech-act request failed: {e}")
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
    except Exception as e:
        print(f"[NLU] /emotion-scores request failed: {e}")
        return _nlu_unavailable_emotion()


def _normalize_register_mode(register_mode: Optional[str]) -> str:
    return "formal" if register_mode == "formal" else "casual"


def _infer_register_mode(recent_messages: list, partner_last_message: str) -> str:
    """대화 맥락을 보고 사용자가 써야 할 말투 모드를 GPT로 추론한다."""
    api_key = os.getenv("OPENAI_API_KEY")
    if not api_key:
        return "casual"

    context_lines = []
    for m in recent_messages[-6:]:
        if isinstance(m, dict):
            speaker = "상대방" if m.get("role") == "partner" else "나"
            text = m.get("text", "")
        else:
            speaker = "상대방" if m.role == "partner" else "나"
            text = m.text
        context_lines.append(f"[{speaker}] {text}")
    if partner_last_message:
        context_lines.append(f"[상대방] {partner_last_message}")
    context_text = "\n".join(context_lines) if context_lines else "(대화 내역 없음)"

    system_prompt = """대화를 보고 사용자("나")가 상대방에게 어떤 말투를 써야 하는 관계인지 판단하세요.

- "formal": 존댓말을 써야 하는 관계 (상사, 교수, 선배, 고객, 처음 보는 사람, 부모님·가족 어른 등)
- "casual": 반말을 써도 되는 관계 (친구, 동생, 연인, 편한 동료 등)

판단 기준 (우선순위 순):
1. "나"의 발화 어미를 최우선으로 봅니다.
   - 나: "~요/~습니다/~어요/아뇨" → formal
   - 나: "~야/~어/~지/ㅋ/ㅎ" → casual
2. 나의 발화가 없으면 상대방 호칭과 말투로 추론합니다.
3. 상대방이 반말을 해도 나는 존댓말을 써야 하는 경우가 있습니다.
   부모님·가족 어른은 자녀에게 반말/임말을 써도, 자녀는 존댓말을 쓰는 것이 일반적입니다.

JSON만 반환: {"registerMode": "formal" | "casual"}"""

    model_name = os.getenv("OPENAI_MODEL", "gpt-4o-mini")
    request_body = {
        "model": model_name,
        "response_format": {"type": "json_object"},
        "temperature": 0.1,
        "max_tokens": 20,
        "messages": [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": context_text},
        ],
    }

    try:
        req = urllib.request.Request(
            "https://api.openai.com/v1/chat/completions",
            data=json.dumps(request_body).encode("utf-8"),
            headers={
                "Content-Type": "application/json",
                "Authorization": f"Bearer {api_key}",
            },
            method="POST",
        )
        with urllib.request.urlopen(req, timeout=10, context=SSL_CONTEXT) as response:
            data = json.loads(response.read().decode("utf-8"))
            content = data["choices"][0]["message"]["content"]
            parsed = json.loads(content)
            mode = parsed.get("registerMode", "casual")
            return mode if mode in ("formal", "casual") else "casual"
    except Exception:
        return "casual"


def _estimate_formal_prob(text: str) -> float:
    stripped = text.strip()
    if not stripped:
        return 0.0

    positive_markers = {
        "습니다": 0.25,
        "입니다": 0.2,
        "해요": 0.15,
        "드려요": 0.2,
        "주세요": 0.2,
        "드립니다": 0.25,
        "가능할까요": 0.25,
        "괜찮으실까요": 0.25,
        "부탁드립니다": 0.3,
    }
    negative_markers = {
        "해": 0.1,
        "야": 0.1,
        "ㅇㅇ": 0.25,
        "ㄱㄱ": 0.25,
        "몰라": 0.2,
        "짜증나": 0.3,
        "싫어": 0.2,
        "귀찮": 0.25,
    }

    score = 0.5
    for marker, weight in positive_markers.items():
        if marker in stripped:
            score += weight
    for marker, weight in negative_markers.items():
        if marker in stripped:
            score -= weight

    if stripped.endswith(("요", "니다", "까요")):
        score += 0.1
    if stripped.endswith(("야", "네", "ㅋ", "ㅎ")):
        score -= 0.1

    return max(0.0, min(1.0, score))


def _safe_score(value: Any) -> float:
    try:
        return max(0.0, min(1.0, float(value)))
    except (TypeError, ValueError):
        return 0.0


def _rule_based_emotion_scores(text: str) -> dict:
    score = _nlu_unavailable_emotion()
    stripped = text.strip()
    if not stripped:
        score["source"] = "fallback"
        score["neutralScore"] = 1.0
        score["topEmotionLabels"] = ["neutral"]
        return score

    distress_markers = ["힘들", "불안", "걱정", "무서", "슬퍼", "우울", "지쳤", "속상", "답답"]
    anger_markers = ["짜증", "화나", "열받", "싫어", "그만", "하지마", "빡", "별로", "어이없"]
    burden_markers = ["부담", "귀찮", "피곤", "바빠", "못하겠", "번거", "벅차", "가능할까요"]
    warmth_markers = ["고마워", "감사", "좋아", "괜찮아", "도와", "응원", "수고", "미안", "고생"]
    neutral_markers = ["알겠", "확인", "오케이", "ㅇㅋ", "그래", "네"]

    def _calc(markers: List[str], base: float = 0.0) -> float:
        hits = sum(1 for marker in markers if marker in stripped)
        return max(base, min(1.0, hits * 0.35))

    score["distressScore"] = _calc(distress_markers)
    score["angerScore"] = _calc(anger_markers)
    score["burdenScore"] = _calc(burden_markers)
    score["warmthScore"] = _calc(warmth_markers)
    if "힘들" in stripped:
        score["distressScore"] = max(score["distressScore"], 0.45)
    if "부담" in stripped:
        score["burdenScore"] = max(score["burdenScore"], 0.45)
    if "짜증" in stripped or "하지마" in stripped:
        score["angerScore"] = max(score["angerScore"], 0.45)
    matched_any = any(
        score[key] > 0
        for key in ["distressScore", "angerScore", "burdenScore", "warmthScore"]
    )
    score["neutralScore"] = max(
        _calc(neutral_markers, 0.65 if not matched_any else 0.15),
        0.55 if not matched_any else 0.0,
    )

    group_pairs = [
        ("distress", score["distressScore"]),
        ("anger", score["angerScore"]),
        ("burden", score["burdenScore"]),
        ("warmth", score["warmthScore"]),
        ("neutral", score["neutralScore"]),
    ]
    score["topEmotionLabels"] = [name for name, value in sorted(group_pairs, key=lambda item: item[1], reverse=True)[:3] if value > 0]
    score["source"] = "fallback"
    return score


def _get_emotion_scores(text: str) -> dict:
    nlu_score = _get_nlu_emotion(text)
    if nlu_score.get("source") == "kote":
        return nlu_score
    return _rule_based_emotion_scores(text)


def _rule_based_speech_act(text: str) -> dict:
    stripped = text.strip()
    if not stripped:
        return {"speechAct": "statement", "source": "fallback"}
    if any(marker in stripped for marker in ["해줘", "보내줘", "확인해줘", "부탁", "요청", "주세요", "해주시", "전달해"]):
        return {"speechAct": "request", "source": "fallback"}
    if any(marker in stripped for marker in ["?", "가능", "가능할까요", "해줄", "되나", "되나요", "할까", "할까요", "어때", "왜", "언제", "괜찮을까요"]):
        return {"speechAct": "question", "source": "fallback"}
    return {"speechAct": "statement", "source": "fallback"}


def _get_speech_act(text: str) -> dict:
    nlu_act = _get_nlu_speech_act(text)
    if nlu_act.get("source") == "3i4k" and nlu_act.get("speechAct"):
        return nlu_act
    return _rule_based_speech_act(text)


def _negative_emotion_sum(scores: dict) -> float:
    return (
        _safe_score(scores.get("distressScore"))
        + _safe_score(scores.get("angerScore"))
        + _safe_score(scores.get("burdenScore"))
    )


def _detect_emotion_shift(partner_scores: dict, draft_scores: dict) -> dict:
    partner_negative = _negative_emotion_sum(partner_scores)
    draft_negative = _negative_emotion_sum(draft_scores)
    partner_warmth = _safe_score(partner_scores.get("warmthScore"))
    draft_warmth = _safe_score(draft_scores.get("warmthScore"))
    delta = round(draft_negative - partner_negative, 3)

    if (partner_warmth >= 0.3 and draft_negative >= 0.45) or (
        partner_negative >= 0.35 and draft_negative > partner_negative + 0.25 and draft_warmth < 0.2
    ):
        return {
            "direction": "worsened",
            "reason": "답장의 부정 감정이 상대방 발화보다 더 강하게 나타납니다.",
            "scoreDelta": delta,
        }
    if draft_warmth > partner_warmth + 0.2 and draft_negative + 0.1 < partner_negative:
        return {
            "direction": "improved",
            "reason": "답장이 상대방의 감정을 다소 완화하는 방향으로 보입니다.",
            "scoreDelta": delta,
        }
    return {
        "direction": "neutral",
        "reason": "뚜렷한 감정 악화 신호는 보이지 않습니다.",
        "scoreDelta": delta,
    }


def _compute_negative_emotion_streak(messages: List[AssistMessage]) -> dict:
    partner_messages = [message for message in messages if message.role == "partner" and message.text.strip()]
    count = 0
    for message in reversed(partner_messages[-5:]):
        scores = _get_emotion_scores(message.text)
        if _negative_emotion_sum(scores) >= 0.35:
            count += 1
        else:
            break

    active = count >= 2
    reason = "최근 상대방의 부정 감정이 이어지고 있습니다." if active else "부정 감정 연속 신호가 뚜렷하지 않습니다."
    return {
        "count": count,
        "active": active,
        "reason": reason,
    }


def _build_observed_features(
    draft: str,
    partner_last_message: str,
    register_mode: str,
    formal_prob: float,
    partner_speech_act: dict,
    my_speech_act: dict,
    partner_emotion_scores: dict,
    my_draft_emotion_scores: dict,
    emotion_shift: dict,
    negative_emotion_streak: dict,
    nlu_source: str,
) -> dict:
    return {
        "draftLength": len(draft.strip()),
        "partnerLooksLikeQuestion": _looks_like_question(partner_last_message),
        "draftLooksTooShort": _looks_too_short(draft),
        "draftLooksLikeAnswer": _looks_like_answer(partner_last_message, draft),
        "containsHarshExpression": _contains_harsh_expression(draft),
        "draftLooksDismissive": _is_dismissive(draft),
        "registerMode": register_mode,
        "formalProb": formal_prob,
        "partnerSpeechAct": partner_speech_act.get("speechAct", "unknown"),
        "mySpeechAct": my_speech_act.get("speechAct", "unknown"),
        "partnerEmotionScores": partner_emotion_scores,
        "myDraftEmotionScores": my_draft_emotion_scores,
        "emotionShift": emotion_shift,
        "negativeEmotionStreak": negative_emotion_streak,
        "nluSource": nlu_source,
    }


def _build_thin_gate_reasons(
    register_mode: str,
    formal_prob: float,
    partner_last_message: str,
    draft: str,
    partner_speech_act: dict,
    my_speech_act: dict,
    partner_emotion_scores: dict,
    my_draft_emotion_scores: dict,
    emotion_shift: dict,
    negative_emotion_streak: dict,
) -> List[dict]:
    partner_act = partner_speech_act.get("speechAct", "unknown")
    my_act = my_speech_act.get("speechAct", "unknown")
    partner_question = partner_act == "question" or _looks_like_question(partner_last_message)
    command_like = partner_act in ["command", "rhetorical_command", "request"] or any(
        marker in partner_last_message for marker in ["해줘", "보내줘", "확인해", "부탁", "주세요"]
    )
    draft_too_short = _looks_too_short(draft)
    looks_like_answer = _looks_like_answer(partner_last_message, draft)
    harsh = _contains_harsh_expression(draft)
    dismissive = _is_dismissive(draft)
    partner_negative = _negative_emotion_sum(partner_emotion_scores)
    draft_negative = _negative_emotion_sum(my_draft_emotion_scores)

    return [
        {
            "id": "formal_mismatch",
            "label": "격식체 대화에서 답장이 너무 캐주얼함",
            "matched": register_mode == "formal" and formal_prob < 0.5,
            "severity": "medium",
        },
        {
            "id": "question_not_answered",
            "label": "상대방 질문에 대한 답이 부족함",
            "matched": partner_question and (draft_too_short or not looks_like_answer),
            "severity": "high",
        },
        {
            "id": "request_not_addressed",
            "label": "상대방 요청/부탁에 대한 반응이 부족함",
            "matched": command_like and (draft_too_short or my_act == "statement" and not looks_like_answer),
            "severity": "medium",
        },
        {
            "id": "harsh_expression",
            "label": "답장에 차갑거나 강한 표현이 포함됨",
            "matched": harsh or draft_negative >= 0.6 or _safe_score(my_draft_emotion_scores.get("angerScore")) >= 0.4,
            "severity": "high",
        },
        {
            "id": "emotion_shift_worsened",
            "label": "답장으로 감정 톤이 악화될 가능성",
            "matched": emotion_shift.get("direction") == "worsened",
            "severity": "high",
        },
        {
            "id": "distress_dismissive",
            "label": "상대가 힘든 상황인데 답장이 무심하게 들릴 수 있음",
            "matched": (partner_negative >= 0.8 or _contains_distress_words(partner_last_message)) and dismissive,
            "severity": "high",
        },
        {
            "id": "negative_streak_cold_reply",
            "label": "상대방의 부정 감정이 이어지는 상황에서 답장이 짧거나 차가움",
            "matched": negative_emotion_streak.get("active") and (dismissive or harsh or draft_too_short),
            "severity": "medium",
        },
    ]


def _build_llm_candidate_payload(
    payload: AnalyzeDraftRequest,
    register_mode: str,
    formal_prob: float,
    partner_speech_act: dict,
    my_speech_act: dict,
    partner_emotion_scores: dict,
    my_draft_emotion_scores: dict,
    emotion_shift: dict,
    negative_emotion_streak: dict,
    thin_gate_reasons: List[dict],
    llm_review_reasons: Optional[List[str]] = None,
    gate_mode: str = "llm_review",
) -> dict:
    return {
        "recentMessages": [
            {"role": message.role, "text": message.text}
            for message in payload.recentMessages[-6:]
        ],
        "partnerLastMessage": payload.partnerLastMessage,
        "draft": payload.draft,
        "registerMode": register_mode,
        "formalProb": formal_prob,
        "partnerSpeechAct": partner_speech_act.get("speechAct", "unknown"),
        "mySpeechAct": my_speech_act.get("speechAct", "unknown"),
        "partnerEmotionScores": partner_emotion_scores,
        "myDraftEmotionScores": my_draft_emotion_scores,
        "emotionShift": emotion_shift,
        "negativeEmotionStreak": negative_emotion_streak,
        "thinGateReasons": thin_gate_reasons,
        "llmReviewReasons": llm_review_reasons or [],
        "gateMode": gate_mode,
    }


def _build_auto_reply_system_prompt() -> str:
    return """
당신은 사용자 대신 카카오톡 답장을 짧게 작성하는 도우미입니다.

[가장 중요한 원칙]
상대방이 원하는 것을 무조건 수락하는 답장을 만들지 마세요.
사용자가 이전 대화에서 어떤 상황에 처해 있는지, 무엇이 필요한지를 파악해서 생성합니다.

예:
- 사용자가 마감을 놓쳐서 예외 처리를 부탁해야 하는 상황 → 수락이 아니라 예외 요청 답장
- 사용자가 오늘 처리하기 어렵다고 했는데 상대가 오늘까지 해달라고 함 → 어렵다고 설명하고 대안 제시
- 사용자가 거절했는데 상대가 계속 부탁함 → 거절 입장 유지

[원칙]
1. 관계와 말투에 맞게 작성하세요.
   - 친구·연인·편한 사이 → 자연스러운 반말
   - 부모님·가족 → 가족체 (~해요/~할게요 수준의 편한 존댓말)
   - 교수님·상사·고객·격식 → 공손한 존댓말

2. 사용자가 처한 상황을 파악해서 그에 맞는 방향으로 생성합니다.
   - 부탁해야 하는 상황 → 정중하게 부탁
   - 거절해야 하는 상황 → 상황 설명 + 대안 제시
   - 상대 서운함/지적 → 상황 설명 (과도한 사과·반성 금지)
   - 상대가 거절·원칙 통보를 했더라도, 사용자에게 특수한 사정이 있다면 예외·대안을 한 번 더 정중하게 부탁하는 방향으로 생성합니다.

3. 사용자가 말하지 않은 사과·약속·감사를 추가하지 마세요.

4. 한두 문장으로 짧게 작성합니다.

5. 실제 카카오톡에서 바로 보낼 수 있는 자연스러운 구어체로 작성합니다.

[출력 형식]
JSON만:
{"reply": "답장 문장", "reason": "짧은 이유"}
""".strip()


def _build_auto_reply_user_prompt(payload: AutoReplyRequest) -> str:
    context_lines = []
    for message in payload.recentMessages:
        speaker = "상대방" if message.role == "partner" else "나"
        context_lines.append(f"[{speaker}] {message.text}")
    context_text = "\n".join(context_lines) if context_lines else "(대화 내역 없음)"

    if payload.registerMode:
        register_mode = _normalize_register_mode(payload.registerMode)
    else:
        register_mode = _infer_register_mode(payload.recentMessages, payload.partnerLastMessage)

    if register_mode == "formal":
        tone_guide = "교수님·상사·고객 등 격식 관계입니다. 공손한 존댓말로 작성하세요."
    else:
        tone_guide = "친구·연인·가족 등 편한 관계입니다. 자연스러운 반말 또는 가족체로 작성하세요."

    return f"""
[대화 모드]
{tone_guide}

[최근 대화 맥락]
{context_text}

[상대방 마지막 메시지]
{payload.partnerLastMessage}

위 맥락을 바탕으로 사용자 입장에서 자연스러운 답장 초안을 JSON 형식으로만 반환해주세요.
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
        "temperature": 0.3,
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
        with urllib.request.urlopen(req, timeout=20, context=SSL_CONTEXT) as response:
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
        with urllib.request.urlopen(req, timeout=20, context=SSL_CONTEXT) as response:
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
    if payload.registerMode:
        register_mode = _normalize_register_mode(payload.registerMode)
    else:
        register_mode = _infer_register_mode(payload.recentMessages, partner_last)
    formal_prob = _estimate_formal_prob(draft)
    partner_speech = _get_speech_act(partner_last)
    draft_speech = _get_speech_act(draft)
    partner_emotion = _get_emotion_scores(partner_last)
    draft_emotion = _get_emotion_scores(draft)
    emotion_shift = _detect_emotion_shift(partner_emotion, draft_emotion)
    negative_emotion_streak = _compute_negative_emotion_streak(payload.recentMessages)

    sources = [
        partner_emotion.get("source"),
        draft_emotion.get("source"),
        partner_speech.get("source"),
        draft_speech.get("source"),
    ]
    if "kote" in sources or "3i4k" in sources:
        nlu_source = "available"
    elif "fallback" in sources:
        # rule-based 분석이 실제로 수행됨을 명확히 표시
        nlu_source = "fallback"
    else:
        nlu_source = "unavailable"

    thin_gate_reasons = _build_thin_gate_reasons(
        register_mode=register_mode,
        formal_prob=formal_prob,
        partner_last_message=partner_last,
        draft=draft,
        partner_speech_act=partner_speech,
        my_speech_act=draft_speech,
        partner_emotion_scores=partner_emotion,
        my_draft_emotion_scores=draft_emotion,
        emotion_shift=emotion_shift,
        negative_emotion_streak=negative_emotion_streak,
    )

    if not draft:
        should_invoke = False
        gate_mode = "safe_skip"
        clearly_safe = True
        safe_skip_reasons: List[str] = ["empty_draft"]
        llm_review_reasons: List[str] = []
        message = "초안을 먼저 입력해주세요."
    elif len(draft) < 2:
        should_invoke = False
        gate_mode = "safe_skip"
        clearly_safe = True
        safe_skip_reasons = ["draft_too_short"]
        llm_review_reasons = []
        message = "초안이 너무 짧아 아직 큰 문제를 판단하기 어렵습니다."
    else:
        clearly_safe, safe_skip_reasons, llm_review_reasons = _is_clearly_safe_to_skip_llm(
            partner_last_message=partner_last,
            draft=draft,
            register_mode=register_mode,
            formal_prob=formal_prob,
            partner_speech_act=partner_speech,
            my_draft_emotion_scores=draft_emotion,
            emotion_shift=emotion_shift,
            negative_emotion_streak=negative_emotion_streak,
            nlu_source=nlu_source,
        )
        should_invoke = not clearly_safe
        gate_mode = "safe_skip" if clearly_safe else "llm_review"
        message = "표현을 한 번 다듬어보는 편이 좋겠습니다." if should_invoke else "큰 문제는 감지되지 않았습니다."

    observed_features = _build_observed_features(
        draft=draft,
        partner_last_message=partner_last,
        register_mode=register_mode,
        formal_prob=formal_prob,
        partner_speech_act=partner_speech,
        my_speech_act=draft_speech,
        partner_emotion_scores=partner_emotion,
        my_draft_emotion_scores=draft_emotion,
        emotion_shift=emotion_shift,
        negative_emotion_streak=negative_emotion_streak,
        nlu_source=nlu_source,
    )
    llm_candidate_payload = _build_llm_candidate_payload(
        payload=payload,
        register_mode=register_mode,
        formal_prob=formal_prob,
        partner_speech_act=partner_speech,
        my_speech_act=draft_speech,
        partner_emotion_scores=partner_emotion,
        my_draft_emotion_scores=draft_emotion,
        emotion_shift=emotion_shift,
        negative_emotion_streak=negative_emotion_streak,
        thin_gate_reasons=thin_gate_reasons,
        llm_review_reasons=llm_review_reasons,
        gate_mode=gate_mode,
    )

    return {
        "registerMode": register_mode,
        "formalProb": formal_prob,
        "partnerEmotionScores": partner_emotion,
        "myDraftEmotionScores": draft_emotion,
        "emotionShift": emotion_shift,
        "negativeEmotionStreak": negative_emotion_streak,
        "partnerSpeechAct": partner_speech.get("speechAct", "unknown"),
        "mySpeechAct": draft_speech.get("speechAct", "unknown"),
        "thinGateReasons": thin_gate_reasons,
        "rules": thin_gate_reasons,
        "gateMode": gate_mode,
        "clearlySafeToSkip": clearly_safe,
        "safeSkipReasons": safe_skip_reasons,
        "llmReviewReasons": llm_review_reasons,
        "shouldInvokeLlm": should_invoke,
        "observedFeatures": observed_features,
        "llmCandidatePayload": llm_candidate_payload,
        "message": message,
    }


@app.post("/llm-assist")
async def llm_assist(req: LlmAssistRequest):
    candidate = req.llmCandidatePayload if isinstance(req.llmCandidatePayload, dict) else {}
    effective_draft = candidate.get("draft") if isinstance(candidate.get("draft"), str) else req.draft
    draft = effective_draft.strip()
    if not draft:
        return {
            "shouldFeedback": False,
            "feedback": "초안을 먼저 입력해주세요.",
            "reason": "빈 초안은 피드백할 수 없습니다.",
            "rewrite": None,
        }

    # 짧은 draft여도 GPT가 맥락을 보고 판단해야 함 (early exit 제거)
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


class LearyAnalysisRequest(BaseModel):
    messages: List[AssistMessage]  # role: "me" | "partner"


def _leary_quadrant(dominance: float, affiliation: float) -> str:
    dom_label = "leading" if dominance >= 60 else ("following" if dominance <= 40 else "balanced")
    aff_label = "friendly" if affiliation >= 60 else ("hostile" if affiliation <= 40 else "neutral")
    return f"{dom_label}-{aff_label}"


def _get_leary_speech_act(text: str) -> dict:
    """Leary dominance 전용 화행 분류.
    3i4K가 fragment/unknown/statement로 분류하면 rule-based fallback으로 보정."""
    primary = _get_speech_act(text)
    act = primary.get("speechAct", "unknown")
    if act in ("fragment", "unknown", "statement", "intonation_dependent", None, ""):
        fallback = _rule_based_speech_act(text)
        fallback_act = fallback.get("speechAct", "unknown")
        if fallback_act in ("request", "question"):
            return {
                "speechAct": fallback_act,
                "source": f"{primary.get('source', 'unknown')}+fallback",
            }
    return primary


def _normalize_leary_source(source: str, kind: str) -> str:
    """개별 소스 문자열을 집계용 카테고리로 정규화."""
    source = source or "unavailable"
    if kind == "speechAct":
        if source == "3i4k":
            return "model"
        if "3i4k" in source:          # "3i4k+fallback" 등
            return "model_assisted"
        if source == "fallback":
            return "fallback"
        return "unavailable"
    # emotion
    if source == "kote":
        return "model"
    if source == "fallback":
        return "fallback"
    return "unavailable"


def _leary_reliability(emo_sources: List[str], act_sources: List[str]) -> dict:
    def _aggregate(normalized: List[str]) -> str:
        if not normalized:
            return "unavailable"
        n = len(normalized)
        model_n     = sum(1 for s in normalized if s == "model")
        assisted_n  = sum(1 for s in normalized if s == "model_assisted")
        model_total = model_n + assisted_n
        if model_total / n >= 0.8:
            return "model" if model_n / n >= 0.8 else "model-assisted"
        if model_total / n >= 0.3:
            return "mixed"
        fallback_n = sum(1 for s in normalized if s == "fallback")
        return "fallback" if fallback_n / n >= 0.5 else "unavailable"

    emo_norm = [_normalize_leary_source(s, "emotion")  for s in emo_sources]
    act_norm = [_normalize_leary_source(s, "speechAct") for s in act_sources]

    emo_agg = _aggregate(emo_norm)
    act_agg = _aggregate(act_norm)

    # 표시용 소스 레이블: 원본 문자열 집계
    def _display_source(sources: List[str], model_exact: str) -> str:
        if not sources:
            return "unavailable"
        n = len(sources)
        exact  = sum(1 for s in sources if s == model_exact)
        assist = sum(1 for s in sources if model_exact in s and s != model_exact)
        fallbk = sum(1 for s in sources if s == "fallback")
        if exact / n >= 0.8:
            return model_exact
        if (exact + assist) / n >= 0.3:
            return f"{model_exact}+fallback" if assist > 0 else "mixed"
        return "fallback" if fallbk / n >= 0.5 else "unavailable"

    emo_display = _display_source(emo_sources, "kote")
    act_display = _display_source(act_sources, "3i4k")

    # reliability: model/model-assisted → 모델 사용으로 간주
    emo_ok = emo_agg in ("model", "model-assisted", "mixed")
    act_ok = act_agg in ("model", "model-assisted", "mixed")
    emo_strong = emo_agg == "model"
    act_strong = act_agg == "model"

    if emo_strong and act_strong:
        reliability = "high"
    elif emo_ok and act_ok:
        reliability = "medium"
    elif emo_ok or act_ok:
        reliability = "medium"
    else:
        reliability = "low"

    return {
        "reliability": reliability,
        "sources": {"emotion": emo_display, "speechAct": act_display},
    }


@app.post("/analyze-leary")
async def analyze_leary(req: LearyAnalysisRequest):
    # ── 1. 최근 100개 메시지만 분석 ──────────────────────────────────────────
    all_msgs = [m for m in req.messages if m.text.strip()]
    recent = all_msgs[-100:]

    my_msgs = [m for m in recent if m.role == "me"]
    partner_msgs = [m for m in recent if m.role == "partner"]

    if not my_msgs:
        return {
            "dominance": 50.0,
            "affiliation": 50.0,
            "quadrant": "balanced-neutral",
            "analyzed_count": len(recent),
            "my_message_count": 0,
            "partner_message_count": len(partner_msgs),
            "window_size": 100,
            "reliability": "low",
            "sources": {"emotion": "unavailable", "speechAct": "unavailable"},
            "signals": {
                "avgWarmth": 0.0, "avgAnger": 0.0,
                "avgDistress": 0.0, "avgBurden": 0.0,
                "harshDismissiveRatio": 0.0,
                "speechDominance": 0.0,
                "lengthRatio": 0.5, "countRatio": 0.5,
            },
        }

    n = len(my_msgs)

    # ── 2. Affiliation (KOTE 기반) ─────────────────────────────────────────────
    warmth_sum = anger_sum = distress_sum = burden_sum = 0.0
    emo_sources: List[str] = []
    harsh_count = 0

    for msg in my_msgs:
        scores = _get_emotion_scores(msg.text)
        emo_sources.append(scores.get("source", "unavailable"))
        warmth_sum  += _safe_score(scores.get("warmthScore"))
        anger_sum   += _safe_score(scores.get("angerScore"))
        distress_sum += _safe_score(scores.get("distressScore"))
        burden_sum  += _safe_score(scores.get("burdenScore"))
        if _contains_harsh_expression(msg.text) or _is_dismissive(msg.text):
            harsh_count += 1

    avg_warmth   = warmth_sum  / n
    avg_anger    = anger_sum   / n
    avg_distress = distress_sum / n
    avg_burden   = burden_sum  / n
    harsh_ratio  = harsh_count / n

    # distress는 적대성이 아니므로 가중치를 최소화
    affiliation = (
        50.0
        + avg_warmth   * 35
        - avg_anger    * 35
        - avg_burden   * 10
        - harsh_ratio  * 20
        - avg_distress * 5   # 약한 감산만
    )
    affiliation = max(5.0, min(95.0, affiliation))

    # ── 3. Dominance (3i4K 기반) ──────────────────────────────────────────────
    _SPEECH_DOM = {
        "command": 1.0, "rhetorical_command": 1.0,
        "request": 0.5,
        "question": 0.25,
        "statement": 0.0, "fragment": 0.0,
        "rhetorical_question": 0.15, "intonation_dependent": 0.1,
        "unknown": 0.0,
    }

    speech_dom_sum = 0.0
    act_sources: List[str] = []
    for msg in my_msgs:
        speech = _get_leary_speech_act(msg.text)
        act_sources.append(speech.get("source", "unavailable"))
        act = speech.get("speechAct", "unknown")
        speech_dom_sum += _SPEECH_DOM.get(act, 0.0)

    speech_dominance = speech_dom_sum / n

    avg_my_len = sum(len(m.text) for m in my_msgs) / n
    avg_partner_len = (
        sum(len(m.text) for m in partner_msgs) / len(partner_msgs)
        if partner_msgs else avg_my_len
    )
    total_len = avg_my_len + avg_partner_len
    length_ratio = avg_my_len / total_len if total_len > 0 else 0.5

    total_count = len(my_msgs) + len(partner_msgs)
    count_ratio = len(my_msgs) / total_count if total_count > 0 else 0.5

    dominance = (
        50.0
        + speech_dominance      * 30
        + (length_ratio - 0.5)  * 30
        + (count_ratio  - 0.5)  * 20
    )
    dominance = max(5.0, min(95.0, dominance))

    # ── 4. 신뢰도 / 소스 집계 ─────────────────────────────────────────────────
    rel_info = _leary_reliability(emo_sources, act_sources)

    return {
        "dominance":    round(dominance, 1),
        "affiliation":  round(affiliation, 1),
        "quadrant":     _leary_quadrant(dominance, affiliation),
        "analyzed_count":       len(recent),
        "my_message_count":     n,
        "partner_message_count": len(partner_msgs),
        "window_size":  100,
        "reliability":  rel_info["reliability"],
        "sources":      rel_info["sources"],
        "signals": {
            "avgWarmth":            round(avg_warmth,   3),
            "avgAnger":             round(avg_anger,    3),
            "avgDistress":          round(avg_distress, 3),
            "avgBurden":            round(avg_burden,   3),
            "harshDismissiveRatio": round(harsh_ratio,  3),
            "speechDominance":      round(speech_dominance, 3),
            "lengthRatio":          round(length_ratio, 3),
            "countRatio":           round(count_ratio,  3),
        },
    }

@app.delete("/users/{user_id}")
async def delete_account(user_id: str):
    conn = get_db()
    cursor = conn.cursor()
    try:
        cursor.execute(
            "DELETE FROM friends WHERE user_id = ? OR friend_id = ?",
            (user_id, user_id),
        )
        cursor.execute(
            "DELETE FROM room_members WHERE user_id = ?", (user_id,)
        )
        cursor.execute(
            "DELETE FROM users WHERE user_id = ?", (user_id,)
        )
        conn.commit()
    finally:
        conn.close()
    return {"success": True}


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
