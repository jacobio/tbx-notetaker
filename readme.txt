# Outline Item + AI Lookup Installer

This note installed the following components into your document:

## What Was Installed

**User Attributes:**
- `OutlineDesignator` (string) - auto-generated outline label (I., A., 1., etc.)
- `LLMConfidence` (string) - AI confidence level (High/Medium/Low)
- `LLMSearchedWeb` (boolean) - whether AI used web search
- `LLMSources` (set) - source URLs from AI lookup

**Prototypes:**
- `/Prototypes/Markdown` - base Markdown prototype (skipped if already present)
- `/Prototypes/Outline Item` - auto-numbering outline item with AI lookup support

**Library Functions** (in `/Hints/Library/`):
- `Utils` - core utilities (now, getDir, runMyCommand)
- `Logging` - log functions (logInfo, logWarn, logError)
- `Claude` - Claude CLI integration (promptClaude)
- `Outlines` - outline numbering and AI lookup functions

**Other:**
- `/LLM Prompts/Tell me more about...` - prompt template for AI lookups
- `/Templates/Outline (Markdown)` - Markdown export template for outlines
- `/Hints/Stamps/AI Lookup` - stamp that triggers Claude to annotate a note
- `/Config/Claude Command` - path and flags for the Claude CLI
- `/Config/Log Level` - logging verbosity (INFO/WARN/ERROR)
- `/Config/Log` - persistent log output

## Prerequisites

1. **Claude CLI**: Install [Claude Code](https://docs.anthropic.com/en/docs/claude-code) and ensure `claude` is on your PATH

## Usage

1. Create a new container (note with children)
2. Set its prototype to **Outline Item**
3. Add child notes - each automatically gets an outline designator (I., A., 1., a., etc.)
4. Nesting works: children of children get deeper designator levels
5. Select a note and run the **AI Lookup** stamp to have Claude annotate it

## Customization

- **Claude CLI path**: Edit `/Config/Claude Command` if `claude` is not on your PATH
- **Claude flags**: Modify allowed tools, model, etc. in the same config note
- **Log verbosity**: Change `/Config/Log Level` to INFO, WARN, or ERROR
- **AI prompt**: Edit `/LLM Prompts/Tell me more about...` to change what Claude returns

## Notes

- The installer is safe to re-run; it uses `create()` which updates existing notes
- The Markdown prototype is only created if one does not already exist
- Library functions are compiled via `update()` during installation
- This installer was generated from the AINoteteker Tinderbox document