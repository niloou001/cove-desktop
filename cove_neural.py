"""Local neural speech worker. Text arrives over stdin; audio leaves over stdout.

No account credentials, network calls, or user speech recordings are used here.
"""
import argparse
import base64
import contextlib
import io
import json
import logging
import os
from pathlib import Path
import sys
import wave

PRESETS = {
    "serena": {"voice": "pf_dora", "speed": 0.90},
    "atlas": {"voice": "pm_santa", "speed": 0.96},
}


def synthesize(engine, text, preset):
    import numpy as np

    if preset not in PRESETS:
        raise ValueError("Unknown voice preset")
    if not isinstance(text, str) or not text.strip() or len(text) > 12000:
        raise ValueError("Invalid text length")
    options = PRESETS[preset]
    samples, rate = engine.create(
        text.strip(), voice=options["voice"], speed=options["speed"], lang="pt-br"
    )
    samples = np.asarray(samples, dtype=np.float32).reshape(-1)
    if not samples.size or not np.isfinite(samples).all():
        raise ValueError("Invalid synthesized audio")
    pcm = (np.clip(samples, -1, 1) * 32767).astype("<i2").tobytes()
    out = io.BytesIO()
    with wave.open(out, "wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(int(rate))
        wav.writeframes(pcm)
    return out.getvalue()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--assets", type=Path, required=True)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    # Preserve a clean JSON-only stdout even if a dependency prints diagnostics.
    protocol = sys.stdout
    os.environ.setdefault("OMP_NUM_THREADS", "4")
    os.environ.setdefault("ORT_LOG_SEVERITY_LEVEL", "3")
    logging.disable(logging.CRITICAL)
    with contextlib.redirect_stdout(sys.stderr):
        from kokoro_onnx import Kokoro

        engine = Kokoro(
            str(args.assets / "kokoro-v1.0.onnx"),
            str(args.assets / "voices-v1.0.bin"),
        )
        missing = {p["voice"] for p in PRESETS.values()} - set(engine.get_voices())
        if missing:
            raise RuntimeError("The downloaded voice pack is incomplete")

    if args.check:
        phrases = {
            "serena": "Oi. Estou aqui com voce. Podemos conversar com calma, no seu tempo.",
            "atlas": "Ola. Estou a disposicao. Diga o que precisa e vamos organizar os proximos passos.",
        }
        for preset, text in phrases.items():
            with contextlib.redirect_stdout(sys.stderr):
                audio = synthesize(engine, text, preset)
            (args.assets / (preset + "-amostra.wav")).write_bytes(audio)
        protocol.write("VOICES_CHECK_OK\n")
        protocol.flush()
        return

    for line in sys.stdin:
        try:
            request = json.loads(line)
            with contextlib.redirect_stdout(sys.stderr):
                audio = synthesize(engine, request.get("text"), request.get("preset"))
            result = {"audio": base64.b64encode(audio).decode("ascii")}
        except Exception:
            # Never echo personal text, tracebacks, or model input to the UI/log.
            result = {"error": "A voz natural nao conseguiu gerar o audio. Execute Preparar-Vozes.cmd novamente."}
        protocol.write(json.dumps(result, ensure_ascii=True) + "\n")
        protocol.flush()


if __name__ == "__main__":
    main()
