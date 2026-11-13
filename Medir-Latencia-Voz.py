"""Silent local voice timing. Does not record, play audio, or use the network."""
import json
from pathlib import Path
import subprocess
import time


def main():
    root = Path(__file__).resolve().parent
    assets = root / "assets" / "neural"
    worker = subprocess.Popen(
        [str(assets / "python" / "python.exe"), "-u",
         str(root / "cove_neural.py"), "--assets", str(assets)],
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
        text=True, encoding="utf-8", creationflags=subprocess.CREATE_NO_WINDOW,
    )
    def request(payload):
        start = time.perf_counter()
        worker.stdin.write(json.dumps(payload) + "\n")
        worker.stdin.flush()
        first = None
        while True:
            line = worker.stdout.readline()
            if not line:
                raise RuntimeError("Voice worker exited")
            packet = json.loads(line)
            if "error" in packet:
                raise RuntimeError("Voice synthesis failed")
            if "audio" in packet and first is None:
                first = time.perf_counter() - start
            if packet.get("ready") or packet.get("done"):
                return first, time.perf_counter() - start
    try:
        _, startup = request({"warmup": True})
        phrase = {"text": "Posso ajudar voce a organizar as tarefas de hoje.",
                  "preset": "serena", "stream": True}
        first, _ = request(phrase)
        cached, _ = request(phrase)
        print(json.dumps({"startup_warmup_seconds": round(startup, 3),
                          "first_audio_warmed_seconds": round(first, 3),
                          "first_audio_cached_seconds": round(cached, 3)}))
    finally:
        worker.kill()
        worker.communicate(timeout=10)


if __name__ == "__main__":
    main()
