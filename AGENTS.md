# AGENTS.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**chatedit** is a command-line AI chat toolkit that lets users edit multi-turn conversations stored as Markdown files, then send them to AI model APIs. The core idea is using a Markdown format to represent chat history that humans can freely edit before/between API calls.

## Tools in This Repo

| Script | Language | Role |
|--------|----------|------|
| `bash/ai-curl.sh` | Bash | Wraps `curl` to send a JSON payload to an AI API endpoint |
| `perl/ai-chat.pl` | Perl | Parses Markdown chat files → assembles JSON → calls API via `curl` → writes response back |
| `bin/ai-curl` | symlink | Points to `bash/ai-curl.sh` |
| `vim/` (submodule) | Vimscript | Git submodule → `github.com/lymslive/chatedit-vim`; `:AI` / `:AR` commands + Markdown abbreviations |
| `Makefile` | Make | `test` / `install` / `help` targets |

The two scripts can be used independently or piped together:
```bash
cat chat.md | perl/ai-chat.pl --encode | bash/ai-curl.sh
```

## Running the Tools

No build step — these are interpreted scripts. Invoke directly:

```bash
# Phase 1: print response to stdout (always happens)
perl/ai-chat.pl chat.md

# Phase 1 + Phase 2: also append response to file (multi-turn workflow)
perl/ai-chat.pl -a chat.md

# Encode only (print assembled JSON, no API call)
perl/ai-chat.pl --encode chat.md | jq .

# Decode: JSON request body → Markdown
perl/ai-chat.pl --decode < testdata/chat-claude.json

# Simple mode: treat whole input as a single user message (no Markdown parsing)
echo "Explain recursion briefly" | perl/ai-chat.pl --simple
echo "Explain recursion briefly" | perl/ai-chat.pl -s --encode | jq .

# Raw JSON output: print API response JSON verbatim (ignores -a)
perl/ai-chat.pl --json chat.md

# Save request JSON to a directory for later inspection (no --debug noise)
perl/ai-chat.pl --postdir post.tmp/ -a chat.md

# Streaming mode: print response in real-time; also append to file when -a is set
perl/ai-chat.pl --stream chat.md
perl/ai-chat.pl --stream -a chat.md

# Stream + raw JSON: forward raw SSE lines to stdout
perl/ai-chat.pl --stream --json chat.md

# Reformat output (add ## role >> header + fix heading levels)
perl/ai-chat.pl -a chat.md                 # reformat on by default when writing file
perl/ai-chat.pl --reformat 1 chat.md       # force reformat even for stdout output
perl/ai-chat.pl --reformat 0 -a chat.md    # disable reformat even when writing file

# STDIN mode with --append: echo original input then append AI reply (both reformatted)
cat chat.md | perl/ai-chat.pl -a

# Send a raw JSON file to the API
bash/ai-curl.sh testdata/chat-simple.json

# Send plain text (auto-wrapped as single-turn JSON)
echo "Hello" | bash/ai-curl.sh --simple
echo "Hello" | bash/ai-curl.sh --simple --system @testdata/system-chinese.txt
```

## Configuration

Create an env file (standard shell assignment syntax, no spaces around `=`):
```bash
API_URL=https://api.example.com/v1/chat/completions
API_KEY=sk-xxxxxxxx
API_MODEL=gpt-4o
```

Both scripts derive the env filename from the script name (`$0` with `.pl`/`.sh` stripped), so a symlink `kimi-chat` → `ai-chat.pl` will look for `kimi-chat.env` first, then fall back to the generic name. Search order (highest priority first):
1. `--env <file>` option
2. `./$PROG.env`  (fallback: `./ai-curl.env` / `./ai-chat.env`)
3. `./.chatedit/$PROG.env`  (fallback: `./.chatedit/ai-curl.env` / `./.chatedit/ai-chat.env`)
4. `~/.chatedit/$PROG.env`  (fallback: `~/.chatedit/ai-curl.env` / `~/.chatedit/ai-chat.env`)

`ai-chat.pl` additionally auto-searches for a system prompt file (`$PROG.sys`, fallback `ai-chat.sys`) and a JSON template file (`$PROG.json`, fallback `ai-chat.json`) in the same three directories.

## Markdown Chat Format (`docs/chat-format.md`)

