# GitHub-Hosted Tinderbox Installer Experiment

## Context

The current Outline Item + AI Lookup installer (`/tmp/ai-outline-installer.tbx`) embeds all content as gzip+base64 payloads in a single action code blob. This works but is hard to maintain — editing a library function means re-running the build script, re-encoding payloads, and rebuilding the installer document. The installer action code is opaque (10KB of base64 strings).

**Goal**: Explore whether Tinderbox's `runCommand()` can fetch plain text files from GitHub at install time, replacing base64 payloads with `curl` calls. This would let us store all installer components as readable plain text in a Git repository.

## Approach: `runCommand("curl ...")` with GitHub Raw URLs

GitHub serves raw file content at predictable URLs:
```
https://raw.githubusercontent.com/{owner}/{repo}/{branch}/{path}
```

In Tinderbox action code, we can (theoretically) do:
```
$Text("/Hints/Library/Utils") = runCommand("curl -s https://raw.githubusercontent.com/.../library/utils.txt");
```

This eliminates all gzip+base64 encoding. Files live as plain text in the repo.

### Two-Tier Architecture

**Tier 1 — Bootstrap note** (lives in a .tbx file or is pasted manually):
```
$OnPaste = "action($Text);"
$Text = <minimal bootstrap that downloads and executes the full installer>
```

The bootstrap `$Text` would be just one line:
```
action(runCommand("curl -s https://raw.githubusercontent.com/{owner}/{repo}/main/install.txt"));
```

**Tier 2 — Remote installer** (`install.txt` in the GitHub repo):
The full installer action code with `runCommand("curl -s ...")` calls for each payload, stored as a plain readable text file in the repo.

### Proposed GitHub Repo Structure

```
tinderbox-installers/
  outline-ai/
    install.txt                     # Main installer action code
    library/
      utils.txt                     # Utils library functions
      logging.txt                   # Logging library
      claude.txt                    # Claude integration
      outlines.txt                  # Outline numbering functions
    prompts/
      tell-me-more.txt              # LLM prompt template
    stamps/
      ai-lookup.txt                 # AI Lookup stamp code
    templates/
      outline-markdown.txt          # Outline export template
      outline-item-markdown.txt     # Outline item export template
    config/
      claude-command.txt            # Default Claude CLI command
      log-level-help.txt            # Log level documentation
    expressions/
      display-expression.txt        # $DisplayExpression value
      onadd.txt                     # $OnAdd value
    readme.txt                      # README content
```

Every file is plain text, version-controlled, and human-readable.

### What Changes vs. Current Installer

| Aspect | Current (base64) | GitHub-hosted |
|--------|-------------------|---------------|
| Library function text | gzip+base64 blob | `runCommand("curl -s URL")` |
| $DisplayExpression | base64 blob | `runCommand("curl -s URL")` |
| $OnAdd | base64 blob | `runCommand("curl -s URL")` |
| Emoji badges | base64 blob | Still base64 (3 short strings, not worth a network call) |
| Prompt/stamp/template text | gzip+base64 blob | `runCommand("curl -s URL")` |
| Build step | Run `build-installer.sh` | Edit plain text files, push to GitHub |
| Offline install | Works | Requires internet |

## Key Risks to Test

Tinderbox is **not sandboxed**, so child processes from `runCommand()` should have full network access. The remaining risks are:

1. **Shell environment** — `runCommand()` may not inherit a full shell environment. We may need `runCommand("/usr/bin/curl -s URL")` with the full path, or prefix with `source ~/.zprofile ;`.

2. **Timeouts** — `runCommand()` timeout behavior is undocumented. Slow networks could cause hangs.

3. **Error handling** — If curl fails (404, network error), `runCommand()` returns an empty string or error text. The installer would silently assign bad content to notes.

4. **`action()` on remote content** — The bootstrap pattern `action(runCommand("curl -s URL"))` needs to work — i.e., downloading action code and executing it in one shot.

