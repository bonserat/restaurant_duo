"""Tổng hợp toàn bộ âm thanh cho game (không dùng file có bản quyền).

Chạy:  python3 tools/make_sounds.py
Kết quả: assets/sfx/*.wav  và  assets/music/*.wav
"""
import os
import numpy as np
from scipy.io import wavfile
from scipy.signal import lfilter, butter

ROOT = os.path.join(os.path.dirname(__file__), '..', 'assets')
SFX_SR = 22050
MUS_SR = 22050
rng = np.random.default_rng(7)


# ------------------------------------------------------------------ tiện ích
def note_hz(n):
    """n: số MIDI"""
    return 440.0 * 2 ** ((n - 69) / 12)


NOTE = {'C': 0, 'C#': 1, 'Db': 1, 'D': 2, 'D#': 3, 'Eb': 3, 'E': 4, 'F': 5, 'F#': 6, 'Gb': 6,
        'G': 7, 'G#': 8, 'Ab': 8, 'A': 9, 'A#': 10, 'Bb': 10, 'B': 11}


def m(name):
    """'C5' -> số MIDI"""
    pitch, octv = (name[:-1], int(name[-1]))
    return 12 * (octv + 1) + NOTE[pitch]


def env(n, sr, a=0.005, d=0.1, s=0.6, r=0.1):
    t = np.arange(n) / sr
    e = np.ones(n) * s
    a_n, d_n, r_n = int(a * sr), int(d * sr), int(r * sr)
    a_n = max(a_n, 1)
    e[:a_n] = np.linspace(0, 1, a_n)
    if d_n > 0:
        e[a_n:a_n + d_n] = np.linspace(1, s, len(e[a_n:a_n + d_n]))
    if r_n > 0 and r_n < n:
        e[-r_n:] *= np.linspace(1, 0, r_n)
    return e


def expdecay(n, sr, tau):
    return np.exp(-np.arange(n) / sr / tau)


def sine(f, dur, sr, phase=0.0):
    t = np.arange(int(dur * sr)) / sr
    return np.sin(2 * np.pi * f * t + phase)


def tri(f, dur, sr):
    t = np.arange(int(dur * sr)) / sr
    return 2 * np.abs(2 * ((t * f) % 1) - 1) - 1


def square(f, dur, sr, duty=0.5):
    t = np.arange(int(dur * sr)) / sr
    return np.where((t * f) % 1 < duty, 1.0, -1.0)


def sweep(f0, f1, dur, sr, kind='sine'):
    n = int(dur * sr)
    f = np.geomspace(f0, f1, n)
    ph = 2 * np.pi * np.cumsum(f) / sr
    return np.sin(ph) if kind == 'sine' else np.sign(np.sin(ph))


def noise(dur, sr):
    return rng.uniform(-1, 1, int(dur * sr))


def lowpass(x, sr, fc):
    b, a = butter(2, min(fc / (sr / 2), 0.99), 'low')
    return lfilter(b, a, x)


def highpass(x, sr, fc):
    b, a = butter(2, min(fc / (sr / 2), 0.99), 'high')
    return lfilter(b, a, x)


def pluck(f, dur, sr, bright=0.5, decay=0.996):
    """Karplus-Strong: tiếng gảy dây (ukulele, đàn tranh, koto)"""
    n = int(dur * sr)
    p = max(2, int(sr / f))
    buf = rng.uniform(-1, 1, p)
    buf = lowpass(buf, sr, 2000 + 6000 * bright)
    out = np.zeros(n)
    for i in range(n):
        out[i] = buf[i % p]
        buf[i % p] = decay * 0.5 * (buf[i % p] + buf[(i + 1) % p])
    return out


def mix_into(track, sig, start, gain=1.0):
    s = int(start)
    if s >= len(track):
        return
    e = min(len(track), s + len(sig))
    track[s:e] += sig[:e - s] * gain


def mix_loop(track, sig, start, gain=1.0):
    """chèn có cuộn vòng: phần đuôi tràn ra sẽ quay về đầu → nhạc lặp liền mạch"""
    s = int(start) % len(track)
    n = len(sig)
    first = min(n, len(track) - s)
    track[s:s + first] += sig[:first] * gain
    if n > first:
        rest = sig[first:]
        track[:len(rest)] += rest * gain


def norm(x, peak=0.9):
    mx = np.max(np.abs(x)) or 1
    return x / mx * peak


