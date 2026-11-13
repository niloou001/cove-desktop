# Cove Desktop

Assistente de voz para Windows com interface flutuante, conversa com IA, aplicativos, jogos e automações locais no Discord e WhatsApp.

## Versão atual

- Nome, cor e aparência configuráveis; o nome salvo também configura a chamada por voz.
- Conversa em balões, contexto recente e confirmações curtas quando a transcrição estiver incerta.
- Jogos instalados da Steam e Epic, atalhos do Windows e executáveis cadastrados.
- Navegação em servidores e canais de voz do Discord, chamadas privadas e mensagens para contatos.
- Mensagens no WhatsApp Desktop e no WhatsApp Web pelo Chrome, com busca por nome salvo na agenda.
- Controle de mouse com coordenadas dos monitores detectados, incluindo monitores à esquerda do principal.
- Rascunhos anteriores preservados em cópias protegidas pelo usuário do Windows e recuperáveis nos Ajustes.
- Horário e data do Windows, temperatura por cidade via Open-Meteo, manchetes da BBC News Brasil e pesquisas no Chrome.
- Inicializador que identifica a versão em execução e permite recarregar os arquivos atualizados.

As automações verificam destinatário e campo de escrita antes de enviar. O envio não é repetido automaticamente quando o resultado é incerto. O reconhecimento depende do modelo local e da pronúncia; as integrações dependem dos controles expostos pela versão do aplicativo/site e das permissões normais do Windows.

Os testes de mensagens usam controladores simulados e janelas próprias. Não foram feitos envios reais para contatos durante a validação. Não há garantia de entrega ou leitura de mensagens.

## Recursos

- Ativação pelo nome configurado nos Ajustes, com Vosk local; **Cove** é o padrão.
- Transcrição das perguntas em português com **Whisper small**, executado localmente por faster-whisper.
- Vozes neurais locais **Serena**, feminina e calma, e **Atlas**, masculina e formal, com Kokoro. São perfis próprios, sem clonagem de personagens ou atores.
- Seleção de microfone, indicador de volume e visualização do texto reconhecido.
- Conversa com uma conta ChatGPT elegível pelo fluxo oficial de autorização, ou com chave da API como alternativa explícita.
- Abertura de aplicativos cadastrados. Exemplos: **“abre o Discord”**, **“tem como abrir o Spotify?”** e **“abre o bloco de notas”**.
- Cadastro de outros aplicativos pelo botão **Apps**. Nomes aproximados ou comandos reconhecidos com dúvida podem pedir esclarecimento antes de abrir.

## Requisitos

### Microfone em outro computador

Se aparecer que a escuta nao esta disponivel, abra **Ajustes → Preparar microfone e escuta local** e aguarde o download. A escuta basica sera iniciada sem precisar instalar as vozes ou o Whisper primeiro.

Em **Permissoes do microfone no Windows**, habilite o acesso ao microfone e o acesso de aplicativos da area de trabalho. Como o Cove roda em PowerShell, ele pode aparecer como **Windows PowerShell**. O Cove nao altera essas permissoes automaticamente.

Use **Dispositivo de entrada no Windows** para conferir se o microfone esta habilitado. Depois clique em **Tentar microfone novamente**, que atualiza a lista e usa o microfone padrao. Para escolher outro, selecione-o na lista e clique em **Aplicar voz e microfone**. Erros de preparacao ficam em `.cove-audit/microphone-setup.out.txt` e `.cove-audit/microphone-setup.err.txt`.

- Windows 10 ou 11 de 64 bits, com Windows PowerShell 5.1 e .NET Framework 4.8.
- Microfone e saída de áudio funcionando; acesso ao microfone permitido para aplicativos da área de trabalho.
- Internet para baixar os componentes na instalação e para conversar com a IA.
- Espaço para os modelos e dependências. A instalação completa pode ocupar alguns GB e consumir memória adicional durante o uso.

Não é necessário instalar Python no sistema, alterar o PATH ou executar como administrador. Os componentes Python ficam em `assets/`, dentro da pasta do Cove.

## Preparar e abrir

Para atualizar uma instalação existente, substitua apenas os arquivos de código e execute **Atualizar-Cove.cmd** na pasta do aplicativo. Preserve seus arquivos de configuração e `assets/`. Se usar o ativador separado de inicialização, execute **Ativar-Cove-Por-Voz.cmd** uma vez para instalar o ouvinte atualizado.

