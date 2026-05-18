from typing import Dict
from fastapi import WebSocket


class ConnectionManager:
    def __init__(self) -> None:
        self.active_connections: Dict[str, WebSocket] = {}

    async def connect(self, user_id: str, websocket: WebSocket) -> None:
        await websocket.accept()
        self.active_connections[user_id] = websocket
        print(f"[WS] Connected: {user_id}")

    def disconnect(self, user_id: str) -> None:
        self.active_connections.pop(user_id, None)
        print(f"[WS] Disconnected: {user_id}")

    async def send(self, message: dict, user_id: str) -> None:
        ws = self.active_connections.get(user_id)
        if ws:
            await ws.send_json(message)


manager = ConnectionManager()