Conversation segments start with `## role >>` (a level-2 heading):
- **Roles**: `system`/`user`/`assistant` or abbreviations `P`/`Q`/`A`
- Text after `>>` on the same line is included in the message content
- A `##` heading that doesn't match the `role >>` pattern ends the current segment (acts as separator)
- Lines starting with `# ` (level-1 heading) are comments — not sent to the API
- Inside triple-backtick code blocks, `##`, `#`, `@`, `!` markers are ignored
- Inside a valid conversation segment:
  - `@path` — imports file contents into the message
  - `!cmd` — captures shell command output into the message
  - Errors from `@`/`!` are appended as `(Read Error)` or `(Read Empty)` on the same line
- `### ` and deeper sub-headings inside a segment are treated as ordinary content (do not end the segment)

## Architecture of `perl/ai-chat.pl`

Entry point: `unless (caller) { run() }` — the `run()` sub holds all CLI/main logic, so the
file can be `require`d by tests without side effects. Option variables are declared as `our`
(package globals) so test files can set them directly.

The main flow inside `run()`:
1. `GetOptions` — parse CLI flags into `our $opt_*` globals
2. `load_env()` — load env file (by script name, fallback `ai-chat.env`), apply CLI overrides
3. `open_input()` — open file or buffer STDIN to a temp file
4. `load_template()` — load JSON template (fallback: inline `{"model":"$API_MODEL","messages":[]}`)
5. `parse_chat()` — parse Markdown into `[{role, content}, ...]` message array
6. `inject_system()` — prepend system message if needed
7. Substitute `$API_MODEL` in template's `model` field
8. Detect streaming: `--stream` flag or `"stream":true` in template sets `$is_stream`
9. Either `--encode` (print JSON and exit), `--decode` (reverse operation), or call API via `curl`
10. If stdin + `--append`: copy raw stdin bytes to stdout before making the API call
11. Dispatch to `run_stream()` or `run_non_stream()`:
    - **Phase 1**: always print response to stdout (`--reformat` defaults to 0 for stdout, or 1 when stdin+`-a`)
    - **Phase 2**: if `-a` + actual file, call `append_to_file()` (reformat defaults to 1) and print stderr summary line
    - Streaming (`call_api_stream()` → `_process_stream_lines()`): real-time delta output; accumulates full content for Phase 2
    - Non-streaming (`call_api()` → `parse_response()`): handles OpenAI-compatible (`.choices[].message.content`) and Anthropic native (`.content[].text`) formats

## Dependencies

| Dependency | Required? | Used by |
|------------|-----------|---------|
| `curl` | Required | both scripts |
| `jq` | Optional | `ai-curl.sh` (degrades to raw JSON without it) |
| Perl 5.14+ | Required | `ai-chat.pl` |
| `JSON::PP` | Required | `ai-chat.pl` (bundled with Perl 5.14+, no CPAN install needed) |
| `envsubst` | Required | `ai-curl.sh` (from `gettext` package) |

## Testing

Unit tests live in `perl/t/` and use only `Test::More` (bundled with Perl). Run with:

```bash
prove perl/t/          # run all unit tests
prove perl/t/02-parse-chat.t   # run a single test file
```

Test files:

| File | What it tests |
|------|---------------|
| `01-normalize-role.t` | `normalize_role` — abbreviation and case handling |
| `02-parse-chat.t` | `parse_chat` — roles, comments, code blocks, `@file`, `!cmd` |
| `03-parse-response.t` | `parse_response` — OpenAI / Anthropic / error / Unicode formats |
| `04-decode-to-md.t` | `decode_to_md` — JSON → Markdown output |
| `05-mock-api.t` | full pipeline with mock `call_api`; `run_non_stream` complete flow incl. file append |
| `06-encode-decode-roundtrip.t` | subprocess integration; encode↔decode idempotency over 2 iterations |
| `07-simple-json-postdir.t` | `--simple`, `--json`, `--postdir` options |
| `08-find-config.t` | `find_config_file` / `load_env` — search order (prog_name dirs first, then ai-chat fallback), `--env`/`--template` option handling |
| `09-stream.t` | `_extract_stream_delta` (OpenAI/Anthropic SSE); `--stream --encode` sets `stream:true` |
| `10-reformat.t` | `fix_heading_level` transformation (incl. count return, code-block preservation via `$in_code_ref`); `--reformat` default per output path (file=1, stdout=0); `print_response` with `$for_file` flag; `append_to_file` trailing-newline separator logic |
| `11-inject-system.t` | `inject_system` — direct value, `@file` ref, suppress (`''`/`'0'`), undef+auto-search via `find_system_file`, no-duplicate when system already present |
| `12-stdin-append.t` | `open_stdin` — STDIN buffered to tmp file; `--append` copies STDIN to stdout; trailing-newline supplement |
| `13-stream-process.t` | `_process_stream_lines` — SSE main loop: content accumulation, reformat (header + heading fix), code-block state tracking across deltas, mid-line heading edge case, Anthropic format, skip invalid input; reads `testdata/stream-openai.sse` and `testdata/stream-anthropic.sse` |

