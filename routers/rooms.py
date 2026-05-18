from typing import Optional
from fastapi import APIRouter, HTTPException
from database import get_db
from models.schemas import DirectRoomRequest

router = APIRouter()


@router.get("/users/{user_id}/rooms")
def get_user_rooms(user_id: str):
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute(
        """
        SELECT r.room_id, r.title, r.relation
        FROM rooms r
        JOIN room_members rm ON r.room_id = rm.room_id
        WHERE rm.user_id = ?
        """,
        (user_id,),
    )
    raw = [dict(r) for r in cursor.fetchall()]
    rooms = []
    for room in raw:
        rid = room["room_id"]
        if rid.startswith("dm:"):
            cursor.execute(
                """
                SELECT u.user_id, u.nickname
                FROM room_members rm
                JOIN users u ON rm.user_id = u.user_id
                WHERE rm.room_id = ? AND rm.user_id != ?
                LIMIT 1
                """,
                (rid, user_id),
            )
            other = cursor.fetchone()
            if other:
                room["title"] = other["nickname"] or other["user_id"]
        rooms.append(room)
    conn.close()
    return {"success": True, "rooms": rooms}


@router.post("/rooms/direct")
def create_direct_room(req: DirectRoomRequest):
    uid, fid = req.user_id.strip(), req.friend_id.strip()
    if not uid or not fid:
        raise HTTPException(status_code=400, detail="사용자 정보가 올바르지 않습니다.")
    if uid == fid:
        raise HTTPException(status_code=400, detail="자기 자신과의 1:1 채팅은 만들 수 없습니다.")

    room_id = f"dm:{':'.join(sorted([uid, fid]))}"
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute(
        "SELECT user_id, nickname FROM users WHERE user_id IN (?, ?)", (uid, fid)
    )
    users = {r["user_id"]: r["nickname"] for r in cursor.fetchall()}
    if uid not in users or fid not in users:
        conn.close()
        raise HTTPException(status_code=404, detail="채팅방을 만들 사용자를 찾을 수 없습니다.")

    title = users.get(fid) or fid
    cursor.execute("INSERT OR IGNORE INTO rooms (room_id, title, relation) VALUES (?, ?, ?)",
                   (room_id, title, "기타"))
    cursor.execute("INSERT OR IGNORE INTO room_members (room_id, user_id) VALUES (?, ?)", (room_id, uid))
    cursor.execute("INSERT OR IGNORE INTO room_members (room_id, user_id) VALUES (?, ?)", (room_id, fid))
    conn.commit()
    conn.close()
    return {"success": True, "room_id": room_id, "title": title,
            "relation": "기타", "friend_id": fid, "friend_nickname": title}


@router.get("/rooms/{room_id}/messages")
def get_room_messages(room_id: str, since: Optional[str] = None):
    """로그인 후 누락된 메시지 동기화용. since 이후 메시지만 반환."""
    conn = get_db()
    cursor = conn.cursor()
    if since:
        cursor.execute(
            "SELECT sender_id, sender_nickname, content, timestamp "
            "FROM messages WHERE room_id = ? AND timestamp > ? ORDER BY timestamp ASC",
            (room_id, since),
        )
    else:
        cursor.execute(
            "SELECT sender_id, sender_nickname, content, timestamp "
            "FROM messages WHERE room_id = ? ORDER BY timestamp ASC",
            (room_id,),
        )
    messages = [dict(r) for r in cursor.fetchall()]
    conn.close()
    return {"messages": messages}
