from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
import json
import uuid

app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


class Room:
    def __init__(self):
        self.clients: dict[str, WebSocket] = {}
        self.is_playing: bool = False
        self.current_time: float = 0.0
        self.video_url: str = ""

    async def broadcast(self, message , exclude: str | None = None):
        dead = []
        for uid, ws in self.clients.items():
            if uid == exclude:
                continue
            try:
                await ws.send_text(json.dumps(message))
            except Exception:
                dead.append(uid)
        for uid in dead:
            self.clients.pop(uid, None)


rooms: dict[str, Room] = {}


@app.websocket("/ws/{room_id}")
async def ws_endpoint(websocket: WebSocket, room_id: str):
    await websocket.accept()
    user_id = str(uuid.uuid4())[:8]

    if room_id not in rooms:
        rooms[room_id] = Room()
    room = rooms[room_id]
    room.clients[user_id] = websocket

    await websocket.send_text(json.dumps({
        "type": "sync",
        "userId": user_id,
        "isPlaying": room.is_playing,
        "currentTime": room.current_time,
        "videoUrl": room.video_url,
        "users": list(room.clients.keys()),
    }))

    await room.broadcast(
        {"type": "user_joined", "userId": user_id, "users": list(room.clients.keys())},
        exclude=user_id,
    )

    try:
        while True:
            raw = await websocket.receive_text()
            msg = json.loads(raw)
            t = msg.get("type")

            if t == "play":
                room.is_playing = True
                room.current_time = msg.get("currentTime", room.current_time)
                await room.broadcast(
                    {"type": "play", "currentTime": room.current_time, "sender": user_id},
                    exclude=user_id,
                )

            elif t == "pause":
                room.is_playing = False
                room.current_time = msg.get("currentTime", room.current_time)
                await room.broadcast(
                    {"type": "pause", "currentTime": room.current_time, "sender": user_id},
                    exclude=user_id,
                )

            elif t == "seek":
                room.current_time = msg.get("currentTime", room.current_time)
                await room.broadcast(
                    {"type": "seek", "currentTime": room.current_time, "sender": user_id},
                    exclude=user_id,
                )

            elif t == "set_video":
                room.video_url = msg.get("videoUrl", "")
                room.is_playing = False
                room.current_time = 0.0
                await room.broadcast(
                    {"type": "set_video", "videoUrl": room.video_url, "sender": user_id},
                    exclude=user_id,
                )

    except WebSocketDisconnect:
        room.clients.pop(user_id, None)
        if not room.clients:
            rooms.pop(room_id, None)
        else:
            await room.broadcast(
                {"type": "user_left", "userId": user_id, "users": list(room.clients.keys())}
            )
