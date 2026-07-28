# FVoice

App de ditado (speech-to-text) 100% local para macOS (Apple Silicon). Menu bar app, push-to-talk global, transcrição via WhisperKit no Neural Engine, foco em PT-BR.

## Build

Requisitos: macOS 14+, Xcode CLT, [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
xcodegen generate
xcodebuild -scheme FVoice -configuration Debug build
```

O `.app` sai em `build/` (ou DerivedData, dependendo da invocação). O `.xcodeproj` é gerado e não é versionado.

## Assinatura e permissões

Assinatura ad-hoc (`CODE_SIGN_IDENTITY: "-"`) com bundle id estável `com.jacobmoura.fvoice`. O macOS revoga Accessibility/Input Monitoring quando a assinatura muda entre builds — se o hotkey global parar de funcionar após rebuild, remova e re-adicione o FVoice em System Settings → Privacy & Security → Accessibility e Input Monitoring.

## Arquitetura

DDD-lite: `Domain/` (entidades, use cases, protocolos — sem AVFoundation/WhisperKit), `Infrastructure/` (áudio, whisper, input, persistência), `App/` (SwiftUI, MenuBarExtra).

## Hotkey

Default: **⌥⌘ (Option+Command) em modo toggle** — pressione uma vez para começar a gravar, de novo para parar (decisão do usuário; substitui o default original de Right Option push-to-talk). O chord é só de modificadores, então o event tap é listen-only e nada é consumido — atalhos e acentos (Opt+letra) continuam funcionando.

## Status

- [x] M0 — Scaffold (menu bar app buildando via xcodebuild)
- [x] M1 — Captura de áudio (16kHz mono, wav de debug em `~/.fvoice/debug/`) + hotkey toggle ⌥⌘
- [ ] M2 — Transcrição (WhisperKit)
- [ ] M3 — Hotkey global + inserção de texto
- [ ] M4 — Robustez (VAD, anti-alucinação)
- [ ] M5 — Settings + polish
