import { useState } from 'react'

const words = {
  adj: ['swift', 'cool', 'lazy', 'happy', 'cosmic', 'neon', 'quiet', 'bold', 'wild', 'calm'],
  noun: ['panda', 'tiger', 'eagle', 'wizard', 'comet', 'pixel', 'spark', 'ghost', 'wolf', 'fox'],
}
const rand = (arr: string[]) => arr[Math.floor(Math.random() * arr.length)]
const genId = () =>
  `${rand(words.adj)}-${rand(words.noun)}-${Math.floor(Math.random() * 900) + 100}`

type LobbyProps = { onJoin: (id: string) => void }

export default function Lobby({ onJoin }: LobbyProps) {
  const [roomId, setRoomId] = useState(genId)

  const handleJoin = () => {
    const id = roomId.trim()
    if (id) onJoin(id)
  }

  return (
    <div className="flex flex-1 items-center justify-center p-6">
      <div className="flex w-full max-w-[400px] flex-col gap-6 rounded-2xl border border-line bg-surface p-8 sm:p-9">
        <div className="flex items-center gap-2">
          <span className="flex h-9 w-9 items-center justify-center rounded-lg bg-accent text-base text-white">
            ▶
          </span>
          <h1 className="text-2xl font-bold">Together</h1>
        </div>
        <p className="text-[0.88rem] leading-relaxed text-muted">
          Watch videos in sync with anyone, anywhere.
        </p>

        <div className="flex flex-col gap-1.5">
          <label
            htmlFor="room-id"
            className="text-[0.73rem] font-semibold uppercase tracking-wider text-muted"
          >
            Room ID
          </label>
          <div className="flex gap-1.5">
            <input
              id="room-id"
              value={roomId}
              onChange={(e) => setRoomId(e.target.value)}
              onKeyDown={(e) => e.key === 'Enter' && handleJoin()}
              placeholder="my-room"
              spellCheck={false}
              autoFocus
              className="flex-1 rounded-lg border border-line bg-app px-3.5 py-2 text-sm outline-none transition-colors focus:border-accent"
            />
            <button
              onClick={() => setRoomId(genId())}
              title="Generate new ID"
              className="flex-shrink-0 rounded-lg border border-line bg-surface-2 px-3.5 py-2 text-base transition-colors hover:bg-line"
            >
              ↺
            </button>
          </div>
          <p className="text-[0.78rem] text-muted">
            Share this ID with others to watch together.
          </p>
        </div>

        <button
          onClick={handleJoin}
          className="w-full rounded-lg bg-accent py-3 font-semibold text-white transition-colors hover:bg-accent-hover"
        >
          Join Room
        </button>
      </div>
    </div>
  )
}