**Mocking `call_api`**: override the sub via Perl's symbol table — no extra modules needed:
```perl
local *main::call_api = sub { return $canned_response_json };
```

Manual sanity checks with existing testdata:
```bash
# Round-trip encode/decode
cat testdata/chat-hello.md | perl/ai-chat.pl --encode | perl/ai-chat.pl --decode

# Inspect assembled JSON
perl/ai-chat.pl --encode testdata/chat-system.md | jq .

# Test ai-curl.sh with a static JSON file (requires valid ai-curl.env)
bash/ai-curl.sh testdata/chat-simple.json
```

## Vim Plugin (`vim/`)

`vim/` is a **git submodule** pointing to `https://github.com/lymslive/chatedit-vim`.
After cloning this repo, initialise it with:
```bash
git submodule update --init
```

Standard Vim plugin layout inside the submodule:
- `plugin/chatedit.vim` — auto-loaded; defines `:AI` and `:AR` commands (async on Vim8+, sync fallback on Vim7)
- `autoload/chatedit.vim` — async implementation (`chatedit#RunChat`, `chatedit#HeadingIndent`); requires Vim 8 with `+job`
- `ftplugin/markdown.vim` — insert-mode abbreviations + normal-mode heading-indent mappings
- `doc/chatedit.txt` — standard Vim help documentation (`:help chatedit`)

**Installing the plugin** (Vim 8+ native packages — either symlink or clone directly):
```bash
mkdir -p ~/.vim/pack/chatedit/start
# Option A: symlink from the checked-out submodule
ln -s /path/to/chatedit/vim ~/.vim/pack/chatedit/start/chatedit
# Option B: clone the plugin repo standalone
git clone git@github.com:lymslive/chatedit-vim.git ~/.vim/pack/chatedit/start/chatedit
```

**Commands** (requires `ai-chat.pl` on `$PATH`; override with `let g:chatedit_cmd = '...'`):

Vim 8+ with `+job`: commands run **asynchronously** via `job_start()` + `--stream`; buffer updates stream in real time.
Vim 7 / no `+job`: synchronous fallback (blocks until `ai-chat.pl` returns).

| Command | Behavior |
|---------|----------|
| `:AI` | Save buffer → run `ai-chat.pl --stream --reformat 1` → stream response to end of buffer |
| `:'<,'>AI` | Write selection to temp file → run `ai-chat.pl --stream --reformat 1` → stream response after selection |
| `:AR` | Save buffer → run `ai-chat.pl --simple --stream --reformat 1` → replace buffer with streamed response |
| `:'<,'>AR` | Write selection to temp file → run with `--simple --stream --reformat 1` → replace selection |

**Markdown abbreviations** (insert mode, in `.md` files):
```
#s  →  ## system >>
#u  →  ## user >>
#a  →  ## assistant >>
```

**Normal-mode mappings** (`.md` files, heading lines only):
```
>>  →  increase heading level (add one #, max ######)
<<  →  decrease heading level (remove one #, min #)
```
Non-heading lines fall through to the default `>>` (indent) / `<<` (unindent) behaviour.

## Makefile

```bash
make help     # list targets
make test     # run prove perl/t/
make install  # copy ai-chat.pl + ai-curl.sh to ~/bin  (override: make install INSTALL_DIR=/usr/local/bin)
```

## Task/Log Files

- `task_todo.md` — project TODO items, each with a `### DONE:` timestamp when completed. Uses `## TODO:date/N` headings.
- `task_log.md` — development log entries.
- `doing_plan.tmp/` — scratch space for research/planning docs (not committed long-term).
