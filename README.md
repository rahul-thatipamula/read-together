<h1 align="center">📖 Read Together</h1>

<p align="center">
  A local‑first reading companion for macOS.<br>
  Read PDFs, highlight them, and ask questions — answered by a small open‑source LLM running entirely on your Mac.
</p>

<p align="center">
  <img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-000?logo=apple&logoColor=white">
  <img alt="Swift 5.9" src="https://img.shields.io/badge/Swift-5.9-F05138?logo=swift&logoColor=white">
  <img alt="SwiftUI" src="https://img.shields.io/badge/UI-SwiftUI%20%2B%20PDFKit-0A84FF">
  <img alt="llama.cpp" src="https://img.shields.io/badge/LLM-llama.cpp%20%2B%20Metal-6E56CF">
  <img alt="Privacy" src="https://img.shields.io/badge/data-never%20leaves%20your%20Mac-2DA44E">
</p>

---

## Why

Reading a long book, you forget things. *Who was that character? What was the argument in chapter 3?
What did I ask about this last week?* Read Together keeps the book, your highlights, your questions
and their answers together — and answers new questions from the book's actual text, with page
numbers, using a model that runs on your own machine. No account, no cloud, no telemetry.

## Features

### Reading
- Native PDFKit viewer: continuous scroll, pinch or ⌘ ± zoom, page jump, position remembered per book
- **Select text → popover**: five highlight colors · Copy · Define · Explain · Ask…
- **Focus mode** (⇧⌘F): full screen, only the book. `Esc` to leave
- **Marks** (⇧⌘M): every highlight in one list — jump to it, ask about it, or ask about all of them
- Highlights are stored as annotations in `marks.json`; your PDF file is never modified

### Asking
- Grounded answers with **page citations** — click a citation to jump there, even into another book
- **This book / All books** scope; the **Ask** screen searches your whole library at once
- **Memory**: every Q&A is remembered across sessions and books, so *“what did I ask about the
  narrator last week?”* just works
- **Word meanings**: `define ephemeral`, select a word → Define, or the **Aa** button. Definitions
  use the passages where the word appears and are saved to your vocabulary
- **Ask about a selection** with your own prompt or quick intents (*Explain simply*, *Summarize*,
  *How does this connect to earlier chapters?*)
- Streaming responses; Stop at any time

### Tracking
- Daily reading time (per book), pages seen, questions asked, words looked up
- 14‑day chart, per‑book table, streak, vocabulary list, recent questions
- Idle‑aware: nothing is counted after 2 minutes without input

### Models
- One‑click download of curated GGUF models (Qwen3 4B/8B, Gemma 3 4B/12B, Llama 3.2 3B) with RAM
  guidance for your machine
- Runs on Metal via llama.cpp; loaded on demand, **freed on quit**
- Book search uses Apple's on‑device `NLEmbedding`, so there is nothing else to download

## Getting started

```bash
brew install xcodegen
git clone https://github.com/rahul-thatipamula/read-together.git
cd read-together
xcodegen generate
open ReadTogether.xcodeproj        # ⌘R
```

First launch: **Models → Download** (Qwen3 8B for 16 GB Macs, Qwen3 4B for 8 GB) → **Load**.
Then **Library → Add Book…**, open it, press **Index for chat** once, and start asking.

Terminal build:

```bash
xcodebuild -project ReadTogether.xcodeproj -scheme ReadTogether -configuration Debug -derivedDataPath build build
open "build/Build/Products/Debug/Read Together.app"
```

Headless check of the whole pipeline (load → index → ask → define → recall → unload):

```bash
"build/Build/Products/Debug/Read Together.app/Contents/MacOS/Read Together" --selftest
```

## Keyboard shortcuts

| Shortcut | Action |
|---|---|
| ⌘O | Add book |
| ⇧⌘F | Focus mode (toggle) |
| ⇧⌘J | Show / hide chat |
| ⇧⌘M | Marks |
| ⌘ + / ⌘ − | Zoom |
| Esc | Leave focus mode |

## How it works

```
select / type question
        │
        ▼
 EmbeddingService ──► LibraryService.search ──┐   top passages (page‑tagged)
        │                                     ├──► ChatService builds prompt ──► LlamaEngine (llama.cpp, Metal)
        └──────────► MemoryService.recall ────┘   relevant past Q&A                     │
                                                                                        ▼
                                                    citations + answer ◄── streamed pieces ── ChatPanel
```

- **Indexing**: PDFKit extracts page text → 220‑word chunks with overlap → `NLEmbedding` vectors →
  `indexes/<book>.json`. Retrieval blends cosine similarity with a lexical score.
- **Generation**: the model's own chat template (`llama_chat_apply_template`), 8K context, min‑p +
  temperature sampling, streamed token by token from a Swift `actor` so the UI never blocks.
- **Memory**: each answered question is embedded and stored; later questions retrieve the closest
  past Q&A and include them in the prompt.

## Project layout

```
ReadTogether/
  App/         ReadTogetherApp (menus, quit handling) · AppState (all UI state) · SelfTest
  Models/      Types · ModelCatalog
  Services/    LlamaEngine · EmbeddingService · LibraryService · ChatService · MemoryService
               MarksService · StatsService · ModelService · JSONStore · Paths
  Views/       ContentView · SidebarView · LibraryView · ReaderView · PDFKitView
               ChatPanel · AskView · StatsView · ModelsView
Vendor/llama.xcframework   prebuilt llama.cpp (b10936), macOS arm64 + x86_64
project.yml                xcodegen spec — regenerate the .xcodeproj after adding files
```

The app is sandboxed. Data lives in
`~/Library/Containers/app.readtogether.mac/Data/Library/Application Support/Read Together/`
(`books/`, `indexes/`, `chats/`, `models/`, `marks.json`, `memory.json`, `vocabulary.json`, `stats.json`).

## Verified

`--selftest` on an Apple M4, 16 GB, Qwen3 8B Q4_K_M:

```
loaded qwen3-8b in 18s
indexed "SOFTWARE ENGINEERING NOTES" (102 pages) in 11s
answer (188 pieces, 21s) with citations [75, 66, 74, 97, 15]
define → saved to vocabulary
recall → recounted earlier questions correctly
unloaded cleanly
```

## Roadmap

- EPUB support
- Text‑to‑speech read‑aloud with follow‑along highlighting
- Export highlights and notes to Markdown
- Optional GGUF embedding model for stronger multilingual retrieval

## License

MIT