1. Baixe o ZIP do repositório e extraia todos os arquivos. Abra a pasta que contém **Abrir-Cove.cmd**; no projeto integrado Cove Voice, ela se chama **desktop**.
2. Abra **Abrir-Cove.cmd**. Na primeira vez, ele prepara o reconhecimento do nome em português.
3. Para instalar as vozes neurais, abra **Preparar-Vozes.cmd** ou use **Conversar → Ajustes → Preparar Serena e Atlas**. Espere a instalação e os testes terminarem.
4. Abra **Preparar-Escuta.cmd** para instalar o reconhecimento aprimorado de frases. Essa etapa aproveita o ambiente Python preparado no passo anterior.
5. Feche o Cove em **Sair**, abra novamente e confira **Escuta aprimorada ativada** em **Ajustes → Microfone**.
6. Escolha seu microfone e voz. Use **Ouvir esta voz** para comparar e **Aplicar voz e microfone** para salvar.

Os arquivos dos modelos são baixados de suas fontes e não são distribuídos neste repositório. O download do modelo de transcrição tem aproximadamente 483 MB. A instalação inicial pode levar alguns minutos.

Se o Windows bloquear os scripts, os arquivos `.cmd` aplicam uma política de execução apenas ao processo iniciado. Não alteram permanentemente a política do PowerShell. Políticas de uma organização ainda podem impedir a execução.

## Conectar a IA

### Conta ChatGPT

Abra **Conversar → Ajustes → Continuar com ChatGPT**. Entre e autorize o Cove na página oficial da OpenAI que abrir no seu navegador. A disponibilidade depende da elegibilidade da conta, das permissões autorizadas e dos limites do plano.

O login usa OAuth com PKCE, `state` e `nonce`, e verifica a identidade assinada antes de salvar credenciais. Ele não importa suas conversas ou sua memória do ChatGPT. **Gerenciar uso** abre as configurações de uso do ChatGPT.

### Chave da API

Como alternativa, abra **Usar chave da API → Salvar e usar API** em Ajustes. O uso da API tem faturamento separado e pode gerar cobranças. O Cove também aceita `OPENAI_API_KEY` no ambiente.

Não há troca automática para a API paga se o plano ChatGPT falhar ou atingir o limite. Nunca publique ou compartilhe a chave.

## Conversar e abrir apps

### Abrir o Cove com a frase de chegada

Se o ativador original **“oi Cove, papai chegou”** já estiver instalado em `%LOCALAPPDATA%\Cove`, abra **Ativar-Cove-Por-Voz.cmd** para conectá-lo a esta instalação. O configurador atualiza o iniciador da Área de Trabalho e preserva uma cópia do anterior.

Depois, a frase abre o Cove Desktop já pronto para ouvir. Se a mesma instalação estiver aberta, ela é trazida à frente em vez de abrir outra cópia. A janela não fica permanentemente sobre os outros apps.

O atalho **Cove Voz** em Inicializar mantém o ouvinte da frase ativo após entrar no Windows. Fechar o Cove Desktop não encerra esse ouvinte separado. Para iniciar sem sair da sessão, abra **Ativar Cove por voz.cmd** na Área de Trabalho e aguarde alguns segundos. O computador precisa estar acordado e com sua sessão iniciada.

Após esta atualização, encerre instâncias de versões anteriores do Cove uma vez antes de testar, porque elas ainda não possuem o controle de instância única. Se mover a pasta do projeto, execute a configuração da ativação novamente.

### Pedir algo ao Cove

Diga o nome configurado, espere a bolinha ficar verde e faça seu pedido. Pare de falar para enviar. A transcrição pode levar alguns segundos, conforme o computador.

Também é possível clicar na bolinha para falar sem dizer o nome, ou digitar na janela **Conversar**.

Para abrir aplicativos:

```text
abre o Discord
abre o disco
abre o discorde
pode abrir o Spotify pra mim?
abra a calculadora
quais aplicativos voce pode abrir
```

**Apps** mostra os programas encontrados e permite cadastrar um arquivo `.exe` ou atalho `.lnk` com um nome fácil de falar. **Abrir selecionado** testa a abertura sem depender do reconhecimento de voz.

Comandos reconhecidos são executados por controladores locais, sem interpretar o texto como comandos de terminal. Pedidos de mensagem fora das formas locais usam a conexão de IA para extrair contato, aplicativo e conteúdo; os dados são validados antes de chegar ao controlador.

Exemplos:

- “Abra o jogo NOME.”
- “Entre no servidor NOME e na call Geral.”
- “Mande mensagem para CONTATO no Discord dizendo Oi, tudo bem?”
- “Mande mensagem para CONTATO no WhatsApp Web dizendo Estou chegando.”
- “Agora diz pra ela que cheguei.”
- “Mande essa resposta para CONTATO no Discord.”
- “Que horas são?” / “Qual a temperatura em Curitiba, Paraná?”
- “Pesquise sobre astronomia no Chrome.”

