import os
from pathlib import Path
from vosk import Model, SetLogLevel
SetLogLevel(-1)
model = Model(str(Path(os.environ['LOCALAPPDATA']) / 'Cove' / 'vosk-model-small-pt-0.3'))
for word in ('couve', 'jarvis', 'jarbas', 'jarves', 'javis', 'luma', 'luna'):
    print(word, model.vosk_model_find_word(word))
