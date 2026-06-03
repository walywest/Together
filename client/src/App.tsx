import { useState } from 'react'
import Lobby from './components/Lobby'
import VideoPlayer from './components/VideoPlayer'
import { useVideoSync } from './hooks/useVideoSync'

type RoomProps = { roomId: string; onLeave: () => void }

function Room({ roomId, onLeave }: RoomProps) {
  const { connected, users, userId, videoUrl, setVideoUrl, remoteAction, emit } =
    useVideoSync(roomId)
  const [urlInput, setUrlInput] = useState('')

  const handleSetVideo = () => {
    const url = urlInput.trim()
    if (!url) return
    setVideoUrl(url)
    emit({ type: 'set_video', videoUrl: url })
    setUrlInput('')
  }

  const shareLink = `${window.location.origin}${window.location.pathname}?room=${encodeURIComponent(roomId)}`

  return (
    <div className="flex h-dvh flex-col">
      <header className="flex flex-shrink-0 items-center justify-between gap-3 border-b border-line bg-surface px-5 py-2.5">
        <div className="flex items-center gap-2.5">
          <span className="text-[0.72rem] font-semibold uppercase tracking-wider text-muted">
            Room
          </span>
          <code className="rounded-md border border-line bg-app px-2 py-0.5 font-mono text-[0.82rem] text-accent">
            {roomId}
          </code>
          <button
            onClick={() => navigator.clipboard.writeText(shareLink)}
            title="Copy invite link"
            className="rounded-md border border-line px-2 py-0.5 text-[0.78rem] text-muted transition-colors hover:text-app-text"
          >
            Copy link
          </button>
        </div>
        <div className="flex items-center gap-2.5">
          <span
            className={`h-[7px] w-[7px] flex-shrink-0 rounded-full ${connected ? 'bg-app-green' : 'bg-app-red'}`}
          />
          <span className="text-[0.82rem] text-muted">
            {users.length} {users.length === 1 ? 'person' : 'people'}
          </span>
          <button
            onClick={onLeave}
            className="rounded-md border border-app-red px-2.5 py-0.5 text-[0.78rem] text-app-red transition-colors hover:bg-app-red hover:text-white"
          >
            Leave
          </button>
        </div>
      </header>

      <main className="flex flex-1 overflow-hidden">
        <section className="flex min-w-0 flex-1 flex-col gap-3 overflow-hidden p-3.5">
          <div className="flex gap-2">
            <input
              value={urlInput}
              onChange={(e) => setUrlInput(e.target.value)}
              onKeyDown={(e) => e.key === 'Enter' && handleSetVideo()}
              placeholder="Paste a video URL (.mp4, .webm, .ogg…)"
              className="flex-1 rounded-lg border border-line bg-app px-3.5 py-2 text-sm outline-none transition-colors focus:border-accent"
            />
            <button
              onClick={handleSetVideo}
              className="flex-shrink-0 rounded-lg bg-accent px-4 py-2 text-sm font-semibold text-white transition-colors hover:bg-accent-hover"
            >
              Load
            </button>
          </div>

          {videoUrl ? (
            <VideoPlayer videoUrl={videoUrl} remoteAction={remoteAction} emit={emit} />
          ) : (
            <div className="flex min-h-0 flex-1 items-center justify-center rounded-xl bg-surface">
              <div className="flex flex-col items-center gap-3 text-muted">
                <span className="text-4xl opacity-20">▶</span>
                <p className="max-w-[260px] text-center text-[0.88rem]">
                  Paste a direct video URL above to start watching together
                </p>
              </div>
            </div>
          )}
        </section>

        <aside className="flex w-[210px] flex-shrink-0 flex-col gap-2.5 overflow-y-auto border-l border-line bg-surface px-3.5 py-4">
          <p className="text-[0.72rem] font-semibold uppercase tracking-wider text-muted">
            Watching now
          </p>
          <ul className="m-0 flex list-none flex-col gap-1.5 p-0">
            {users.map((uid) => (
              <li
                key={uid}
                className={`flex items-center gap-2 text-[0.83rem] ${uid === userId ? 'text-app-text' : 'text-muted'}`}
              >
                <span className="flex h-[26px] w-[26px] flex-shrink-0 items-center justify-center rounded-full bg-accent text-[0.72rem] font-bold text-white">
                  {uid[0].toUpperCase()}
                </span>
                <span className="flex-1 overflow-hidden text-ellipsis whitespace-nowrap font-mono text-[0.78rem]">
                  {uid}
                </span>
                {uid === userId && (
                  <span className="flex-shrink-0 rounded bg-accent px-1.5 py-[0.1rem] text-[0.65rem] font-bold text-white">
                    you
                  </span>
                )}
              </li>
            ))}
          </ul>
        </aside>
      </main>
    </div>
  )
}

export default function App() {
  const params = new URLSearchParams(window.location.search)
  const [roomId, setRoomId] = useState(params.get('room') ?? '')
  const [inRoom, setInRoom] = useState(!!params.get('room'))

  const joinRoom = (id: string) => {
    setRoomId(id)
    setInRoom(true)
    window.history.pushState({}, '', `?room=${encodeURIComponent(id)}`)
  }

  const leaveRoom = () => {
    setInRoom(false)
    setRoomId('')
    window.history.pushState({}, '', window.location.pathname)
  }

  return inRoom ? <Room roomId={roomId} onLeave={leaveRoom} /> : <Lobby onJoin={joinRoom} />
}
