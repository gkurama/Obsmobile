# OBS Mobile

Estúdio de transmissão nativo para iPhone, inspirado no OBS Studio. O projeto
usa SwiftUI, AVFoundation, ScreenCaptureKit (iOS 27+), ReplayKit (iOS 16–26) e
HaishinKit para cenas, câmera, captura de tela, gravação e publicação RTMP.

## O que o código oferece

- Cenas com fontes de câmera, texto, cor e imagem; fontes podem ser ocultadas,
  reposicionadas e redimensionadas. Texto, cor e imagem são incluídos na
  composição RTMP da câmera.
- Publicação da câmera por RTMP/RTMPS com chave configurável.
- Captura da tela e áudio do iPhone publicada por RTMP. No iOS 27+, ScreenCaptureKit
  faz a captura e grava um MP4 local; no iOS 16–26, a extensão ReplayKit transmite
  e grava um MOV local. Depois, toque em **Salvar gravações de ecrã** para importar
  os arquivos para a Fototeca. Em ambos os modos, o sistema pede autorização.
- Controles de volume e mudo para microfone e áudio do app na transmissão de
  tela.
- Gravação da câmera local na Fototeca.
- Conexão ao OBS WebSocket v5 para listar/trocar cenas e iniciar/parar a live.
- Monitor de vídeo RTMP para receber um sinal enviado pelo PC.
- Teleprompter com texto e velocidade ajustáveis no iPhone; o texto pode ser
  enviado a uma fonte de texto existente no OBS por WebSocket.

## Compilar e assinar

Requer macOS, Xcode 27 ou posterior e XcodeGen (`brew install xcodegen`). O
código de captura ScreenCaptureKit usa o SDK iOS 27; o suporte ReplayKit para
iOS 16–26 continua disponível quando o app é compilado com esse SDK. Gere e abra
o projeto:

```sh
xcodegen generate
open OBSMobile.xcodeproj
```

O app e a extensão precisam do grupo compartilhado `group.com.g.obsmobile.shared`.
Ative esse App Group para os dois identificadores no Apple Developer e na
assinatura dos targets. Para captura no iOS 27+, o entitlement de gravação de
tela e os modos de background de áudio/captura também precisam estar ativos.
Configure assinatura para app e extensão no Xcode antes de instalar em um
iPhone. Confirme no portal Apple que as capacidades de App Groups e captura de
ecrã necessárias estão habilitadas para a equipa e para os perfis dos dois
targets. O IPA produzido sem assinatura pelo workflow não pode ser instalado
diretamente.

## Enviar para YouTube, TikTok ou OBS no PC

1. Obtenha a URL RTMP/RTMPS e a chave de transmissão da plataforma. O botão
   YouTube preenche `rtmp://a.rtmp.youtube.com/live2`; a chave é fornecida pela
   conta do YouTube. Para TikTok, informe a URL e a chave que a conta disponibilizar.
2. Para enviar a câmera e as fontes da cena, toque em **Transmitir câmera RTMP**.
   Para o ecrã inteiro, toque em **Transmitir e gravar ecrã** no iOS 27+ e escolha
   a captura no seletor Apple. No iOS 16–26, use o seletor ReplayKit e escolha OBS
   Mobile como extensão. No iOS 27+, pare pelo mesmo botão do app; nas versões
   anteriores, encerre a transmissão pelo indicador de gravação/transmissão do iOS.
3. Para levar vídeo ao OBS do PC, use um servidor RTMP na rede local (por
   exemplo, MediaMTX) e configure o OBS como cliente desse servidor. O app manda
   o sinal para o endereço do servidor; o próprio OBS não recebe RTMP direto sem
   um servidor de ingestão.

O RTMP normal não cifra o tráfego; use RTMPS quando o destino oferecer. O app
publica em um destino RTMP por vez. Um serviço de retransmissão pode encaminhar
para várias plataformas.

## Controlar o OBS e assistir ao PC no iPhone

- No OBS, ative **WebSocket Server** e configure o app com `ws://IP_DO_PC:4455`
  (ou `wss://` quando configurado) e a senha do servidor. O painel do app lista
  cenas, troca a cena ativa e envia comandos de iniciar/parar transmissão.
- Para assistir ao PC no iPhone, envie a saída do OBS para um servidor RTMP e
  informe a URL de entrada e a chave no painel **PC → iPhone**.
- Para o teleprompter no PC, conecte o painel **OBS no PC**, informe no painel
  **Teleprompter** o nome de uma fonte de texto do OBS e envie o roteiro. Adicione
  um filtro **Deslizar** a essa fonte no OBS para rolar o texto na transmissão;
  o iPhone mantém a leitura e o controle de velocidade localmente.

O botão OBS remoto controla cenas e transmissão; a prévia de vídeo PC → iPhone é
uma conexão RTMP independente. O app não implementa o protocolo do plugin OBS
Teleport. O Teleport original conecta instâncias desktop do OBS; esta integração
usa RTMP para vídeo e OBS WebSocket para controle.

## Limitações desta etapa

- iOS controla a captura de tela através do seletor do sistema e da API disponível
  naquela versão.
  Essa transmissão encaminha o ecrã capturado e o áudio do sistema/microfone; ela
  ainda não combina o ecrã com as camadas personalizadas da cena.
- Os modos de câmera e ecrã são exclusivos. Iniciar gravação ou transmissão pela
  câmera interrompe a captura do ecrã; iniciar captura do ecrã interrompe a
  gravação ou transmissão da câmera. A gravação/transmissão de câmera usa a câmera
  e seu microfone; captura de ecrã transmite a tela e grava um arquivo local com
  áudio do app e, se habilitado pelo seletor iOS, microfone. Importe a gravação de
  ecrã para a Fototeca depois de parar a captura.
- A gravação local da câmera e a publicação RTMP da câmera também alternam entre
  si. Ambas usam a câmera como fonte; escolha a ação desejada no painel Controles.
- A captura contínua pode ser encerrada pelo iOS, por falta de memória, rede ou
  bateria. O app não oferece ainda reconexão automática, múltiplos destinos
  simultâneos, fontes de navegador, transições, chroma key ou um mixer completo
  como o OBS de computador.
- O iPhone não permite que um app substitua o compositor de tela do sistema nem
  capture conteúdo protegido por DRM. O resultado é um estúdio móvel com
  funções compatíveis com iOS, não uma cópia integral do OBS desktop.
