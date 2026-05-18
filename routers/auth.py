from fastapi import APIRouter, HTTPException
from database import get_db
from models.schemas import LoginRequest, SignupRequest, UpdateNicknameRequest, UpdateStatusRequest

router = APIRouter()


@router.post("/login")
def login(req: LoginRequest):
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute(
        "SELECT user_id, nickname, status_message FROM users WHERE user_id = ? AND password = ?",
        (req.username, req.password),
    )
    row = cursor.fetchone()
    conn.close()
    if not row:
        raise HTTPException(status_code=401, detail="인증 실패")
    return {
        "success": True,
        "user_id": row["user_id"],
        "nickname": row["nickname"] or row["user_id"],
        "status_message": row["status_message"],
    }


@router.post("/signup")
def signup(req: SignupRequest):
    uid  = req.user_id.strip()
    pw   = req.password.strip()
    nick = req.nickname.strip()
    status = (req.status_message or "").strip() or "상태 메시지가 없습니다."

    if not uid or not pw or not nick:
        raise HTTPException(status_code=400, detail="아이디, 비밀번호, 닉네임을 모두 입력해주세요.")

    conn = get_db()
    cursor = conn.cursor()
    cursor.execute("SELECT user_id FROM users WHERE user_id = ?", (uid,))
    if cursor.fetchone():
        conn.close()
        raise HTTPException(status_code=409, detail="이미 존재하는 아이디입니다.")

    cursor.execute(
        "INSERT INTO users (user_id, password, nickname, status_message) VALUES (?, ?, ?, ?)",
        (uid, pw, nick, status),
    )
    conn.commit()
    conn.close()
    return {"success": True, "user_id": uid, "nickname": nick, "status_message": status}


@router.get("/users/search/{search_id}")
def search_user(search_id: str):
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute(
        "SELECT user_id, nickname, status_message FROM users WHERE user_id = ?", (search_id,)
    )
    row = cursor.fetchone()
    conn.close()
    if not row:
        return {"success": False, "message": "해당 아이디의 사용자를 찾을 수 없습니다."}
    return {
        "success": True,
        "user_id": row["user_id"],
        "nickname": row["nickname"] or row["user_id"],
        "status_message": row["status_message"] or "상태 메시지가 없습니다.",
    }


@router.post("/users/update_nickname")
def update_nickname(req: UpdateNicknameRequest):
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute("UPDATE users SET nickname = ? WHERE user_id = ?", (req.nickname, req.user_id))
    conn.commit()
    conn.close()
    return {"success": True}


@router.post("/users/update_status")
def update_status(req: UpdateStatusRequest):
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute("UPDATE users SET status_message = ? WHERE user_id = ?",
                   (req.status_message, req.user_id))
    conn.commit()
    conn.close()
    return {"success": True}


@router.delete("/users/{user_id}")
def delete_account(user_id: str):
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute("DELETE FROM friends WHERE user_id = ? OR friend_id = ?", (user_id, user_id))
    cursor.execute("DELETE FROM room_members WHERE user_id = ?", (user_id,))
    cursor.execute("DELETE FROM users WHERE user_id = ?", (user_id,))
    conn.commit()
    conn.close()
    return {"success": True}
