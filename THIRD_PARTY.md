# Componentes e modelos

Os instaladores baixam dependências e modelos separadamente. Seus arquivos não são incluídos no repositório e conservam os avisos e licenças dos respectivos projetos.

| Componente | Uso | Fonte |
| --- | --- | --- |
| Vosk | Ativação local pelo nome e escuta leve de reserva | https://github.com/alphacep/vosk-api |
| Modelo Vosk português | `vosk-model-small-pt-0.3` | https://alphacephei.com/vosk/models |
| faster-whisper | Transcrição local, versão 1.2.1 | https://github.com/SYSTRAN/faster-whisper |
| Whisper small convertido | Modelo multilíngue usado em CPU/int8 | https://huggingface.co/Systran/faster-whisper-small |
| Kokoro-82M | Timbres `pf_dora` e `pm_santa`; perfis Serena e Atlas | https://huggingface.co/hexgrad/Kokoro-82M |
| kokoro-onnx | Síntese local, versão 0.6.1 | https://github.com/thewh1teagle/kokoro-onnx |
| Python | Ambiente local portátil | https://www.python.org/ |
| ONNX Runtime, CTranslate2 e dependências Python | Inferência e processamento de áudio | Distribuídas pelos respectivos pacotes no PyPI |
| Windows Speech | Vozes brasileiras instaladas como alternativas | Componentes do Windows, não redistribuídos pelo projeto |

Os perfis Serena e Atlas usam vozes do modelo Kokoro e ajustes de ritmo. Não são clonagens de vozes de personagens ou atores. A qualidade e a pronúncia variam conforme o texto e o modelo.

Autorização da conta ChatGPT: https://developers.openai.com/siwc/token-sharing-open-source/sign-in

Uso do plano para inferência: https://developers.openai.com/siwc/token-sharing-open-source/models-and-inference
