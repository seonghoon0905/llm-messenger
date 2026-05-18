from fastapi import APIRouter, WebSocket, WebSocketDisconnect
from database import get_db
from websocket.manager import manager

router = APIRouter()


@router.websocket("/ws/{user_id}")
async def websocket_endpoint(websocket: WebSocket, user_id: str):
    await manager.connect(user_id, websocket)
    try:
        while True:
            data = await websocket.receive_json()
            msg_type = data.get("type")

            # ── 초대 ──────────────────────────────────────────────────────
            if msg_type == "INVITE":
                room_id    = data.get("room_id")
                room_title = data.get("room_title")
                relation   = data.get("relation")
                invitee_id = data.get("invitee_id")
                ts         = data.get("timestamp")

                conn = get_db()
                cursor = conn.cursor()
                invitee_nick = invitee_id
                existing_members = []
                try:
                    cursor.execute(
                        "INSERT OR IGNORE INTO rooms (room_id, title, relation) VALUES (?, ?, ?)",
                        (room_id, room_title, relation),
                    )
                    cursor.execute(
                        "SELECT user_id FROM room_members WHERE room_id = ? AND user_id != ?",
                        (room_id, invitee_id),
                    )
                    existing_members = [r["user_id"] for r in cursor.fetchall()]
                    cursor.execute(
                        "INSERT OR IGNORE INTO room_members (room_id, user_id) VALUES (?, ?)",
                        (room_id, invitee_id),
                    )
                    cursor.execute(
                        "INSERT OR IGNORE INTO room_members (room_id, user_id) VALUES (?, ?)",
                        (room_id, user_id),
                    )
                    conn.commit()
                    cursor.execute("SELECT nickname FROM users WHERE user_id = ?", (invitee_id,))
                    row = cursor.fetchone()
                    invitee_nick = row["nickname"] if row and row["nickname"] else invitee_id
                finally:
                    conn.close()

                await manager.send({
                    "type": "INVITE_EVENT", "room_id": room_id,
                    "inviter_id": user_id, "room_title": room_title,
                    "relation": relation, "timestamp": ts,
                }, invitee_id)

                joined_packet = {
                    "type": "MEMBER_JOINED", "room_id": room_id,
                    "user_id": invitee_id, "nickname": invitee_nick,
                    "inviter_id": user_id, "timestamp": ts,
                }
                for mid in existing_members:
                    await manager.send(joined_packet, mid)
                continue

            # ── 퇴장 ──────────────────────────────────────────────────────
            if msg_type == "LEAVE":
                room_id = data.get("room_id")
                conn = get_db()
                cursor = conn.cursor()
                try:
                    cursor.execute(
                        "DELETE FROM room_members WHERE room_id = ? AND user_id = ?", (room_id, user_id)
                    )
                    conn.commit()
                    cursor.execute("SELECT user_id FROM room_members WHERE room_id = ?", (room_id,))
                    remaining = [r["user_id"] for r in cursor.fetchall()]
                    cursor.execute("SELECT nickname FROM users WHERE user_id = ?", (user_id,))
                    row = cursor.fetchone()
                    nick = row["nickname"] if row and row["nickname"] else user_id
                finally:
                    conn.close()

                packet = {"type": "LEAVE_EVENT", "room_id": room_id,
                          "user_id": user_id, "nickname": nick, "timestamp": data.get("timestamp")}
                for mid in remaining:
                    await manager.send(packet, mid)
                continue

            # ── 메시지 수정 ───────────────────────────────────────────────
            if msg_type == "EDIT":
                room_id       = data.get("room_id")
                msg_timestamp = data.get("msg_timestamp")
                new_text      = data.get("new_text")
                conn = get_db()
                cursor = conn.cursor()
                cursor.execute("SELECT user_id FROM room_members WHERE room_id = ?", (room_id,))
                members = [r["user_id"] for r in cursor.fetchall()]
                conn.close()
                packet = {"type": "EDIT_EVENT", "room_id": room_id,
                          "sender_id": user_id, "msg_timestamp": msg_timestamp, "new_text": new_text}
                for mid in members:
                    if mid != user_id:
                        await manager.send(packet, mid)
                continue

            # ── 메시지 삭제 ───────────────────────────────────────────────
            if msg_type == "DELETE":
                room_id       = data.get("room_id")
                msg_timestamp = data.get("msg_timestamp")
                conn = get_db()
                cursor = conn.cursor()
                cursor.execute("SELECT user_id FROM room_members WHERE room_id = ?", (room_id,))
                members = [r["user_id"] for r in cursor.fetchall()]
                conn.close()
                packet = {"type": "DELETE_EVENT", "room_id": room_id,
                          "sender_id": user_id, "msg_timestamp": msg_timestamp}
                for mid in members:
                    if mid != user_id:
                        await manager.send(packet, mid)
                continue

            # ── 일반 메시지 ───────────────────────────────────────────────
            room_id   = data.get("receiver_id")
            content   = data.get("content")
            timestamp = data.get("timestamp")
            conn = get_db()
            cursor = conn.cursor()
            cursor.execute("SELECT nickname FROM users WHERE user_id = ?", (user_id,))
            row = cursor.fetchone()
            sender_nick = row["nickname"] if row and row["nickname"] else user_id

            cursor.execute("SELECT title, relation FROM rooms WHERE room_id = ?", (room_id,))
            room_row = cursor.fetchone()
            room_title   = room_row["title"]    if room_row else room_id
            room_relation = room_row["relation"] if room_row else "기타"

            cursor.execute("SELECT user_id FROM room_members WHERE room_id = ?", (room_id,))
            members = [r["user_id"] for r in cursor.fetchall()]

            # 서버 DB에 메시지 저장 (오프라인 수신자를 위한 동기화 용)
            cursor.execute(
                "INSERT INTO messages (room_id, sender_id, sender_nickname, content, timestamp) "
                "VALUES (?, ?, ?, ?, ?)",
                (room_id, user_id, sender_nick, content, timestamp),
            )
            conn.commit()
            conn.close()

            packet = {
                "room_id": room_id, "sender_id": user_id, "sender_nickname": sender_nick,
                "content": content, "timestamp": data.get("timestamp"),
                "room_title": room_title, "relation": room_relation,
            }
            for mid in members:
                if mid != user_id:
                    p = dict(packet)
                    if room_id.startswith("dm:"):
                        p["room_title"] = sender_nick
                    await manager.send(p, mid)

    except WebSocketDisconnect:
        manager.disconnect(user_id)
    except Exception as e:
        print(f"[WS] Error ({user_id}): {e}")
        manager.disconnect(user_id)
