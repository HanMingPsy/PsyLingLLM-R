PsyLingLLM — Model Registry (Registration Subsystem)

A production-ready, GitHub-standard guide to PsyLingLLM’s model registry: how endpoints are analyzed, standardized, validated, and written to a portable YAML file.

🧭 1) Purpose & Scope

The registry stores endpoint definitions (inputs/outputs/streaming) for LLM providers in a human-readable YAML that PsyLingLLM can load at runtime.
It is generated automatically from a probe + analysis pipeline, but can also be edited by hand.

Key goals:

One place to define how to call a model (headers, body, optional params).

Version- and provider-agnostic interface types (e.g., chat, completion, messages, responses).

Streaming delta paths and non-streaming content paths captured precisely.

CI-friendly preview + validation (Pass-1 vs Pass-2 consistency).

📦 2) Registration Subsystem Layout (R Package Standard)

All functions live under /R/ and are documented with roxygen2.

psylingllm/
├── R/
│   ├── register_orchestrator.R        # llm_register(): end-to-end analysis → registry
│   ├── register_probe_request.R       # probe_llm_streaming(): POST (non-stream & SSE)
│   ├── register_rank_endpoint.R       # scoring (NS & ST) and keyword lexicon
│   ├── register_build_input.R         # build_standardized_input(), Pass-2 templates
│   ├── register_read.R                # structural inference & path helpers
│   ├── register_classify.R            # URL → interface classification
│   ├── register_entry.R               # build_registry_entry_from_analysis()
│   ├── register_io.R                  # upsert into ~/.psylingllm/model_registry.yaml
│   ├── register_preview.R             # CI/human-readable preview
│   ├── register_validate.R            # Pass-2 consistency report
│   └── register_utils.R               # helpers (internal-only)
├── inst/
│   └── schema/
│       └── model_registry.yaml        # example/seed schema (optional)
└── tests/
    ├── testthat/
    │   ├── test_register_build_input.R
    │   ├── test_register_validate.R
    │   └── test_register_orchestrator.R
    └── testthat.R


Why this structure?

Recognized by devtools, roxygen2, pkgload.

Clear layering: orchestration → probe → scoring → standardization → entry → IO.

Easier to test and maintain.

🔄 3) End-to-End Workflow
flowchart LR
  A[llm_register()] --> B[probe_llm_streaming (Pass-1)]
  B --> C[score_candidates_ns/st]
  C --> D[build_standardized_input (Pass-2 templates)]
  D --> E[make_pass2_probe_inputs]
  E --> F[probe_llm_streaming (Pass-2)]
  F --> G[render_pass2_path_consistency_report]
  G --> H[build_registry_entry_from_analysis]
  H --> I[format_registration_preview]
  I --> J[register_endpoint_to_user_registry (YAML upsert)]


Pass-1: Probe the raw endpoint, score likely paths for answer and thinking.

Pass-2: Build a normalized request template; re-probe; verify extracted paths are consistent.

Entry: Convert the analysis to a stable, hand-editable YAML node.

Upsert: Merge into the user registry at ~/.psylingllm/model_registry.yaml.

🧩 4) Concepts & Placeholders

Interface types (auto-classified from URL path):

chat, completion, messages, conversation, responses, generate, inference, or unknown.

Placeholders (used in templates and probe inputs):

${API_KEY} in headers

${CONTENT} in body (user prompt location)

${ROLE} for provider-specific role labels

${PARAMETER} merge anchor (see “Optionals”)

Optionals:

Runtime-tunable fields (e.g., stream, max_tokens, temperature).

Stored under input.optional_defaults and merged when constructing requests.

📖 5) Minimal Example
R — Auto-analyze and register
res <- llm_register(
  url = "https://api.deepseek.com/v1/chat/completions",
  headers = list(
    "Authorization" = "Bearer ${API_KEY}",
    "Content-Type"  = "application/json"
  ),
  body = list(
    model = "deepseek-chat",
    messages = list(list(role = "user", content = "${CONTENT}"))
  ),
  api_key = Sys.getenv("DEEPSEEK_API_KEY"),
  provider = "official",
  generation_interface = "chat",
  optional_defaults = list(stream = TRUE, max_tokens = 512, temperature = 0.7),
  auto_register = TRUE
)

cat(paste(format_registration_preview(res), collapse = "\n"))

