"""Convert the README demo recordings into GIFs. See RECORDING.md.

Usage: python3 docs/media/make_gifs.py RECORDINGS_DIR [CLIP ...]

RECORDINGS_DIR holds one `<clip>.mov` per entry in CLIPS. Each clip is a list
of segments (start, end, speed, hold): the segment plays [start, end) at
`speed`, then freezes its last frame for `hold` seconds. The timings below
belong to the current takes; update them after re-recording.
"""
import os
import subprocess
import sys

OUT = os.path.dirname(os.path.abspath(__file__))
FPS = 15
HOLD = 1.5
END = 999  # past the end of any clip

# The grid clips (ask, translate, jargon, prompt) share a 1424x1236 crop so
# the README's 2x2 table lines up.
# name: (crop "w:h:x:y" or None, output width, segments)
CLIPS = {
    "hero":      (None,             960, [(0, 6.6, 1, HOLD), (6.6, END, 1, 0)]),
    "ask":       (None,             640, [(0, 6.6, 1, HOLD), (6.6, END, 1, 0)]),
    "translate": ("1424:1236:80:0", 640, [(0, 9.2, 1, HOLD), (9.2, END, 1, 0)]),
    "jargon":    ("1424:1236:70:0", 640, [(0, 4.4, 1, HOLD), (4.4, END, 1, 0)]),
    "prompt":    ("1424:1236:0:0",  640, [(0, 13.6, 1, HOLD), (13.6, END, 1, 0)]),
    # Settings editing plays at 1.5x; it's the slowest stretch.
    "presets":   (None,             800, [(0, 1.0, 1, 0), (1.0, 13.8, 1.5, 0),
                                          (13.8, 18.1, 1, HOLD), (18.1, END, 1, 0)]),
}


def build(recordings, name):
    crop, width, segments = CLIPS[name]
    pre = (f"crop={crop}," if crop else "") + f"fps={FPS}"
    n = len(segments)
    graph = [f"[0:v]{pre},split={n}" + "".join(f"[in{i}]" for i in range(n))]
    for i, (start, end, speed, hold) in enumerate(segments):
        chain = f"[in{i}]trim=start={start}:end={end},setpts=(PTS-STARTPTS)/{speed}"
        if hold:
            chain += f",tpad=stop_mode=clone:stop_duration={hold}"
        graph.append(chain + f"[s{i}]")
    graph.append("".join(f"[s{i}]" for i in range(n))
                 + f"concat=n={n}:v=1:a=0,fps={FPS},scale={width}:-1:flags=lanczos,split[a][b]")
    graph.append("[a]palettegen=stats_mode=diff[p]")
    graph.append("[b][p]paletteuse=dither=bayer:bayer_scale=5:diff_mode=rectangle")
    out = os.path.join(OUT, f"{name}.gif")
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", os.path.join(recordings, f"{name}.mov"),
                    "-filter_complex", ";".join(graph), "-loop", "0", out], check=True)
    return out


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    recordings = os.path.expanduser(sys.argv[1])
    for name in sys.argv[2:] or CLIPS:
        path = build(recordings, name)
        print(f"{name}.gif  {os.path.getsize(path) / 1e6:.1f} MB")
