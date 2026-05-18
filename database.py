import sqlite3

DATABASE_PATH = "auth_server.db"


def get_db() -> sqlite3.Connection:
    conn = sqlite3.connect(DATABASE_PATH)
    conn.row_factory = sqlite3.Row
    return conn


def init_db() -> None:
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
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS messages (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            room_id TEXT NOT NULL,
            sender_id TEXT NOT NULL,
            sender_nickname TEXT,
            content TEXT NOT NULL,
            timestamp TEXT NOT NULL
        )
    """)
    conn.commit()
    conn.close()
