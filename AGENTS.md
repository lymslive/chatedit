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

The main flow:
1. `load_env()` — load `ai-curl.env`, apply CLI overrides
2. `open_input()` — open file or buffer STDIN to a temp file
3. `load_template()` — load JSON template (fallback: inline `{"model":"$API_MODEL","messages":[]}`)
4. `parse_chat()` — parse Markdown into `[{role, content}, ...]` message array
5. `inject_system()` — prepend system message if needed
6. Substitute `$API_MODEL` in template's `model` field
7. Either `--encode` (print JSON and exit), `--decode` (reverse operation), or call `call_api()` via `curl`
8. `parse_response()` — handles both OpenAI-compatible (`.choices[].message.content`) and Anthropic native (`.content[].text`) response formats
9. Write response back to file (`-i`) or print to stdout

## Dependencies

| Dependency | Required? | Used by |
|------------|-----------|---------|
| `curl` | Required | both scripts |
| `jq` | Optional | `ai-curl.sh` (degrades to raw JSON without it) |
| Perl 5.14+ | Required | `ai-chat.pl` |
| `JSON::PP` | Required | `ai-chat.pl` (bundled with Perl 5.14+, no CPAN install needed) |
| `envsubst` | Required | `ai-curl.sh` (from `gettext` package) |

## Testing

No formal test framework. Verify behavior manually with files in `testdata/`:

```bash
# Round-trip encode/decode sanity check
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