def save_wav(name, x, sr=SFX_SR, peak=0.9):
    os.makedirs(os.path.join(ROOT, 'sfx'), exist_ok=True)
    x = norm(x, peak)
    fade = min(len(x), int(0.005 * sr))
    x[-fade:] *= np.linspace(1, 0, fade)
    wavfile.write(os.path.join(ROOT, 'sfx', name + '.wav'), sr, (x * 32767).astype(np.int16))


def save_music(name, x, sr=MUS_SR):
    os.makedirs(os.path.join(ROOT, 'music'), exist_ok=True)
    x = norm(x, 0.85)
    # WAV để lặp liền mạch (AAC/MP3 có khoảng lặng đầu file gây "khựng" khi lặp)
    wavfile.write(os.path.join(ROOT, 'music', name + '.wav'), sr, (x * 32767).astype(np.int16))


# ------------------------------------------------------------------ nhạc cụ
def bell(f, dur, sr):
    n = int(dur * sr)
    x = (sine(f, dur, sr) + 0.5 * sine(f * 2.0, dur, sr) + 0.25 * sine(f * 3.01, dur, sr) + 0.15 * sine(f * 4.2, dur, sr))
    return x[:n] * expdecay(n, sr, dur / 3)


def epiano(f, dur, sr):
    n = int(dur * sr)
    t = np.arange(n) / sr
    x = sine(f, dur, sr) + 0.35 * sine(2 * f, dur, sr) * expdecay(n, sr, 0.15)
    trem = 1 + 0.15 * np.sin(2 * np.pi * 4.5 * t)
    return x * trem * expdecay(n, sr, max(0.25, dur / 2)) * env(n, sr, 0.004, 0, 1, 0.05)


def flute(f, dur, sr):
    n = int(dur * sr)
    t = np.arange(n) / sr
    vib = 1 + 0.006 * np.sin(2 * np.pi * 5.5 * t) * np.clip(t * 3, 0, 1)
    ph = 2 * np.pi * np.cumsum(f * vib) / sr
    x = np.sin(ph) + 0.15 * np.sin(2 * ph) + 0.02 * lowpass(noise(dur, sr), sr, 3000)
    return x * env(n, sr, 0.06, 0.1, 0.8, 0.12)


def steel(f, dur, sr):
    n = int(dur * sr)
    x = sine(f, dur, sr) + 0.6 * sine(f * 2.0, dur, sr) * expdecay(n, sr, 0.2) + 0.3 * sine(f * 3.0, dur, sr) * expdecay(n, sr, 0.1)
    return x * expdecay(n, sr, 0.45) * env(n, sr, 0.003, 0, 1, 0.04)


def softsq(f, dur, sr):
    n = int(dur * sr)
    x = lowpass(square(f, dur, sr, 0.3), sr, 2500)
    return x * env(n, sr, 0.01, 0.08, 0.55, 0.06)


def pad(freqs, dur, sr):
    n = int(dur * sr)
    x = np.zeros(n)
    for f in freqs:
        x += tri(f, dur, sr) + 0.5 * tri(f * 1.003, dur, sr)
    x = lowpass(x, sr, 1400)
    return x * env(n, sr, 0.4, 0.2, 0.8, 0.5) / max(1, len(freqs))


def bass(f, dur, sr):
    n = int(dur * sr)
    x = sine(f, dur, sr) + 0.3 * tri(f, dur, sr)
    return x * env(n, sr, 0.005, 0.08, 0.7, 0.05)


def kick(sr):
    x = sweep(140, 45, 0.18, sr)
    return x * expdecay(len(x), sr, 0.06)


def snare(sr, soft=1.0):
    x = highpass(noise(0.15, sr), sr, 1500) * 0.7 + sine(190, 0.15, sr) * 0.3
    return x * expdecay(len(x), sr, 0.05) * soft


def hat(sr, open_=False):
    x = highpass(noise(0.12 if open_ else 0.04, sr), sr, 6000)
    return x * expdecay(len(x), sr, 0.04 if open_ else 0.012)


def shaker(sr):
    x = highpass(noise(0.07, sr), sr, 4000)
    return x * env(len(x), sr, 0.02, 0.02, 0.6, 0.03)


def tom(f, sr):
    x = sweep(f * 1.4, f, 0.25, sr)
    return x * expdecay(len(x), sr, 0.09)


def brush(sr):
    x = lowpass(highpass(noise(0.18, sr), sr, 2500), sr, 7000)
    return x * env(len(x), sr, 0.05, 0.05, 0.5, 0.08)


