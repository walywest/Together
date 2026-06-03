import { useEffect, useRef, useState, useCallback } from 'react'

const WS_BASE = import.meta.env.VITE_WS_URL ?? 'ws://localhost:8000/ws'

export type RemoteAction = {
  type: 'play' | 'pause' | 'seek'
  currentTime: number
  ts: number
}

export type ClientMessage =
  | { type: 'play'; currentTime: number }
  | { type: 'pause'; currentTime: number }
  | { type: 'seek'; currentTime: number }
  | { type: 'set_video'; videoUrl: string }

type ServerMessage =
  | {
      type: 'sync'
      userId: string
      users: string[]
      videoUrl: string
      isPlaying: boolean
      currentTime: number
    }
  | { type: 'play'; currentTime: number }
  | { type: 'pause'; currentTime: number }
  | { type: 'seek'; currentTime: number }
  | { type: 'set_video'; videoUrl: string }
  | { type: 'user_joined'; users: string[] }
  | { type: 'user_left'; users: string[] }

export function useVideoSync(roomId: string) {
  const wsRef = useRef<WebSocket | null>(null)
  const [connected, setConnected] = useState(false)
  const [users, setUsers] = useState<string[]>([])
  const [userId, setUserId] = useState<string | null>(null)
  const [videoUrl, setVideoUrl] = useState('')
  const [remoteAction, setRemoteAction] = useState<RemoteAction | null>(null)

  useEffect(() => {
    if (!roomId) return

    const ws = new WebSocket(`${WS_BASE}/${roomId}`)
    wsRef.current = ws

    ws.onopen = () => setConnected(true)
    ws.onclose = () => setConnected(false)

    ws.onmessage = ({ data }) => {
      const msg: ServerMessage = JSON.parse(data)
      switch (msg.type) {
        case 'sync':
          setUserId(msg.userId)
          setUsers(msg.users)
          setVideoUrl(msg.videoUrl)
          if (msg.videoUrl) {
            setRemoteAction({
              type: msg.isPlaying ? 'play' : 'pause',
              currentTime: msg.currentTime,
              ts: Date.now(),
            })
          }
          break
        case 'play':
          setRemoteAction({ type: 'play', currentTime: msg.currentTime, ts: Date.now() })
          break
        case 'pause':
          setRemoteAction({ type: 'pause', currentTime: msg.currentTime, ts: Date.now() })
          break
        case 'seek':
          setRemoteAction({ type: 'seek', currentTime: msg.currentTime, ts: Date.now() })
          break
        case 'set_video':
          setVideoUrl(msg.videoUrl)
          setRemoteAction({ type: 'pause', currentTime: 0, ts: Date.now() })
          break
        case 'user_joined':
        case 'user_left':
          setUsers(msg.users)
          break
      }
    }

    return () => ws.close()
  }, [roomId])

  const emit = useCallback((msg: ClientMessage) => {
    if (wsRef.current?.readyState === WebSocket.OPEN) {
      wsRef.current.send(JSON.stringify(msg))
    }
  }, [])

  return { connected, users, userId, videoUrl, setVideoUrl, remoteAction, emit }
}
