"""Ativacao local por voz. Audio permanece na memoria do computador."""
import ctypes
import json
import logging
from logging.handlers import RotatingFileHandler
from pathlib import Path
import queue
import re
import subprocess
import sys
import time
import unicodedata

BASE = Path(__file__).resolve().parent

def load_wake_name():
    try:
        pointer = BASE / 'desktop-root.txt'
        project = Path(pointer.read_text(encoding='utf-8-sig').strip()) if pointer.exists() else BASE
        data = json.loads((project / 'cove-identity.json').read_text(encoding='utf-8-sig'))
        name = data.get('Name', 'Cove')
        return name if isinstance(name, str) and 1 <= len(name.strip()) <= 24 else 'Cove'
    except (OSError, ValueError):
        return 'Cove'

def wake_names(name):
    plain = ''.join(c for c in unicodedata.normalize('NFD', name.lower()) if unicodedata.category(c) != 'Mn')
    normal = ' '.join(re.findall(r'[a-z0-9]+', plain))
    if normal == 'cove':
        return ('cove', 'couve', 'coube', 'ouve', 'covi', 'cov')
    if plain.replace('.', '').strip() == 'jarvis':
        return ('jarvis', 'jarbas')
    compact = ' '.join(re.findall(r'[a-z0-9]+', plain.replace('.', '').replace("'", '')))
    return tuple(dict.fromkeys((normal, compact)))

def wake_phrases(name):
    names = wake_names(name)
    phrases = [f'{hello} {word} {article}papai chegou' for hello in ('oi', 'ola') for word in names for article in ('', 'o ')]
    return phrases + ['oi', 'ola', *names, 'papai chegou', 'o papai chegou', '[unk]']

def is_wake_phrase(text, name=None):
    normalized = ''.join(c for c in unicodedata.normalize('NFD', text.lower()) if unicodedata.category(c) != 'Mn')
    words = re.findall(r'[a-z0-9]+', normalized)
    # O nome Cove pode ser transcrito como "coube", "couve" ou "ouve".
    aliases = '|'.join(re.escape(word) for word in wake_names(name or load_wake_name()))
    return bool(re.search(r'\b(?:oi|oie|ola) (?:' + aliases + r') (?:o )?papai chegou\b', ' '.join(words)))

def launch():
    subprocess.Popen(['cmd.exe', '/c', str(Path.home() / 'Desktop' / 'Cove.bat')], creationflags=subprocess.CREATE_NO_WINDOW)

def main():
    import sounddevice as sd
    from vosk import Model, KaldiRecognizer, SetLogLevel
    handler = RotatingFileHandler(BASE / 'listener.log', maxBytes=200000, backupCount=2, encoding='utf-8')
    logging.basicConfig(level=logging.INFO, handlers=[handler], format='%(asctime)s %(levelname)s %(message)s')
    mutex = ctypes.windll.kernel32.CreateMutexW(None, False, 'Local\\CoveVoiceListener')
    if ctypes.windll.kernel32.GetLastError() == 183:
        return
    SetLogLevel(-1)
    model = Model(str(BASE / 'vosk-model-small-pt-0.3'))
    last_launch = 0
    while True:
        try:
            device = sd.query_devices(kind='input')
            rate = int(device['default_samplerate'])
            current_name = load_wake_name()
            phrases = wake_phrases(current_name)
            recognizer = KaldiRecognizer(model, rate, json.dumps(phrases, ensure_ascii=False))
            recent = []
            last_status = time.monotonic()
            last_name_check = 0
            peak = 0
            audio = queue.Queue(maxsize=100)
            def callback(data, frames, timing, status):
                if not audio.full():
                    audio.put_nowait(bytes(data))
            with sd.RawInputStream(samplerate=rate, blocksize=4000, dtype='int16', channels=1, callback=callback):
                logging.info('Ouvindo no microfone: %s', device['name'])
                while True:
                    data = audio.get(timeout=15)
                    import array
                    peak = max(peak, max((abs(v) for v in array.array('h', data)), default=0))
                    final = recognizer.AcceptWaveform(data)
                    result = json.loads(recognizer.Result() if final else recognizer.PartialResult())
                    now = time.monotonic()
                    if now - last_name_check > 1:
                        last_name_check = now
                        changed = load_wake_name()
                        if changed != current_name:
                            current_name = changed
                            recognizer = KaldiRecognizer(model, rate, json.dumps(wake_phrases(current_name), ensure_ascii=False))
                            recent.clear()
                            continue
                    spoken = result.get('text', result.get('partial', ''))
                    recent = [(t, words) for t, words in recent if now - t < 8]
                    combined = ' '.join([words for t, words in recent] + [spoken])
                    if final and spoken:
                        recent.append((now, spoken))
                        if any(w in spoken.split() for w in ('oi', 'ola', 'papai', 'chegou')):
                            logging.info('Candidato de ativacao: %s', spoken)
                    if now - last_status > 60:
                        logging.info('Captura ativa; pico do microfone: %d/32768', peak)
                        last_status, peak = now, 0
                    if is_wake_phrase(combined, current_name) and now - last_launch > 20:
                        launch()
                        last_launch = time.monotonic()
                        logging.info('Frase de ativacao detectada; Cove aberto.')
                        recognizer.Reset()
                        recent.clear()
        except Exception:
            logging.exception('Falha de audio; nova tentativa em 10 segundos')
            time.sleep(10)

if __name__ == '__main__':
    if '--test' in sys.argv:
        assert is_wake_phrase('Oi Cove, papai chegou', 'Cove')
        assert is_wake_phrase('oi couve o papai chegou', 'Cove')
        assert not is_wake_phrase('papai chegou', 'Cove')
        assert not is_wake_phrase('oi cove tudo bem', 'Cove')
        assert is_wake_phrase('oi Luma papai chegou', 'Luma')
        assert not is_wake_phrase('oi Cove papai chegou', 'Luma')
        print('Frases de ativacao verificadas.')
    elif '--launch-test' in sys.argv:
        launch()
    else:
        main()