YAML — What the registry looks like
deepseek-chat:
  chat:
    provider: official
    reasoning: true
    input:
      default_url: https://api.deepseek.com/v1/chat/completions
      headers:
        Content-Type: application/json
        Authorization: Bearer ${API_KEY}
      body:
        model: deepseek-chat
        messages:
          - role: ${ROLE}
            content: ${CONTENT}
        ${PARAMETER}: ${VALUE}
      optional_defaults:
        stream: true
        max_tokens: 512
        temperature: 0.7
      default_system: ~
    output:
      respond_path: list("choices","0","message","content")
      thinking_path: list("choices","0","message","reasoning_content")
      id_path: list("id")
      object_path: list("object")
      token_usage_path:
        prompt: list("usage","prompt_tokens")
        completion: list("usage","completion_tokens")
    streaming:
      enabled: true
      delta_path: list("choices","0","delta","content")
      thinking_delta_path: list("choices","0","delta","reasoning_content")


Security: Do not store real API keys in the registry. Keep "Authorization": "Bearer ${API_KEY}" and inject the key at runtime.

🧠 6) Output Path Semantics

Non-streaming (NS):

respond_path → where the final answer text lives.

thinking_path → where provider-exposed reasoning lives (if any).

Streaming (ST / SSE):

delta_path → where incremental answer tokens arrive.

thinking_delta_path → incremental reasoning tokens (if any).

Usage:

token_usage_path → nested pointers to prompt/completion totals.

Paths are represented as R-readable specs (e.g., list("choices","0","message","content")), supporting zero-based numeric segments for JSON arrays.

🧪 7) Pass-2 Consistency Report

After standardization, the system re-probes the endpoint and prints a GitHub-friendly verification:

[Pass-2 Verified Ports]
✅ NS respond_path consistent: list("choices..message..content")
⚙️  NS thinking_path skipped (embedded <think> detected)
✅ ST delta_path consistent: list("choices..delta..content")

✅ All ports consistent between Pass-1 and Pass-2. Verification PASSED.


If any mismatch is detected, the report ends with FAILED so you can fix the template or adjust scoring thresholds.

🧷 8) Optionals & the ${PARAMETER} Merge Anchor

The Pass-2 body includes a special anchor ${PARAMETER} whose value is materialized from input.optional_defaults at request time.

You can keep the anchor as ~ (null) in YAML for cleanliness; the orchestrator still merges optional_defaults during probes and runtime calls.

Typical optionals (broad, provider-agnostic):
stream, max_tokens, temperature, top_p, top_k, penalties, stop sequences, seeds, beams, logprobs, response formats, tool toggles, reasoning knobs, safety, search toggles, retry/echo/suffix metadata, etc.

🧰 9) Public API (Exported)

llm_register(url, headers, body, api_key, provider, generation_interface, optional_defaults, ...)
Orchestrates Pass-1/Pass-2 analysis, prints previews, optionally upserts.

build_registry_entry_from_analysis(analysis, ...)
Convert an analysis result to a registry entry (pure function).

format_registration_preview(entry)
CI/human-readable preview of the entry you’re about to write.

register_endpoint_to_user_registry(entry, path = get_registry_path())
Safe upsert into ~/.psylingllm/model_registry.yaml.

get_registry_path() / ensure_registry_header(path)
Registry location and file bootstrap.

Internal helpers (e.g., classify_generation_interface(), build_standardized_input(), probe_llm_streaming()) are documented but not typically exported to end users.

🧪 10) Testing & CI
Local
devtools::document()
devtools::load_all()
devtools::check()
testthat::test_dir("tests/testthat")

GitHub Actions
name: R-CMD-check
on: [push, pull_request]
jobs:
  R-CMD-check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: r-lib/actions/setup-r@v2
      - uses: r-lib/actions/setup-r-dependencies@v2
      - uses: r-lib/actions/check-r-package@v2


Suggested tests:

test_register_build_input.R — ${CONTENT} location + messages vs single-prompt.

test_register_validate.R — PASS/FAIL for port consistency.

test_register_orchestrator.R — end-to-end dry-run (mock endpoint).

test_register_entry.R — YAML serialization round-trip.

🧑‍💻 11) Style & Contribution

Style: tidyverse (2-space indent, snake_case).

Docs: roxygen2 headers on every exported function (@param, @return, @export, @examples).

Commits (Conventional):

feat(register): add pass-2 standardization and validation

fix(register_io): preserve vendor fields during merge

refactor(classify): unify /v1 and /api/v1 path stripping

test(register): add stream delta path reconstruction cases

🔐 12) Security Notes

Do not commit real API keys. Always use ${API_KEY} and set them via environment variables or secrets.

The registry should not contain private URLs; prefer generic/official endpoints in default_url.

📝 13) Troubleshooting

Streaming not detected
Ensure Accept: text/event-stream and body$stream = TRUE. Some providers only stream on certain interfaces.

No thinking_path
Many providers don’t expose reasoning fields. The system handles this (it’s optional).

Path mismatch in Pass-2
Re-check ${CONTENT} location and confirm message container keys (messages, content, role).

📄 14) License

MIT (or your project’s license). Include a LICENSE file at repo root.