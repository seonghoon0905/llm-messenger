from fastapi import FastAPI, WebSocket, WebSocketDisconnect, HTTPException
from pydantic import BaseModel
from typing import List, Dict
import sqlite3
import json

app = FastAPI()

def get_db():
    conn = sqlite3.connect("auth_server.db")
    conn.row_factory = sqlite3.Row
    return conn

def init_db():
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS messages (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            room_id TEXT,
            sender_id TEXT,
            sender_nickname TEXT,
            content TEXT,
            timestamp TEXT
        )
    """)
    conn.commit()
    conn.close()

init_db()

# --- [ Pydantic 모델 ] ---
class User(BaseModel):
    username: str
    password: str

# --- [ WebSocket 관리 클래스 ] ---
class ConnectionManager:
    def __init__(self):
        # user_id: WebSocket 객체
        self.active_connections: Dict[str, WebSocket] = {}

    async def connect(self, user_id: str, websocket: WebSocket):
        await websocket.accept()
        self.active_connections[user_id] = websocket
        print(f"🟢 [WS] 연결 성공: {user_id}")

    def disconnect(self, user_id: str):
        if user_id in self.active_connections:
            del self.active_connections[user_id]
            print(f"🔴 [WS] 연결 해제: {user_id}")

    async def send_personal_message(self, message: dict, user_id: str):
        if user_id in self.active_connections:
            await self.active_connections[user_id].send_json(message)

manager = ConnectionManager()

# --- [ WebSocket 엔드포인트 ] ---
@app.websocket("/ws/{user_id}")
async def websocket_endpoint(websocket: WebSocket, user_id: str):
    await manager.connect(user_id, websocket)
    try:
        while True:
            data = await websocket.receive_json()
            
            # 1. 초대(INVITE) 처리 로직
            if data.get("type") == "INVITE":
                room_id = data.get("room_id")
                room_title = data.get("room_title")
                relation = data.get("relation")  # 우리가 중요하게 생각하는 관계 태그
                invitee_id = data.get("invitee_id")
                
                # [DB 기록] 방 정보 저장 및 멤버 추가
                conn = get_db()
                cursor = conn.cursor()
                try:
                    # 방이 없으면 생성 (태그 저장)
                    cursor.execute(
                        "INSERT OR IGNORE INTO rooms (room_id, title, relation) VALUES (?, ?, ?)",
                        (room_id, room_title, relation)
                    )
                    # 초대받은 사람을 멤버로 추가
                    cursor.execute(
                        "INSERT OR IGNORE INTO room_members (room_id, user_id) VALUES (?, ?)",
                        (room_id, invitee_id)
                    )
                    # (선택사항) 초대한 나 자신도 멤버로 추가
                    cursor.execute(
                        "INSERT OR IGNORE INTO room_members (room_id, user_id) VALUES (?, ?)",
                        (room_id, user_id)
                    )
                    conn.commit()
                except Exception as e:
                    print(f"❌ DB 저장 에러: {e}")
                finally:
                    conn.close()

                # 상대방에게 초대 이벤트 실시간 전송
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
                    print(f"📩 [INVITE] {user_id} -> {invitee_id} (방: {room_title}, 관계: {relation})")
                continue

            # 2. 일반 메시지 처리 로직
            room_id = data.get("receiver_id") # 클라이언트가 receiver_id 필드에 room_id를 보냅니다.
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
            
            # DB에 메시지 저장 (오프라인 동기화용)
            cursor.execute(
                "INSERT INTO messages (room_id, sender_id, sender_nickname, content, timestamp) VALUES (?, ?, ?, ?, ?)",
                (room_id, user_id, sender_nickname, content, data.get("timestamp"))
            )
            conn.commit()
            
            cursor.execute("SELECT user_id FROM room_members WHERE room_id = ?", (room_id,))
            members = cursor.fetchall()
            conn.close()

            for member in members:
                member_id = member["user_id"]
                if member_id != user_id and member_id in manager.active_connections:
                    await manager.send_personal_message(message_packet, member_id)
                    print(f"📩 [WS] {user_id} -> {member_id} (방: {room_id}): {content}")

    except WebSocketDisconnect:
        manager.disconnect(user_id)
    except Exception as e:
        print(f"❌ [WS] 에러 발생: {e}")
        manager.disconnect(user_id)

# --- [ 추가 API: 내 방 목록 불러오기 ] ---
# Flutter의 initState에서 이 API를 호출해야 목록이 유지됩니다.
@app.get("/users/{user_id}/rooms")
async def get_user_rooms(user_id: str):
    conn = get_db()
    cursor = conn.cursor()
    # 내가 멤버로 속한 방의 정보를 조인해서 가져옴
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

@app.get("/rooms/{room_id}/messages")
async def get_room_messages(room_id: str):
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute("SELECT * FROM messages WHERE room_id = ? ORDER BY timestamp ASC", (room_id,))
    messages = [dict(row) for row in cursor.fetchall()]
    conn.close()
    return {"success": True, "messages": messages}

@app.post("/login")
async def login(user: User):
    conn = get_db()
    cursor = conn.cursor()
    # DB에서 사용자 확인
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
        # 아이디/비번 틀림
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
    uvicorn.run(app, host="0.0.0.0", port=8000)