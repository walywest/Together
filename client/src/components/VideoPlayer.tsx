import { useRef, useEffect, useState, useCallback } from 'react'
import type { ChangeEvent } from 'react'
import type { RemoteAction, ClientMessage } from '../hooks/useVideoSync'

const SEEK_THRESHOLD = 1.5

function formatTime(s: number) {
  if (!isFinite(s)) return '0:00'
  const m = Math.floor(s / 60)
  const sec = Math.floor(s % 60)
  return `${m}:${sec.toString().padStart(2, '0')}`
}

type VideoPlayerProps = {
  videoUrl: string
  remoteAction: RemoteAction | null
  emit: (msg: ClientMessage) => void
}

export default function VideoPlayer({ videoUrl, remoteAction, emit }: VideoPlayerProps) {
  const videoRef = useRef<HTMLVideoElement>(null)
  const isSyncing = useRef(false)
  const [isPlaying, setIsPlaying] = useState(false)
  const [currentTime, setCurrentTime] = useState(0)
  const [duration, setDuration] = useState(0)
  const [volume, setVolume] = useState(1)
  const [buffered, setBuffered] = useState(0)

  useEffect(() => {
    const video = videoRef.current
    if (!remoteAction || !video) return

    isSyncing.current = true
    const { type, currentTime: t } = remoteAction

    if (type === 'play') {
      if (Math.abs(video.currentTime - t) > SEEK_THRESHOLD) video.currentTime = t
      video
        .play()
        .catch(() => {})
        .finally(() => {
          isSyncing.current = false
        })
    } else if (type === 'pause') {
      if (Math.abs(video.currentTime - t) > SEEK_THRESHOLD) video.currentTime = t
      video.pause()
      isSyncing.current = false
    } else if (type === 'seek') {
      video.currentTime = t
      isSyncing.current = false
    }
  }, [remoteAction])

  const handlePlay = useCallback(() => {
    setIsPlaying(true)
    if (!isSyncing.current) {
      emit({ type: 'play', currentTime: videoRef.current?.currentTime ?? 0 })
    }
  }, [emit])

  const handlePause = useCallback(() => {
    setIsPlaying(false)
    if (!isSyncing.current) {
      emit({ type: 'pause', currentTime: videoRef.current?.currentTime ?? 0 })
    }
  }, [emit])

  const handleSeeked = useCallback(() => {
    if (!isSyncing.current) {
      emit({ type: 'seek', currentTime: videoRef.current?.currentTime ?? 0 })
    }
  }, [emit])

  const handleTimeUpdate = useCallback(() => {
    const video = videoRef.current
    if (!video) return
    setCurrentTime(video.currentTime)
    if (video.buffered.length > 0 && video.duration) {
      setBuffered((video.buffered.end(video.buffered.length - 1) / video.duration) * 100)
    }
  }, [])

  const handleLoadedMetadata = useCallback(() => {
    setDuration(videoRef.current?.duration ?? 0)
  }, [])

  const togglePlay = () => {
    const video = videoRef.current
    if (!video) return
    if (video.paused) video.play()
    else video.pause()
  }

  const handleSeekChange = (e: ChangeEvent<HTMLInputElement>) => {
    const video = videoRef.current
    if (!video) return
    video.currentTime = (Number(e.target.value) / 1000) * duration
  }

  const handleVolumeChange = (e: ChangeEvent<HTMLInputElement>) => {
    const v = parseFloat(e.target.value)
    setVolume(v)
    if (videoRef.current) videoRef.current.volume = v
  }

  const handleFullscreen = () => {
    videoRef.current?.requestFullscreen?.()
  }

  const progress = duration ? (currentTime / duration) * 1000 : 0

  return (
    <div className="flex min-h-0 flex-1 flex-col overflow-hidden rounded-xl bg-black">
      <video
        ref={videoRef}
        src={videoUrl}
        onPlay={handlePlay}
        onPause={handlePause}
        onSeeked={handleSeeked}
        onTimeUpdate={handleTimeUpdate}
        onLoadedMetadata={handleLoadedMetadata}
        onClick={togglePlay}
        className="block min-h-0 w-full flex-1 cursor-pointer bg-black object-contain"
      />
      <div className="flex flex-shrink-0 items-center gap-2.5 border-t border-line bg-surface px-3.5 py-2">
        <button
          onClick={togglePlay}
          title={isPlaying ? 'Pause' : 'Play'}
          className="flex-shrink-0 text-[1.05rem] leading-none text-app-text"
        >
          {isPlaying ? '⏸' : '▶'}
        </button>

        <div className="relative flex h-4 flex-1 items-center">
          <div className="pointer-events-none absolute inset-x-0 top-1/2 h-1 -translate-y-1/2 overflow-hidden rounded bg-line">
            <div
              className="absolute inset-y-0 left-0 rounded bg-surface-2"
              style={{ width: `${buffered}%` }}
            />
            <div
              className="absolute inset-y-0 left-0 rounded bg-accent"
              style={{ width: `${(progress / 10).toFixed(2)}%` }}
            />
          </div>
          <input
            type="range"
            min={0}
            max={1000}
            value={Math.round(progress)}
            onChange={handleSeekChange}
            className="relative z-10 w-full cursor-pointer border-none bg-transparent"
          />
        </div>

        <span className="flex-shrink-0 whitespace-nowrap text-[0.77rem] tabular-nums text-muted">
          {formatTime(currentTime)} / {formatTime(duration)}
        </span>

        <div className="flex flex-shrink-0 items-center gap-1.5">
          <span className="text-[0.8rem]">{volume === 0 ? '🔇' : '🔊'}</span>
          <input
            type="range"
            min={0}
            max={1}
            step={0.05}
            value={volume}
            onChange={handleVolumeChange}
            className="w-16 cursor-pointer"
          />
        </div>

        <button
          onClick={handleFullscreen}
          title="Fullscreen"
          className="flex-shrink-0 text-base leading-none text-muted transition-colors hover:text-app-text"
        >
          ⛶
        </button>
      </div>
    </div>
  )
}
