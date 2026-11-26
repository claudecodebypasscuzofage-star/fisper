<p align="center">
  <img src="docs/icon.png" width="128" alt="Fisper icon">
</p>

<h1 align="center">Fisper</h1>

<p align="center">
  <b>Don't type, just speak.</b><br>
  Free, open-source, 100% on-device voice dictation for macOS.<br>
  Hold <kbd>fn</kbd>, talk, release — clean, punctuated text appears in whatever app you're using.
</p>

<p align="center">
  <img src="docs/screenshots/home.png" width="820" alt="Fisper home screen">
</p>

---

## Why

Cloud dictation apps are great, but they send your voice to a server, cap your words, and cost a subscription.
Fisper does the same job **entirely on your Mac**: Whisper runs on the GPU for speech-to-text, and a local language model (Apple Intelligence or Ollama) cleans up what you said. No account, no network, no limits.

## Features

**Dictation**
- **Hold-to-talk anywhere** — hold <kbd>fn</kbd> (or right ⌥ / ⌘ / ⇧ / ⌃, ⌃⌥, ⌥⌘), speak, release. Text lands at your cursor in any app: Messages, Mail, Slack, Notes, VS Code/Cursor, terminals, ChatGPT/Claude…
- **Hands-free** — double-tap the key or press <kbd>space</kbd> while holding it; finish with the key or ✓. <kbd>Esc</kbd> cancels, <kbd>⌃⌘V</kbd> pastes the last dictation again.
- **Transcribes while you speak** — long dictations are streamed to Whisper in the background at natural pauses, so a 2-minute ramble finishes as fast as a sentence.
- **Fast** — ~0.3–0.6 s speech-to-text on Apple Silicon (adaptive Whisper context, model kept warm), ~1 s release-to-text including AI clean-up.

**Noise & clarity**
- **Voice isolation** — Apple's on-device ML voice-isolation model (the tech behind FaceTime's *Voice Isolation*) strips background noise, music and nearby chatter. *Automatic* mode measures your room's signal-to-noise and only applies it when needed; strength is adjustable (85% measured best for accuracy).
- **Quiet & mumbled speech boost** — speech-aware loudness normalization with a soft limiter (+17 dB on a whispered test clip, transcribed word-perfect).
- **Rumble/hum filter**, silence detection and Whisper-hallucination filtering ("We couldn't hear you" instead of a phantom "Thank you.").

**Writing**
- **Auto-correct levels** — *Light* (punctuation + fillers, your exact words) · *Balanced* (grammar, self-corrections, lists) · *Polished* (smooths awkward phrasing).
- Removes *um / uh*, stutters and repeats; applies self-corrections — *"Tuesday, no wait, Wednesday"* → *"Wednesday"*; fixes grammar — *"it were closed so we goes home"* → *"it was closed, so we went home"*.
- **Your rules** — plain-English instructions the AI follows every time ("Use British spelling", "Never use exclamation marks").
- Lists → bullets, numbers → digits, *"new line"* / *"new paragraph"*, per-app **Style** (Formal / Casual / very casual).
- Every AI rewrite is validated: if it adds content, answers your question or drops text, Fisper falls back to the deterministic cleaner.
- **Dictionary** (names, jargon, "chat GPT → ChatGPT" — also fed to Whisper as hints) and **Snippets** ("my email" → your address).

**Make it yours** — 40+ settings in a native System Settings–style layout: shortcut, tap sensitivity, hands-free behaviour, max length, excluded apps, insert method (paste / type it out / clipboard), smart spacing, trailing space, auto-Return, model, language, noise mode, isolation strength, accent color, Liquid Glass or Midnight flow bar, bar position & size, sounds & volume, history retention…

**Reliable** — crash-isolated speech engine that restarts itself, self-healing keyboard listener, automatic retry on Whisper repetition loops, failed dictations saved for one-click re-transcribe, built-in diagnostics.

<p align="center">
  <img src="docs/screenshots/flow-bar.png" width="640" alt="The flow bar: idle, recording, hands-free, processing">
  <br><sub>The flow bar: idle · listening · hands-free · thinking (Liquid Glass and Midnight styles)</sub>
</p>

| Writing & AI | Audio & Noise |
|---|---|
| ![Writing](docs/screenshots/writing.png) | ![Audio](docs/screenshots/audio.png) |
| **Appearance** | **Insights** |
| ![Appearance](docs/screenshots/appearance.png) | ![Insights](docs/screenshots/insights.png) |

<p align="center"><img src="docs/screenshots/menubar.png" width="300" alt="Menu bar panel"><br><sub>Menu bar panel</sub></p>

## Requirements

