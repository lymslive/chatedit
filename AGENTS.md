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

The two scripts can be used independently or piped together:
```bash
cat chat.md | perl/ai-chat.pl --encode | bash/ai-curl.sh
```

## Running the Tools

No build step — these are interpreted scripts. Invoke directly:

```bash
# Markdown chat → API → append response back to file (multi-turn workflow)
perl/ai-chat.pl -i chat.md

# Encode only (print assembled JSON, no API call)
perl/ai-chat.pl --encode chat.md | jq .

# Decode: JSON request body → Markdown
perl/ai-chat.pl --decode < testdata/chat-claude.json

# Send a raw JSON file to the API
bash/ai-curl.sh testdata/chat-simple.json

# Send plain text (auto-wrapped as single-turn JSON)
echo "Hello" | bash/ai-curl.sh --simple
echo "Hello" | bash/ai-curl.sh --simple --system @testdata/system-chinese.txt
```

## Configuration

Create `ai-curl.env` (standard shell assignment syntax, no spaces around `=`):
```bash
API_URL=https://api.example.com/v1/chat/completions
API_KEY=sk-xxxxxxxx
API_MODEL=gpt-4o
```

Both scripts search for this file in order (highest priority first):
1. `--env <file>` option
2. `./ai-curl.env`
3. `./.chatedit/ai-curl.env`
4. `~/.chatedit/ai-curl.env`

`ai-chat.pl` additionally auto-searches for a system prompt file `ai-chat.sys` in the same locations (unless `--system` is given). A JSON template file `ai-chat.json` is similarly searched for the API request template.

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
2. `load_env()` — load `ai-curl.env`, apply CLI overrides
3. `open_input()` — open file or buffer STDIN to a temp file
4. `load_template()` — load JSON template (fallback: inline `{"model":"$API_MODEL","messages":[]}`)
5. `parse_chat()` — parse Markdown into `[{role, content}, ...]` message array
6. `inject_system()` — prepend system message if needed
7. Substitute `$API_MODEL` in template's `model` field
8. Either `--encode` (print JSON and exit), `--decode` (reverse operation), or call `call_api()` via `curl`
9. `parse_response()` — handles both OpenAI-compatible (`.choices[].message.content`) and Anthropic native (`.content[].text`) response formats
10. Write response back to file (`-i`) or print to stdout

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
| `05-mock-api.t` | full pipeline with mock `call_api` (no real API calls needed) |
| `06-encode-decode-roundtrip.t` | subprocess integration; encode↔decode idempotency over 2 iterations |

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

## Task/Log Files

- `task_todo.md` — project TODO items, each with a `### DONE:` timestamp when completed. Uses `## TODO:date/N` headings.
- `task_log.md` — development log entries.
- `doing_plan.tmp/` — scratch space for research/planning docs (not committed long-term).
