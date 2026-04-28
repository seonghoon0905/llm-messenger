import sqlite3

def init_db():
    conn = sqlite3.connect("auth_server.db")
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
            title TEXT NOT NULL,
            relation TEXT,            -- 우리가 보냈던 '가족', '친구' 등 태그 저장
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    """)

    cursor.execute("""
        CREATE TABLE IF NOT EXISTS room_members (
            room_id TEXT,
            user_id TEXT,
            joined_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (room_id, user_id),
            FOREIGN KEY (room_id) REFERENCES rooms (room_id),
            FOREIGN KEY (user_id) REFERENCES users (user_id)
        )
    """)
    
    test_users = [
        ('sh', '1234', '이성훈', '상태 메시지가 없습니다.'),
        ('ys', '1234', '김영석', '상태 메시지가 없습니다.'),
        ('hw', '1234', '이현우', '상태 메시지가 없습니다.')
    ]
    
    cursor.executemany(
        "INSERT OR IGNORE INTO users (user_id, password, nickname, status_message) VALUES (?, ?, ?, ?)", 
        test_users
    )
    
    conn.commit()
    conn.close()
    print("✅ 인증 및 채팅 서버 DB 초기화 완료 (방/멤버 테이블 포함)")

if __name__ == "__main__":
    init_db()