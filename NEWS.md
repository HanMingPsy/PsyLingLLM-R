# PsyLingLLM 0.4.0

- Introduced Registry v2 with separate model, provider, interface, and
  capability domains.
- Refactored `llm_caller()` into a resolver, request builder, transport,
  response parser, and result-normalization pipeline without changing its
  experiment-facing behavior.
- Added reusable protocol support for OpenAI-compatible Chat Completions,
  OpenAI Responses, DeepSeek-compatible chat, and Anthropic Messages.
- Added explicit support levels and opt-in production Registry smoke tests.
  OpenAI Responses, DeepSeek Chat/Responses, and Qwen Chat/Responses passed
  live non-stream and stream verification for the documented model entries.
- Preserved Registry v1 user files and the existing public registry return
  structures through compatibility projections.
- Added network-free contract tests for request construction, streaming,
  response parsing, provider errors, timeouts, secret redaction, and bundled
  Registry v1/v2 equivalence.
- Added `adaptive_feedback_experiment()` as the canonical adaptive-conversation
  entry point while preserving `conversation_experiment_with_feedback()` as a
  backward-compatible alias.
- Corrected experiment result-path handling so an explicit output path no
  longer initializes the default user result directory.
- Moved automatically named result files to the platform-specific package data
  directory returned by `tools::R_user_dir()` for CRAN-compliant persistence.
- Added opt-in live DeepSeek coverage for ordinary conversation history and
  bounded adaptive feedback execution.
- Moved the default user Registry to `tools::R_user_dir()` while retaining
  read-only compatibility with the historical `~/.psylingllm` location.
- Hardened Registry and result persistence so malformed Registry files are
  preserved, v1 registration cannot corrupt v2 bundles, parent directories are
  created explicitly, and failed writes no longer report false success.
