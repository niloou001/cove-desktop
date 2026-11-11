"""Portuguese local transcription. Audio is only received through a local pipe."""
import argparse
import base64
import contextlib
import concurrent.futures
import io
import json
import logging
import os
from pathlib import Path
import sys
import threading
import urllib.request
import wave


def download_large_file(url, destination):
    """Resume a partial download using four ordinary HTTP range requests."""
    probe = urllib.request.Request(url, headers={"Range": "bytes=0-0"})
    with urllib.request.urlopen(probe, timeout=60) as response:
        content_range = response.headers.get("Content-Range", "")
        if response.status != 206 or "/" not in content_range:
            return False
        total = int(content_range.rsplit("/", 1)[1])
    part = destination.with_suffix(destination.suffix + ".part")
    prefix = part.stat().st_size if part.is_file() else 0
    if prefix > total:
        raise RuntimeError("O download parcial tem tamanho inesperado")
    if prefix == total:
        part.replace(destination)
        return True
    step = 4 * 1024 * 1024
    ranges = [(start, min(start + step - 1, total - 1)) for start in range(prefix, total, step)]
    progress = {"count": prefix, "next": (prefix // 50_000_000 + 1) * 50_000_000}
    progress_lock = threading.Lock()

    def fetch(bounds):
        start, end = bounds
        target = destination.with_name(f"{destination.name}.{start}-{end}.range")
        expected = end - start + 1
        if target.is_file() and target.stat().st_size == expected:
            return target
        request = urllib.request.Request(url, headers={"Range": f"bytes={start}-{end}"})
        with urllib.request.urlopen(request, timeout=120) as response:
            if response.status != 206 or response.headers.get("Content-Range") != f"bytes {start}-{end}/{total}":
                raise RuntimeError("O servidor nao confirmou o trecho solicitado")
            with target.open("wb") as out:
                while block := response.read(1024 * 1024):
                    out.write(block)
        if target.stat().st_size != expected:
            raise RuntimeError("Um trecho do modelo ficou incompleto")
        with progress_lock:
            progress["count"] += expected
            if progress["count"] >= progress["next"]:
                print(f"Recebidos: {progress['count'] // 1_000_000} de {total // 1_000_000} MB", flush=True)
                progress["next"] += 50_000_000
        return target

    print(f"Continuando o modelo: {prefix // 1_000_000} de {total // 1_000_000} MB", flush=True)
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as executor:
        chunks = list(executor.map(fetch, ranges))
    with part.open("ab") as out:
        for chunk in chunks:
            with chunk.open("rb") as data:
                while block := data.read(1024 * 1024):
                    out.write(block)
    if part.stat().st_size != total:
        raise RuntimeError("Tamanho final do modelo nao confere")
    part.replace(destination)
    for chunk in chunks:
        chunk.unlink()
    return True


def download_model(folder):
    folder.mkdir(parents=True, exist_ok=True)
    for name in ("config.json", "model.bin", "tokenizer.json", "vocabulary.txt"):
        destination = folder / name
        minimum = 100_000_000 if name == "model.bin" else 100
        if destination.is_file() and destination.stat().st_size >= minimum:
            continue
        print("Baixando " + name + "...", flush=True)
        url = "https://huggingface.co/Systran/faster-whisper-small/resolve/main/" + name
        if name == "model.bin" and download_large_file(url, destination):
            continue
        part = destination.with_suffix(destination.suffix + ".part")
        with urllib.request.urlopen(url, timeout=120) as response, part.open("wb") as out:
            expected = int(response.headers.get("Content-Length", 0))
            count = 0
            next_update = 50_000_000
            while block := response.read(1024 * 1024):
                out.write(block)
                count += len(block)
                if count >= next_update:
                    print(f"  {count // 1_000_000} MB recebidos", flush=True)
                    next_update += 50_000_000
        if count < minimum or (expected and count != expected):
            raise RuntimeError("Download incompleto: " + name)
        part.replace(destination)


def load_engine(folder):
    from faster_whisper import WhisperModel

    return WhisperModel(
        str(folder), device="cpu", compute_type="int8",
        cpu_threads=min(4, os.cpu_count() or 2), num_workers=1,
        local_files_only=True,
    )


def prepare_audio(pcm):
    """Remove DC bias and lift quiet speech with bounded, fixed gain."""
    import numpy as np

    if not 3200 <= len(pcm) <= 1_600_000 or len(pcm) % 2:
        raise ValueError("Invalid audio length")
    audio = np.frombuffer(pcm, dtype="<i2").astype(np.float32) / 32768.0
    # Estimate a constant sensor offset from the quietest 20 ms blocks.
    # A whole-clip mean also removes natural asymmetry from voiced sounds.
    count = audio.size // 320
    if count:
        blocks = audio[:count * 320].reshape(count, 320)
        variances = blocks.var(axis=1)
        quiet = np.argsort(variances)[:max(1, count // 5)]
        offset = float(np.median(blocks.mean(axis=1)[quiet]))
        if abs(offset) > 0.001:
            audio -= offset
    rms = float(np.sqrt(np.mean(audio * audio)))
    peak = float(np.max(np.abs(audio)))
    # Do not amplify an almost silent recording or change normal/loud speech.
    if 0.0008 < rms < 0.015 and peak > 0:
        gain = min(6.0, 0.035 / rms, 0.98 / peak)
        if gain > 1:
            audio *= gain
    return np.ascontiguousarray(audio, dtype=np.float32)


def vocabulary_hints(value, limit=320):
    # Keep individual names intact; do not cut a large app list mid-word.
    if not isinstance(value, str):
        return ""
    selected, seen = [], set()
    for term in value.replace(";", ",").replace("\n", ",").split(","):
        term = " ".join(term.split())
        key = term.casefold()
        if not term or key in seen or len(term) > 60:
            continue
        if len(", ".join(selected + [term])) > limit:
            break
        selected.append(term)
        seen.add(key)
    return ", ".join(selected)


def transcribe(engine, pcm, hotwords=""):
    import numpy as np

    audio = prepare_audio(pcm)
    segments, _ = engine.transcribe(
        audio, language="pt", task="transcribe", beam_size=5,
        temperature=0.0, condition_on_previous_text=False,
        vad_filter=True,
        vad_parameters={"threshold": 0.35, "min_silence_duration_ms": 800,
                        "min_speech_duration_ms": 150},
        hotwords=vocabulary_hints(hotwords),
        hallucination_silence_threshold=1.0,
    )
    retained = [s for s in segments if s.no_speech_prob < 0.65 and s.avg_logprob > -1.15]
    text = " ".join(s.text.strip() for s in retained).strip()
    uncertain = bool(retained) and sum(s.avg_logprob for s in retained) / len(retained) < -0.7
    return {"text": text, "uncertain": uncertain}


def wav_pcm(path):
    import numpy as np

    with wave.open(str(path), "rb") as wav:
        if wav.getsampwidth() != 2:
            raise ValueError("Expected PCM16 WAV")
        rate, channels = wav.getframerate(), wav.getnchannels()
        samples = np.frombuffer(wav.readframes(wav.getnframes()), dtype="<i2")
    if channels > 1:
        samples = samples.reshape(-1, channels).astype(np.float32).mean(axis=1)
    if rate != 16000:
        points = np.arange(int(len(samples) * 16000 / rate)) * rate / 16000
        samples = np.interp(points, np.arange(len(samples)), samples)
    return np.asarray(np.clip(samples, -32768, 32767), dtype="<i2").tobytes()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", required=True, type=Path)
    parser.add_argument("--download", action="store_true")
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--wav", type=Path)
    args = parser.parse_args()
    if args.download:
        download_model(args.model)
        return
    logging.disable(logging.CRITICAL)
    protocol = sys.stdout
    with contextlib.redirect_stdout(sys.stderr):
        engine = load_engine(args.model)
    if args.check:
        import numpy as np

        # A silent clip must not produce a command or a hallucinated phrase.
        with contextlib.redirect_stdout(sys.stderr):
            result = transcribe(engine, np.zeros(16000, dtype="<i2").tobytes())
        if result["text"]:
            raise RuntimeError("Silence check returned text")
        print("ASR_CHECK_OK", flush=True)
        return
    if args.wav:
        with contextlib.redirect_stdout(sys.stderr):
            result = transcribe(engine, wav_pcm(args.wav), "Discord, Spotify, Steam, Cove")
        print(json.dumps(result, ensure_ascii=True), flush=True)
        return
    for line in sys.stdin:
        try:
            request = json.loads(line)
            if request.get("warmup"):
                result = {"ready": True}
            else:
                pcm = base64.b64decode(request["pcm"], validate=True)
                with contextlib.redirect_stdout(sys.stderr):
                    result = transcribe(engine, pcm, request.get("hotwords", ""))
        except Exception:
            result = {"error": "Nao consegui transcrever esta fala. Tente novamente ou digite a mensagem."}
        protocol.write(json.dumps(result, ensure_ascii=True) + "\n")
        protocol.flush()


if __name__ == "__main__":
    main()
