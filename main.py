from fastapi import FastAPI
from database import init_db
from routers import auth, friends, rooms, analysis, ws

app = FastAPI(title="LLM Messenger API")

app.include_router(auth.router)
app.include_router(friends.router)
app.include_router(rooms.router)
app.include_router(analysis.router)
app.include_router(ws.router)

init_db()