Para WhatsApp Web, deixe sua conta conectada em `https://web.whatsapp.com` no Chrome. Contatos com nomes repetidos exigem identificação mais precisa. WhatsApp sem “Web” seleciona o aplicativo Desktop. A Cove não faz login por você nem lê cookies do navegador.

Se já existir outro rascunho no campo, uma cópia é protegida com DPAPI antes da substituição. Consulte **Ajustes → Ver rascunhos preservados** para recuperar o texto. Se a proteção falhar, o original é mantido no aplicativo. Esc ou trocar de janela interrompe o controle.

## Controles e diagnóstico

- Arraste o texto abaixo da bolinha para mover a janela.
- Clique durante uma resposta para interromper a fala.
- Clique durante uma transcrição para iniciar outra tentativa.
- Use **Pausar microfone** para suspender a escuta; **Sair** encerra a captura e o aplicativo.
- O indicador não permanece obrigatoriamente por cima dos outros aplicativos.
- Confira **Ouvi:** na janela Conversar quando houver uma transcrição incorreta.
- Se a barra de volume não reagir, selecione outro microfone e confira as permissões e o volume de entrada do Windows.
- Após atualizar os arquivos, encerre todas as instâncias antigas do Cove e abra novamente.

Se um preparador falhar, execute seu `.cmd` para ler a mensagem completa. Downloads completos são reaproveitados quando possível.

## Privacidade

O reconhecimento do nome, a transcrição e a síntese das vozes locais processam áudio no computador. O áudio das conversas não é salvo pelo Cove nem enviado a um serviço de transcrição. As amostras geradas nos testes ficam em `assets/` e não contêm gravações do usuário.

Perguntas transcritas e o histórico recente da conversa são enviados à conexão de IA escolhida. A interpretação de mensagens não reconhecidas localmente recebe o pedido atual. O histórico fica em memória; uma cópia protegida pode ser usada durante a recarga do aplicativo. O botão **Limpar** limpa a conversa atual. Rascunhos preservados ficam protegidos separadamente em `.cove-drafts/` e não são publicados.

As credenciais locais são protegidas para o usuário atual do Windows com DPAPI. O `.gitignore` exclui a conexão da conta, a chave, os caminhos de apps cadastrados, as preferências, os modelos, os áudios e os registros. Não remova essas exclusões antes de revisar os arquivos.

## Validação

Na pasta do aplicativo, execute no Windows PowerShell:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Verificar-Cove.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\Verificar-Apps.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\Verificar-ChatGPT.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\Verificar-Escuta.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\Verificar-Vozes.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\Verificar-Ativacao.ps1
powershell -NoProfile -STA -ExecutionPolicy Bypass -File .\Verificar-Mensagens.ps1
powershell -NoProfile -STA -ExecutionPolicy Bypass -File .\Verificar-Planejador-Mensagens.ps1
powershell -NoProfile -STA -ExecutionPolicy Bypass -File .\Verificar-Envio-Seguro.ps1
powershell -NoProfile -STA -ExecutionPolicy Bypass -File .\Verificar-WhatsApp-Web.ps1
powershell -NoProfile -STA -ExecutionPolicy Bypass -File .\Verificar-Nome-Voz.ps1
powershell -NoProfile -STA -ExecutionPolicy Bypass -File .\Cove-Voice.ps1 -SmokeTest
```

Após preparar as vozes e a escuta, o teste de transcrição com fala sintetizada pode ser executado com:

```powershell
.\assets\neural\python\python.exe .\testar_escuta_real.py
```

Foram verificados compilação, interface, comandos e negações, configuração dos apps, regras de captura, cancelamento, tratamento de respostas e partes do fluxo OAuth. O Whisper também foi testado com silêncio e áudios sintetizados, incluindo nomes de aplicativos e uma confirmação curta.

Esses testes não substituem o teste real no microfone. A disponibilidade do login e da inferência depende da conta. A abertura de apps precisa ser validada na sessão normal do Windows.

## Tecnologias

PowerShell/WPF, C#, Vosk, faster-whisper/CTranslate2, Kokoro/ONNX Runtime e autenticação oficial Sign in with ChatGPT. Veja [THIRD_PARTY.md](THIRD_PARTY.md) para fontes e créditos.

Projeto independente, sem afiliação oficial com a OpenAI, Microsoft ou personagens usados como referência de estilo.