def chirp(sr):
    x = np.concatenate([sweep(2600, 4200, 0.06, sr), np.zeros(int(0.03 * sr)), sweep(2800, 4600, 0.05, sr)])
    return x * 0.5


# ------------------------------------------------------------------ hiệu ứng
def make_sfx():
    sr = SFX_SR
    # chuông cửa khi khách vào
    a = bell(note_hz(m('E6')), 0.5, sr)
    b = bell(note_hz(m('C6')), 0.8, sr)
    x = np.zeros(int(1.0 * sr)); mix_into(x, a, 0); mix_into(x, b, 0.18 * sr)
    save_wav('door', x, peak=0.6)
    # nhận order: tiếng bút + blip
    x = np.zeros(int(0.25 * sr))
    mix_into(x, highpass(noise(0.02, sr), sr, 3000) * 0.6, 0)
    mix_into(x, softsq(note_hz(m('A5')), 0.08, sr), 0.03 * sr)
    mix_into(x, softsq(note_hz(m('E6')), 0.1, sr), 0.11 * sr)
    save_wav('order', x, peak=0.55)
    # thả nguyên liệu: tiếng "bõm"
    x = sweep(900, 300, 0.12, sr) * expdecay(int(0.12 * sr), sr, 0.04)
    save_wav('plop', x, peak=0.6)
    # nhầm nguyên liệu
    x = np.concatenate([lowpass(square(180, 0.12, sr), sr, 1500), np.zeros(int(0.03 * sr)), lowpass(square(140, 0.2, sr), sr, 1500)])
    save_wav('wrong', x * env(len(x), sr, 0.005, 0.05, 0.8, 0.05), peak=0.5)
    # bắt đầu nấu: xèo xèo
    x = lowpass(highpass(noise(0.6, sr), sr, 2500), sr, 9000)
    x *= env(len(x), sr, 0.05, 0.1, 0.6, 0.3) * (1 + 0.3 * np.sin(np.arange(len(x)) / sr * 2 * np.pi * 11))
    save_wav('sizzle', x, peak=0.35)
    # nấu xong: ding!
    x = bell(note_hz(m('A6')), 1.0, sr)
    mix_into(x, bell(note_hz(m('E7')), 0.8, sr), 0, 0.5)
    save_wav('ding', x, peak=0.7)
    # món cháy
    x = lowpass(noise(0.8, sr), sr, 1200) * expdecay(int(0.8 * sr), sr, 0.3)
    x += 0.5 * sweep(300, 120, 0.8, sr) * expdecay(int(0.8 * sr), sr, 0.3)
    save_wav('burn', x, peak=0.5)
    # mang món ra quầy: vút
    n = int(0.3 * sr)
    nz = noise(0.3, sr)
    x = np.zeros(n)
    for i, fc in enumerate(np.geomspace(800, 5000, 6)):
        seg = slice(i * n // 6, (i + 1) * n // 6)
        x[seg] = highpass(nz, sr, fc)[seg]
    save_wav('whoosh', x * env(n, sr, 0.05, 0.05, 0.8, 0.15), peak=0.4)
    # đặt món lên bàn: pop vui
    x = sweep(500, 1300, 0.08, sr) * expdecay(int(0.08 * sr), sr, 0.05)
    y = np.zeros(int(0.35 * sr)); mix_into(y, x, 0); mix_into(y, bell(note_hz(m('G6')), 0.25, sr) * 0.5, 0.06 * sr)
    save_wav('serve', y, peak=0.6)
    # khách trả tiền: leng keng
    x = np.zeros(int(0.5 * sr))
    mix_into(x, softsq(note_hz(m('B5')), 0.08, sr), 0)
    mix_into(x, softsq(note_hz(m('E6')), 0.35, sr), 0.08 * sr)
    mix_into(x, bell(note_hz(m('E7')), 0.35, sr) * 0.4, 0.08 * sr)
    save_wav('coin', x, peak=0.55)
    # khách bực bỏ về
    x = lowpass(sweep(260, 150, 0.45, sr, 'square'), sr, 900)
    save_wav('angry', x * env(len(x), sr, 0.01, 0.1, 0.7, 0.1), peak=0.45)
    # dọn bàn: lấp lánh
    x = np.zeros(int(0.7 * sr))
    for i, n_ in enumerate(['C7', 'E7', 'G7', 'C8', 'E8']):
        mix_into(x, bell(note_hz(m(n_)), 0.3, sr) * 0.6, i * 0.05 * sr)
    mix_into(x, highpass(noise(0.25, sr), sr, 5000) * expdecay(int(0.25 * sr), sr, 0.08) * 0.3, 0)
    save_wav('clean', x, peak=0.5)
    # chạm nút
    x = sine(1200, 0.03, sr) * expdecay(int(0.03 * sr), sr, 0.01)
    save_wav('tap', x, peak=0.35)
    # đạt mục tiêu: kèn ngắn
    x = np.zeros(int(1.2 * sr))
    for i, n_ in enumerate(['C5', 'E5', 'G5']):
        mix_into(x, softsq(note_hz(m(n_)), 0.14, sr), i * 0.12 * sr)
    for n_ in ['C6', 'E5', 'G5']:
        mix_into(x, softsq(note_hz(m(n_)), 0.6, sr) * 0.8, 0.36 * sr)
    mix_into(x, bell(note_hz(m('C7')), 0.7, sr) * 0.4, 0.36 * sr)
    save_wav('goal', x, peak=0.6)
    # chiến thắng: fanfare dài
    x = np.zeros(int(2.6 * sr))
    seq = [('G4', 0, .15), ('C5', .15, .15), ('E5', .3, .15), ('G5', .45, .3), ('E5', .75, .15), ('G5', .9, .9)]
    for n_, st, du in seq:
        mix_into(x, softsq(note_hz(m(n_)), du, sr), st * sr)
        mix_into(x, steel(note_hz(m(n_)) * 2, du + 0.2, sr) * 0.3, st * sr)
    for n_ in ['C4', 'E4', 'G4', 'C5']:
        mix_into(x, pad([note_hz(m(n_))], 1.5, sr) * 0.6, 0.9 * sr)
    for i in range(4):
        mix_into(x, snare(sr, 0.6), (0.9 + i * 0.08) * sr)
    mix_into(x, highpass(noise(1.2, sr), sr, 6000) * expdecay(int(1.2 * sr), sr, 0.4) * 0.25, 0.9 * sr)
    save_wav('win', x, peak=0.7)
    # thua: kèn buồn
    x = np.zeros(int(2.2 * sr))
    for i, n_ in enumerate(['G4', 'F#4', 'F4']):
        mix_into(x, lowpass(sweep(note_hz(m(n_)), note_hz(m(n_)) * 0.98, 0.4, sr, 'square'), sr, 1200) * env(int(0.4 * sr), sr, 0.03, 0.1, 0.7, 0.1), i * 0.45 * sr)
    t = np.arange(int(0.9 * sr)) / sr
    f = note_hz(m('E4')) * (1 + 0.03 * np.sin(2 * np.pi * 6 * t)) * np.linspace(1, 0.95, len(t))
    last = lowpass(np.sign(np.sin(2 * np.pi * np.cumsum(f) / sr)), sr, 1000) * env(len(t), sr, 0.03, 0.1, 0.7, 0.3)
    mix_into(x, last, 1.35 * sr)
    save_wav('lose', x, peak=0.5)
    # pháo hoa: bùm + lách tách
    x = np.zeros(int(1.2 * sr))
    mix_into(x, lowpass(noise(0.4, sr), sr, 500) * expdecay(int(0.4 * sr), sr, 0.12), 0)
    for _ in range(25):
        st = rng.uniform(0.1, 1.0)
        mix_into(x, highpass(noise(0.01, sr), sr, 4000) * rng.uniform(0.2, 0.6), st * sr)
    save_wav('firework', x, peak=0.5)
    make_sfx2()


def make_sfx2():
    """Âm thanh cho nấu nhiều công đoạn, sự cố và thú cưng"""
    sr = SFX_SR
    # nhát dao trên thớt
    x = np.zeros(int(0.15 * sr))
    mix_into(x, lowpass(noise(0.03, sr), sr, 2500) * expdecay(int(0.03 * sr), sr, 0.008), 0)
    mix_into(x, sine(180, 0.1, sr) * expdecay(int(0.1 * sr), sr, 0.02) * 0.8, 0)
    save_wav('chop', x, peak=0.7)
    # rắc gia vị: lạo xạo
    x = np.zeros(int(0.25 * sr))
    for k in range(3):
        mix_into(x, highpass(noise(0.04, sr), sr, 5000) * env(int(0.04 * sr), sr, 0.005, 0.01, 0.6, 0.02), k * 0.07 * sr)
    save_wav('shake', x, peak=0.45)
    # vặn núm: tách
    x = highpass(noise(0.015, sr), sr, 3000) * expdecay(int(0.015 * sr), sr, 0.004)
    x = np.concatenate([x, np.zeros(int(0.03 * sr)), x * 0.6])
    save_wav('knob', x, peak=0.5)
    # còi báo cháy
    t = np.arange(int(1.2 * sr)) / sr
    f = 900 + 350 * np.sign(np.sin(2 * np.pi * 3 * t))
    x = lowpass(np.sign(np.sin(2 * np.pi * np.cumsum(f) / sr)), sr, 2500) * env(len(t), sr, 0.01, 0.05, 0.8, 0.1)
    save_wav('alarm', x, peak=0.4)
    # mất điện: tụt áp
    x = sweep(440, 60, 0.7, sr, 'square')
    x = lowpass(x, sr, 1200) * env(len(x), sr, 0.005, 0.1, 0.8, 0.3)
    mix_into(x, highpass(noise(0.05, sr), sr, 3000) * 0.5, 0)
    save_wav('powerdown', x, peak=0.45)
    # chuột kêu chít chít
    x = np.zeros(int(0.4 * sr))
    for k in range(3):
        mix_into(x, sweep(3000, 4200, 0.05, sr) * env(int(0.05 * sr), sr, 0.005, 0.01, 0.8, 0.02), k * 0.11 * sr)
    save_wav('squeak', x, peak=0.4)
    # nước nhỏ giọt
    x = np.zeros(int(0.6 * sr))
    for k in range(2):
        mix_into(x, sweep(1400, 2600, 0.06, sr) * expdecay(int(0.06 * sr), sr, 0.02), k * 0.3 * sr)
    save_wav('drip', x, peak=0.5)
    # khách quát tháo: "hừm!"
    t = np.arange(int(0.45 * sr)) / sr
    f = 160 * (1 + 0.25 * np.exp(-t / 0.1)) * (1 + 0.05 * np.sin(2 * np.pi * 25 * t))
    x = np.sign(np.sin(2 * np.pi * np.cumsum(f) / sr)) * 0.6 + lowpass(noise(0.45, sr), sr, 1500) * 0.3
    x = lowpass(x, sr, 1800) * env(len(t), sr, 0.02, 0.1, 0.7, 0.15)
    save_wav('shout', x, peak=0.45)
    # xử lý xong sự cố: tinh tinh
    x = np.zeros(int(0.6 * sr))
    mix_into(x, bell(note_hz(m('E6')), 0.4, sr), 0)
    mix_into(x, bell(note_hz(m('B6')), 0.45, sr), 0.1 * sr)
    save_wav('fixed', x, peak=0.55)
    # mèo rừ rừ
    t = np.arange(int(0.7 * sr)) / sr
    x = lowpass(noise(0.7, sr), sr, 400) * (0.6 + 0.4 * np.sin(2 * np.pi * 24 * t)) * env(len(t), sr, 0.1, 0.1, 0.8, 0.2)
    save_wav('purr', x, peak=0.5)
    # chó sủa gâu
    x = np.zeros(int(0.45 * sr))
    for k in range(2):
        b = lowpass(sweep(500, 280, 0.12, sr, 'square'), sr, 1500) * env(int(0.12 * sr), sr, 0.005, 0.03, 0.6, 0.04)
        mix_into(x, b, k * 0.2 * sr)
    save_wav('woof', x, peak=0.5)
    # vẹt hót
    x = np.zeros(int(0.4 * sr))
    mix_into(x, sweep(2000, 3200, 0.08, sr), 0)
    mix_into(x, sweep(3200, 2400, 0.08, sr), 0.1 * sr)
    mix_into(x, sweep(2400, 3600, 0.1, sr), 0.2 * sr)
    save_wav('chirp', x * 0.6, peak=0.45)


# ------------------------------------------------------------------ nhạc nền
def song(bpm, bars, sr=MUS_SR):
    beat = 60 / bpm
    total = int(bars * 4 * beat * sr)
    return np.zeros(total), beat


def place_melody(track, notes, beat, sr, inst, gain, start_beat=0):
    """notes: list (tên nốt hoặc None, số phách)"""
    pos = start_beat
    for n_, dur in notes:
        if n_ is not None:
            sig = inst(note_hz(m(n_)), dur * beat * 1.05, sr)
            mix_loop(track, sig, pos * beat * sr, gain)
        pos += dur
    return pos


def chord_notes(root, kind):
    iv = {'M': [0, 4, 7], 'm': [0, 3, 7], 'M7': [0, 4, 7, 11], 'm7': [0, 3, 7, 10], '7': [0, 4, 7, 10]}[kind]
    r = m(root)
    return [r + i for i in iv]


def music_menu():
    sr = MUS_SR
    x, beat = song(92, 8)
    prog = [('C4', 'M'), ('A3', 'm'), ('F3', 'M'), ('G3', 'M')] * 2
    for i, (r, k) in enumerate(prog):
        ns = chord_notes(r, k)
        mix_loop(x, pad([note_hz(n) for n in ns], 4 * beat, sr), i * 4 * beat * sr, 0.5)
        mix_loop(x, bass(note_hz(m(r) - 12), 2 * beat, sr), i * 4 * beat * sr, 0.5)
        mix_loop(x, bass(note_hz(m(r) - 12), 2 * beat, sr), (i * 4 + 2) * beat * sr, 0.4)
        for j in range(8):
            mix_loop(x, bell(note_hz(ns[j % len(ns)] + 12), 0.6, sr), (i * 4 + j * 0.5) * beat * sr, 0.12)
    mel = [('E5', 1), ('G5', 1), ('C6', 2), ('A5', 1), ('G5', 1), ('E5', 2), ('F5', 1), ('A5', 1), ('C6', 1), ('A5', 1), ('G5', 3), (None, 1),
           ('E5', 1), ('G5', 1), ('C6', 2), ('D6', 1), ('C6', 1), ('A5', 2), ('F5', 1), ('E5', 1), ('D5', 1), ('B4', 1), ('C5', 3), (None, 1)]
    place_melody(x, mel, beat, sr, bell, 0.25)
    save_music('menu', x)


def music_classic():
    sr = MUS_SR
    x, beat = song(118, 8)
    prog = [('F3', 'M'), ('D3', 'm'), ('Bb3', 'M'), ('C4', '7')] * 2
    for i, (r, k) in enumerate(prog):
        ns = chord_notes(r, k)
        b0 = i * 4
        for j, off in enumerate([0, 1.5, 2, 3]):
            mix_loop(x, bass(note_hz(m(r) - 12 + (7 if j % 2 else 0)), 0.45 * beat, sr), (b0 + off) * beat * sr, 0.55)
        for off in [0.5, 1.5, 2.5, 3.5]:
            for n_ in ns:
                mix_loop(x, epiano(note_hz(n_ + 12), 0.4 * beat, sr), (b0 + off) * beat * sr, 0.12)
        for off in range(4):
            mix_loop(x, kick(sr) if off % 2 == 0 else snare(sr, 0.5), (b0 + off) * beat * sr, 0.5)
            mix_loop(x, hat(sr), (b0 + off + 0.5) * beat * sr, 0.25)
    mel = [('A5', .5), ('C6', .5), ('A5', .5), ('F5', .5), ('G5', 1), (None, 1),
           ('F5', .5), ('A5', .5), ('D6', 1), ('C6', 1), (None, 1),
           ('Bb5', .5), ('A5', .5), ('G5', .5), ('F5', .5), ('D5', 1), ('F5', 1),
           ('E5', .5), ('G5', .5), ('C6', 1.5), (None, 1.5),
           ('A5', .5), ('C6', .5), ('F6', 1), ('E6', .5), ('D6', .5), ('C6', 1),
           ('D6', .5), ('C6', .5), ('A5', 1), ('F5', 1), (None, 1),
           ('G5', .5), ('A5', .5), ('Bb5', .5), ('D6', .5), ('C6', 1), ('A5', 1),
           ('G5', 1), ('E5', 1), ('F5', 2)]
    place_melody(x, mel, beat, sr, softsq, 0.22)
    save_music('classic', x)


def music_garden():
    sr = MUS_SR
    x, beat = song(96, 8)
    prog = [('G3', 'M'), ('E3', 'm'), ('C3', 'M'), ('D3', 'M')] * 2
    for i, (r, k) in enumerate(prog):
        ns = chord_notes(r, k)
        b0 = i * 4
        mix_loop(x, bass(note_hz(m(r) - 12), 3.5 * beat, sr), b0 * beat * sr, 0.4)
        arp = ns + [ns[1] + 12]
        for j in range(8):
            mix_loop(x, pluck(note_hz(arp[j % 4] + 12), 0.7, sr, 0.4), (b0 + j * 0.5) * beat * sr, 0.25)
        mix_loop(x, shaker(sr), (b0 + 1) * beat * sr, 0.15)
        mix_loop(x, shaker(sr), (b0 + 3) * beat * sr, 0.15)
    for bt in [3.2, 13.7, 22.1, 29.5]:
        mix_loop(x, chirp(sr), bt * beat * sr, 0.12)
    mel = [('D5', 1.5), ('B4', .5), ('D5', 1), ('G5', 1), ('E5', 2), ('D5', 2),
           ('C5', 1), ('E5', 1), ('G5', 1.5), ('F#5', .5), ('E5', 2), ('D5', 2),
           ('B5', 1.5), ('A5', .5), ('G5', 1), ('E5', 1), ('G5', 2), ('B4', 2),
           ('C5', 1), ('E5', 1), ('D5', 1), ('A4', 1), ('G4', 4)]
    place_melody(x, mel, beat, sr, flute, 0.3)
    save_music('garden', x)


def music_beach():
    sr = MUS_SR
    x, beat = song(104, 8)
    prog = [('D4', 'M'), ('G3', 'M'), ('A3', 'M'), ('D4', 'M'), ('B3', 'm'), ('G3', 'M'), ('A3', '7'), ('D4', 'M')]
    for i, (r, k) in enumerate(prog):
        ns = chord_notes(r, k)
        b0 = i * 4
        # ukulele: nhịp đảo "xuống – xuống lên – lên xuống lên"
        for off in [0, 1, 1.5, 2.5, 3, 3.5]:
            for q, n_ in enumerate(ns[:4]):
                mix_loop(x, pluck(note_hz(n_), 0.5, sr, 0.7, 0.993), (b0 + off) * beat * sr + q * 0.012 * sr, 0.12)
        mix_loop(x, bass(note_hz(m(r) - 12), 1.4 * beat, sr), b0 * beat * sr, 0.5)
        mix_loop(x, bass(note_hz(m(r) - 5), 1.4 * beat, sr), (b0 + 2) * beat * sr, 0.4)
        for j in range(8):
            mix_loop(x, shaker(sr), (b0 + j * 0.5) * beat * sr, 0.18 if j % 2 else 0.1)
    mel = [('F#5', 1), ('A5', 1), ('B5', .5), ('A5', 1.5), ('G5', 1), ('B5', 1), ('D6', 2),
           ('C#6', 1), ('B5', .5), ('A5', 1.5), ('F#5', 1), ('E5', 1), ('D5', 2),
           ('F#5', 1), ('A5', 1), ('D6', 1), ('B5', 1), ('G5', 2), ('B5', 2),
           ('A5', 1), ('G5', 1), ('E5', 1), ('C#5', 1), ('D5', 4)]
    place_melody(x, mel, beat, sr, steel, 0.3)
    save_music('beach', x)


def music_night():
    sr = MUS_SR
    x, beat = song(70, 8)
    prog = [('Eb3', 'M7'), ('C3', 'm7'), ('F3', 'm7'), ('Bb3', '7')] * 2
    for i, (r, k) in enumerate(prog):
        ns = chord_notes(r, k)
        b0 = i * 4
        for off in [0, 2.5]:
            for q, n_ in enumerate(ns):
                mix_loop(x, epiano(note_hz(n_ + 12), 2 * beat, sr), (b0 + off) * beat * sr + q * 0.02 * sr, 0.13)
        mix_loop(x, bass(note_hz(m(r) - 12), 1.8 * beat, sr), b0 * beat * sr, 0.45)
        mix_loop(x, bass(note_hz(m(r) - 5), 1.8 * beat, sr), (b0 + 2) * beat * sr, 0.35)
        for off in range(4):
            mix_loop(x, brush(sr), (b0 + off) * beat * sr, 0.12)
            mix_loop(x, hat(sr), (b0 + off + 0.66) * beat * sr, 0.08)
    mel = [('G5', 1.5), ('Bb5', .5), ('D6', 2), ('C6', 1), ('Bb5', 1), ('G5', 2),
           ('Ab5', 1.5), ('C6', .5), ('Eb6', 2), ('D6', 1), ('C6', 1), ('Bb5', 2),
           ('G5', 1), ('F5', 1), ('Eb5', 1), ('G5', 1), ('Bb5', 2), ('C6', 2),
           ('Ab5', 1), ('G5', 1), ('F5', 2), ('Eb5', 4)]
    place_melody(x, mel, beat, sr, bell, 0.22)
    save_music('night', x)


def music_sakura():
    sr = MUS_SR
    x, beat = song(80, 8)
    # thang âm Nhật (Hirajoshi / In): A Bb D E F
    for i in range(8):
        b0 = i * 4
        root = ['A2', 'A2', 'D3', 'A2', 'F2', 'D3', 'E3', 'A2'][i]
        mix_loop(x, pad([note_hz(m(root) + 12), note_hz(m(root) + 19)], 4 * beat, sr), b0 * beat * sr, 0.35)
        mix_loop(x, bass(note_hz(m(root)), 3 * beat, sr), b0 * beat * sr, 0.35)
        mix_loop(x, tom(110, sr), b0 * beat * sr, 0.25)
    mel = [('A4', 1), ('Bb4', 1), ('E5', 2), ('D5', 1), ('Bb4', .5), ('A4', .5), ('E4', 2),
           ('F4', 1), ('A4', 1), ('Bb4', 1), ('D5', 1), ('E5', 3), (None, 1),
           ('A5', 1), ('F5', 1), ('E5', 2), ('D5', 1), ('E5', .5), ('D5', .5), ('Bb4', 2),
           ('A4', 1), ('Bb4', 1), ('F4', 1), ('E4', 1), ('A4', 4)]
    place_melody(x, mel, beat, sr, lambda f, d, s: pluck(f, max(d, 1.2), s, 0.9, 0.997), 0.4)
    save_music('sakura', x)


def tranh(f, dur, sr):
    """đàn tranh: gảy dây + luyến nhẹ lên"""
    n = int(max(dur, 1.0) * sr)
    base = pluck(f, n / sr, sr, 0.8, 0.997)
    # luyến: dịch cao độ nhẹ ở đầu nốt bằng nội suy lại
    t = np.arange(n) / sr
    bend = 1 - 0.03 * np.exp(-t / 0.06)
    idx = np.clip(np.cumsum(bend), 0, n - 1)
    return np.interp(idx, np.arange(n), base)


def music_tet():
    sr = MUS_SR
    x, beat = song(112, 8)
    # ngũ cung Việt: C D F G A
    roots = ['C3', 'F3', 'G3', 'C3', 'A2', 'F3', 'G3', 'C3']
    for i, r in enumerate(roots):
        b0 = i * 4
        mix_loop(x, bass(note_hz(m(r)), 1.5 * beat, sr), b0 * beat * sr, 0.5)
        mix_loop(x, bass(note_hz(m(r) + 7), 1.5 * beat, sr), (b0 + 2) * beat * sr, 0.4)
        # trống: tùng – cắc – tùng tùng – cắc
        mix_loop(x, tom(90, sr), b0 * beat * sr, 0.5)
        mix_loop(x, highpass(noise(0.03, sr), sr, 2500) * 0.8, (b0 + 1) * beat * sr, 0.3)
        mix_loop(x, tom(90, sr), (b0 + 2) * beat * sr, 0.45)
        mix_loop(x, tom(120, sr), (b0 + 2.5) * beat * sr, 0.35)
        mix_loop(x, highpass(noise(0.03, sr), sr, 2500) * 0.8, (b0 + 3) * beat * sr, 0.3)
        mix_loop(x, hat(sr, True), (b0 + 3.5) * beat * sr, 0.15)
    mel = [('G5', .5), ('A5', .5), ('C6', 1), ('A5', .5), ('G5', .5), ('F5', 1), ('G5', 2), ('C5', 2),
           ('D5', .5), ('F5', .5), ('G5', 1), ('A5', 1), ('G5', .5), ('F5', .5), ('D5', 2), (None, 1),
           ('C6', .5), ('D6', .5), ('C6', 1), ('A5', 1), ('G5', 1), ('A5', .5), ('G5', .5), ('F5', 1), ('D5', 2),
           ('F5', .5), ('G5', .5), ('A5', 1), ('G5', 1), ('D5', 1), ('C5', 4)]
    place_melody(x, mel, beat, sr, tranh, 0.4)
    save_music('tet', x)


if __name__ == '__main__':
    make_sfx()
    for fn in [music_menu, music_classic, music_garden, music_beach, music_night, music_sakura, music_tet]:
        fn()
        print('ok', fn.__name__)
