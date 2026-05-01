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