from fastapi import APIRouter, HTTPException
from database import get_db
from models.schemas import FriendRequest
from websocket.manager import manager

router = APIRouter()


@router.post("/friends/add")
async def add_friend(req: FriendRequest):
    uid, fid = req.user_id.strip(), req.friend_id.strip()
    if not uid or not fid:
        raise HTTPException(status_code=400, detail="친구 추가 정보가 올바르지 않습니다.")
    if uid == fid:
        raise HTTPException(status_code=400, detail="자기 자신은 친구로 추가할 수 없습니다.")

    conn = get_db()
    cursor = conn.cursor()
    cursor.execute(
        "SELECT user_id, nickname, status_message FROM users WHERE user_id IN (?, ?)", (uid, fid)
    )
    rows = {r["user_id"]: r for r in cursor.fetchall()}
    if uid not in rows or fid not in rows:
        conn.close()
        raise HTTPException(status_code=404, detail="추가할 친구를 찾을 수 없습니다.")

    cursor.execute("INSERT OR IGNORE INTO friends (user_id, friend_id) VALUES (?, ?)", (uid, fid))
    cursor.execute("INSERT OR IGNORE INTO friends (user_id, friend_id) VALUES (?, ?)", (fid, uid))
    conn.commit()
    conn.close()

    packet = {
        "type": "FRIEND_EVENT",
        "user_id": uid,
        "nickname": rows[uid]["nickname"] or uid,
        "status_message": rows[uid]["status_message"] or "상태 메시지가 없습니다.",
    }
    await manager.send(packet, fid)
    return {"success": True}


@router.delete("/friends/remove")
def remove_friend(req: FriendRequest):
    uid, fid = req.user_id.strip(), req.friend_id.strip()
    if not uid or not fid:
        raise HTTPException(status_code=400, detail="친구 삭제 정보가 올바르지 않습니다.")
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute(
        "DELETE FROM friends WHERE (user_id=? AND friend_id=?) OR (user_id=? AND friend_id=?)",
        (uid, fid, fid, uid),
    )
    conn.commit()
    conn.close()
    return {"success": True}


@router.get("/users/{user_id}/friends")
def get_friends(user_id: str):
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
            "user_id": r["user_id"],
            "nickname": r["nickname"] or r["user_id"],
            "status_message": r["status_message"] or "상태 메시지가 없습니다.",
        }
        for r in cursor.fetchall()
    ]
    conn.close()
    return {"success": True, "friends": friends}
