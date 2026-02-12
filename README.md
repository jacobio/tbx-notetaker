# AI Notetaker for Tinderbox

A one-line installer that adds AI-powered note-taking to any [Tinderbox](https://www.eastgate.com/Tinderbox/) document. Creates outline items with automatic numbering (I., A., 1., a., ...) and a stamp that uses [Claude](https://docs.anthropic.com/en/docs/claude-code) to annotate your notes.

## Install

Open any Tinderbox document, create a stamp with the following action code, and run it:

```
action(runCommand("curl -s https://raw.githubusercontent.com/jacobio/tbx-notetaker/main/install.txt"));
```

All components are fetched from this repo at install time. The installer is safe to re-run.

## What Gets Installed

| Component | Path | Purpose |
|-----------|------|---------|
| **Prototypes** | `/Prototypes/Outline Item` | Auto-numbering outline items with AI lookup support |
| | `/Prototypes/Markdown` | Base Markdown prototype (skipped if already present) |
| | `/Prototypes/LLM Prompt` | Prototype for AI prompt templates |
| **Library** | `/Hints/Library/Utils` | Core utilities (now, getDir, runMyCommand) |
| | `/Hints/Library/Logging` | Log functions (logInfo, logWarn, logError) |
| | `/Hints/Library/Claude` | Claude CLI integration (promptClaude) |
| | `/Hints/Library/Outlines` | Outline numbering and AI lookup functions |
| **Config** | `/Config/Claude Command` | Path and flags for the Claude CLI |
| | `/Config/Log Level` | Logging verbosity (INFO/WARN/ERROR) |
| **Other** | `/LLM Prompts/Tell me more about...` | Prompt template for AI lookups |
| | `/Templates/Outline (Markdown)` | Markdown export template |
| | `/Hints/Stamps/AI Lookup` | Stamp that triggers Claude to annotate a note |

**User Attributes:** `OutlineDesignator`, `LLMConfidence`, `LLMSearchedWeb`, `LLMSources`

## Usage

1. Create a new container (note with children)
2. Set its prototype to **Outline Item**
3. Add child notes -- each automatically gets an outline designator (I., A., 1., a., etc.)
4. Nesting works: children of children get deeper designator levels
5. Select a note and run the **AI Lookup** stamp to have Claude annotate it

## Prerequisites

- [Tinderbox](https://www.eastgate.com/Tinderbox/) (macOS)
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) CLI installed and on your PATH

## Customization

- **Claude CLI path**: Edit `/Config/Claude Command` if `claude` is not on your PATH
- **Claude flags**: Modify allowed tools, model, etc. in the same config note
- **Log verbosity**: Change `/Config/Log Level` to INFO, WARN, or ERROR
- **AI prompt**: Edit `/LLM Prompts/Tell me more about...` to change what Claude returns

## Repo Structure

```
tbx-notetaker/
├── install.txt              # Main installer (fetched by the one-liner)
├── library/                 # Tinderbox action code libraries
│   ├── utils.txt
│   ├── logging.txt
│   ├── claude.txt
│   └── outlines.txt
├── prompts/
│   └── tell-me-more.txt     # LLM prompt template
├── stamps/
│   └── ai-lookup.txt        # AI Lookup stamp action code
├── templates/
│   ├── outline-markdown.txt
│   └── outline-item-markdown.txt
├── config/
│   ├── claude-command.txt
│   └── log-level-help.txt
├── readme.txt               # In-document README (installed into Tinderbox)
├── scripts/
│   └── run-experiments.sh   # JXA test harness
└── test-data/               # Test fixtures
```

## Development

Run the test harness (requires Tinderbox open with a document):

```bash
bash scripts/run-experiments.sh
```

This validates that `runCommand("curl ...")` works inside Tinderbox by running 4 experiments: basic fetch, library compilation, action bootstrapping, and expression assignment.

## License

MIT