- Mac with **Apple Silicon** (M1 or later)
- **macOS 26** or later
- ~600 MB disk for the default speech model
- Optional: **Apple Intelligence** turned on *or* [Ollama](https://ollama.com) with a small model (`ollama pull qwen2.5:3b` gave the best results in testing) for grammar & self-correction. Without either, Fisper still removes fillers, stutters and fixes spacing with built-in rules.

## Install

### Download

Grab `Fisper.dmg` from [Releases](../../releases), drag **Fisper** to Applications.

Fisper is ad-hoc signed (no paid Apple developer account), so the first time macOS may say it can't verify the developer. Either right-click the app → **Open**, or run:

```bash
xattr -dr com.apple.quarantine /Applications/Fisper.app
```

### Build from source

```bash
git clone https://github.com/claudecodebypasscuzofage-star/fisper.git
cd fisper
brew install cmake        # only needed the first time, to build whisper.cpp
./scripts/build.sh --install
```

`--install` copies the app to `/Applications` and launches it. Use `--dmg` to also produce `build/Fisper.dmg`.

## First run

1. **Microphone** — allow it when asked.
2. **Accessibility** — System Settings → Privacy & Security → Accessibility → turn on **Fisper**. This lets it notice your shortcut in other apps and paste text. (Fisper's window updates by itself once it's on.)
3. **fn / 🌐 key** — System Settings → Keyboard → *Press 🌐 key to* → **Do Nothing**, so the emoji picker doesn't pop up. Or pick a different shortcut.
4. The speech model (~574 MB) downloads once.

Then click into any text field, hold <kbd>fn</kbd>, talk, release.

| Action | Keys |
|---|---|
| Push to talk | hold <kbd>fn</kbd> |
| Hands-free | double-tap <kbd>fn</kbd>, or <kbd>fn</kbd> + <kbd>space</kbd> |
| Finish hands-free | <kbd>fn</kbd> or ✓ |
| Cancel | <kbd>Esc</kbd> |
| Paste last dictation again | <kbd>⌃</kbd><kbd>⌘</kbd><kbd>V</kbd> |

## How it works

```
 hold fn ─► AVAudioEngine (16 kHz mono) ──► streamed in chunks at pauses while you talk
                                              │
                                              ▼
     high-pass ─► SNR check ─► Apple voice isolation (if noisy) ─► loudness boost
                                              │
                                              ▼
                        whisper.cpp server (Metal GPU, model kept warm)
                                              │  raw transcript
                                              ▼
     rules: noise tags, fillers, stutters, dictionary, voice commands
                                              │
                                              ▼
     local LLM (Apple Intelligence or Ollama) ─► faithfulness check ─┐
                                              │ (fallback: rules)    │
                                              ▼                      │
               style for the target app ─► snippets ─► smart spacing ◄┘
                                              │
                                              ▼
                      paste via ⌘V into the focused app, restore clipboard
```

- `Sources/Fisper/Core/HotkeyManager.swift` — CGEventTap for the hold-to-talk key, hands-free, Esc, ⌃⌘V
- `Sources/Fisper/Core/AudioRecorder.swift` — microphone capture, levels for the waveform, silence analysis, pause detection
- `Sources/Fisper/Core/AudioEnhancer.swift` — high-pass, SNR estimate, AUSoundIsolation (offline render), loudness normalization
- `Sources/Fisper/Core/WhisperServer.swift` — runs and supervises the bundled `whisper-server`
- `Sources/Fisper/Core/TextCleaner.swift` — deterministic clean-up, styles, dictionary, snippets
- `Sources/Fisper/Core/AIPolisher.swift` — Apple Foundation Models / Ollama rewrite + output validation
- `Sources/Fisper/UI/` — SwiftUI: flow bar, Home, Insights, Dictionary, Snippets, Style, Settings, onboarding

### Testing without a microphone

```bash
swift build
./.build/debug/Fisper --selftest some-recording.wav another.wav   # prints raw vs. final text, SNR and timings
./.build/debug/Fisper --enhance noisy.wav cleaned.wav always       # hear what voice isolation does
FISPER_DEMO=1 FISPER_DATA_DIR=/tmp/fisper-demo ./.build/debug/Fisper --render-ui /tmp/shots   # renders every screen to PNG
```

## Privacy

Audio, transcripts, history, dictionary and snippets stay in `~/Library/Application Support/Fisper`. Fisper makes no network requests except downloading Whisper models from Hugging Face when you click *Download*, and talking to Ollama on `127.0.0.1` if you use it.

## Troubleshooting

- **Shortcut does nothing** — check Accessibility is on for Fisper. After rebuilding from source, macOS may need you to toggle Fisper off and on again in Accessibility (ad-hoc signatures change on every build).
- **Emoji picker appears** — set *Press 🌐 key to* → *Do Nothing*, or switch the shortcut to right ⌥.
- **"We couldn't hear you"** — check the microphone in Settings; AirPods sometimes take a moment to switch to their mic. Settings → Advanced → *Run test dictation* checks the whole pipeline without a mic.
- **Text was copied but not pasted** — the focused app may block synthetic paste (e.g. secure password fields). Press ⌘V yourself.
- Logs: `~/Library/Application Support/Fisper/fisper.log`

## Credits

- [whisper.cpp](https://github.com/ggml-org/whisper.cpp) (MIT) and OpenAI's [Whisper](https://github.com/openai/whisper) models (MIT)
- Apple Foundation Models framework, [Ollama](https://ollama.com)

Fisper is an independent project and is not affiliated with Wispr, OpenAI or Apple.

## License

[MIT](LICENSE)
