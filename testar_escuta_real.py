"""Regression check using synthetic speech, never the user's microphone."""
import json
from pathlib import Path
import re
import sys
import time

sys.path.insert(0, str(Path(__file__).resolve().parent))
from cove_asr import load_engine, transcribe, wav_pcm
from cove_neural import synthesize
from kokoro_onnx import Kokoro

root = Path(__file__).resolve().parent
assets = root / "assets"
fixtures = assets / "asr" / "testes"
fixtures.mkdir(parents=True, exist_ok=True)
tts = Kokoro(str(assets / "neural" / "kokoro-v1.0.onnx"), str(assets / "neural" / "voices-v1.0.bin"))
cases = [
    ("Cove, abre o Discord pra mim, por favor.", "discord"),
    ("Tem como abrir o Spotify pra mim?", "spotify"),
    ("Abre o bloco de notas.", "bloco de notas"),
    ("Sim.", "sim"),
]
for i, (text, _) in enumerate(cases):
    path = fixtures / f"fala-{i}.wav"
    if not path.is_file():
        path.write_bytes(synthesize(tts, text, "serena"))
del tts
if "--make-fixtures" in sys.argv:
    print("SYNTHETIC_FIXTURES_OK", flush=True)
    raise SystemExit(0)
model = load_engine(assets / "asr" / "small")
failed = False
for i, (_, expected) in enumerate(cases):
    begin = time.monotonic()
    hints = "Sim, nao, pode abrir, cancelar" if i == 3 else "Discord, Spotify, Steam, Cove"
    result = transcribe(model, wav_pcm(fixtures / f"fala-{i}.wav"), hints)
    print(json.dumps({"case": i, "text": result["text"], "seconds": round(time.monotonic() - begin, 2)}, ensure_ascii=True), flush=True)
    if expected not in result["text"].lower():
        failed = True
if failed:
    raise SystemExit("One or more synthetic speech checks failed")
print("SYNTHETIC_SPEECH_OK", flush=True)
