CCTV videos (simulation). All optional: until a file exists the screen shows an animated "NO SIGNAL" / "CLIP PLACEHOLDER".

1) cctv_simulation.mp4
   The "live" camera on the dashboard and Gate Monitor. MP4 (H.264), muted loop, ideally 720p and under 10 MB
   (InfinityFree per-file upload limit).

2) 5 second gate clips (entry and exit)
   Every entry and exit in the audit log, and every vehicle on the On Campus page, has a "5s clip" button.
   - cctv_clip_placeholder.mp4     one shared 5 second clip, shown for every passage. Add this one file first.
   - cctv_clips/log-<id>.mp4       optional clip for one specific passage, where <id> is the gate log id
                                   (shown as "Audit Log ID" in the Inspect drawer). Looked up before the shared clip.
   MP4 (H.264), 5 seconds, muted, ideally 480p-720p and under 2 MB each.
