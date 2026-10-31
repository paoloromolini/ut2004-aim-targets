# Generates the hit "ding" (16-bit mono PCM WAV). Original sound, no third-party material.
import math, struct, wave, sys
out = sys.argv[1]
rate = 44100
dur = 0.22
n = int(rate * dur)
frames = bytearray()
for i in range(n):
    t = i / rate
    env = math.exp(-t * 20.0) * min(1.0, t / 0.002)          # 2 ms attack, fast decay
    s = 0.60 * math.sin(2 * math.pi * 1175.0 * t)             # D6
    s += 0.30 * math.sin(2 * math.pi * 1760.0 * t)            # A6
    s += 0.12 * math.sin(2 * math.pi * 2349.0 * t)            # D7
    frames += struct.pack('<h', int(max(-1.0, min(1.0, s * env * 0.8)) * 32000))
with wave.open(out, 'wb') as w:
    w.setnchannels(1); w.setsampwidth(2); w.setframerate(rate); w.writeframes(bytes(frames))
