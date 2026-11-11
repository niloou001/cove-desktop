"""Synthetic fixtures only: no microphone, network, or user recordings."""
import json
from pathlib import Path
import sys
import time

sys.path.insert(0, str(Path(__file__).resolve().parent))
import numpy as np
from cove_asr import load_engine, transcribe, wav_pcm, prepare_audio, vocabulary_hints

root = Path(__file__).resolve().parent
raw = wav_pcm(root / 'assets/asr/testes/fala-0.wav')
original = np.frombuffer(raw, dtype='<i2').astype(np.float32) / 32768
quiet = (np.clip(original * .07 + .015, -1, 1) * 32767).astype('<i2').tobytes()
start = time.perf_counter()
for _ in range(100):
    normalized = prepare_audio(quiet)
print(json.dumps({'audio_processing_ms': round((time.perf_counter() - start) * 10, 3)}), flush=True)
assert abs(float(np.mean(normalized)) - float(np.mean(original)) * .42) < .0003
assert np.array_equal(prepare_audio(raw), original)
assert np.max(np.abs(normalized)) <= .981
assert np.sqrt(np.mean(normalized ** 2)) > np.sqrt(np.mean((original * .07) ** 2))
assert vocabulary_hints('Discord, Discord; Geral\nSpotify') == 'Discord, Geral, Spotify'
assert len(vocabulary_hints(', '.join('Nome' + str(i) for i in range(100)))) <= 320
assert not prepare_audio(np.full(16000, 500, dtype='<i2').tobytes()).any()

engine = load_engine(root / 'assets/asr/small')
for case, expected in enumerate(('discord', 'spotify', 'bloco de notas', 'sim')):
    raw = wav_pcm(root / f'assets/asr/testes/fala-{case}.wav')
    samples = np.frombuffer(raw, dtype='<i2').astype(np.float32) / 32768
    for mode in ('clean', 'quiet'):
        audio = samples if mode == 'clean' else samples * .07 + .015
        pcm = (np.clip(audio, -1, 1) * 32767).astype('<i2').tobytes()
        start = time.perf_counter()
        hints = 'Discord, Spotify, Steam, Cove' if case != 3 else 'Sim, nao, pode abrir, cancelar'
        result = transcribe(engine, pcm, hints)
        print(json.dumps({'case': case, 'mode': mode, 'seconds': round(time.perf_counter() - start, 2), **result}, ensure_ascii=True), flush=True)
        assert expected in result['text'].lower(), (case, mode, result)

random = np.random.default_rng(42)
for name, samples in [('silence', np.zeros(16000)), ('dc_only', np.full(16000, .015)), ('noise', random.normal(0, .003, 16000))]:
    result = transcribe(engine, (np.clip(samples, -1, 1) * 32767).astype('<i2').tobytes(), 'Discord, Spotify, Steam, Cove')
    assert not result['text'], (name, result)
    print(name + '_NO_COMMAND_OK', flush=True)
print('RECOGNITION_REGRESSION_OK', flush=True)