## Experiment Plan

### Experiment 1: Basic `curl` from `runCommand()`

Test whether `runCommand("curl ...")` can fetch content from a public URL.

**Steps:**
1. Create a small public test file (e.g., a GitHub Gist or raw repo file) containing `Hello from GitHub`
2. Create a test TBX at `/tmp/curl-test.tbx`
3. Via JXA, run: `note.actOn({with: '$Text = runCommand("curl -s https://raw.githubusercontent.com/...");'})`
4. Check if `$Text` contains the downloaded content

**Success criteria**: `$Text` equals `Hello from GitHub`
**If it fails**: Try `/usr/bin/curl`, try with `runCommand("source ~/.zprofile ; curl -s URL")`, document the error

### Experiment 2: Assign `$Text` from remote plain text

Test that multi-line content (like a library function) downloads correctly and can be used as `$Text`.

**Steps:**
1. Upload the Utils library (`/tmp/installer-utils.txt`) to a public GitHub repo or Gist
2. In test TBX, create a Library note and try: `$Text("/Hints/Library/Utils") = runCommand("curl -s URL");`
3. Set `$IsAction = true`, call `update("/Hints/Library/Utils")`
4. Test that the function is callable

**Success criteria**: `now()` returns a date string after fetching and compiling the library note from a URL

### Experiment 3: Remote `action()` execution (bootstrap pattern)

Test the two-tier bootstrap — downloading action code and executing it.

**Steps:**
1. Upload a small action code file to GitHub:
   ```
   $Name = "Remote Install Worked!";
   $Color = "green";
   ```
2. In test TBX, run: `note.actOn({with: 'action(runCommand("curl -s URL"));'})`
3. Check if the note was renamed and colored

**Success criteria**: Note name changes to "Remote Install Worked!" and turns green

### Experiment 4: Quoting — `$DisplayExpression` and `$OnAdd` from URL

Test that action code expressions with inner quotes survive the curl → attribute assignment.

**Steps:**
1. Upload `display-expression.txt` containing: `$OutlineDesignator + " " + $Name`
2. Upload `onadd.txt` containing: `$Prototype |= "Outline Item"; $OutlineDesignator = outlineDesignator(this);`
3. Assign: `$DisplayExpression("/path") = runCommand("curl -s URL");`
4. Verify the expression evaluates correctly

**Success criteria**: DisplayExpression renders correctly with outline designators

### Experiment 5: Full remote installer (if 1-4 pass)

Build the complete installer using curl calls, host all files in a GitHub repo, and test end-to-end.

**Steps:**
1. Push all component files to the GitHub repo
2. Write `install.txt` — the main installer with curl-based payload fetching
3. Create a bootstrap note: `$OnPaste="action($Text);"` / `$Text = action(runCommand("curl -s .../install.txt"));`
4. Paste into a fresh document and verify full installation

## Implementation Steps (for running the experiments)

1. **Create a public GitHub repo** (or Gist) with test files
2. **Write the JXA test harness** — a script that creates `/tmp/curl-test.tbx`, runs each experiment, and reports results
3. **Run experiments 1-4 sequentially** — each builds on the previous
4. **If experiments pass**: restructure the existing installer to use the GitHub-hosted approach
5. **If curl fails for any reason**: investigate alternatives:
   - The `fetch()` action code function (undocumented but may have better integration)
   - `runCommand("python3 -c 'import urllib.request; ...'")`
   - Fall back to the proven base64 approach

## Verification

- Experiment 1 passes: `$Text` contains the exact content of the remote file
- Experiment 2 passes: Library function compiles and runs from URL-fetched source
- Experiment 3 passes: Remote action code executes correctly via `action(runCommand(...))`
- Experiment 4 passes: Quoted expressions assigned correctly from URL content
- Experiment 5 passes: Full installer works identically to the current base64 version
