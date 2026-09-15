# PsyLingLLM 0.4.0

- Introduced Registry v2 with separate model, provider, interface, and
  capability domains.
- Refactored `llm_caller()` into a resolver, request builder, transport,
  response parser, and result-normalization pipeline without changing its
  experiment-facing behavior.
- Added reusable protocol support for OpenAI-compatible Chat Completions,
  OpenAI Responses, DeepSeek-compatible chat, and Anthropic Messages.
- Preserved Registry v1 user files and the existing public registry return
  structures through compatibility projections.
- Added network-free contract tests for request construction, streaming,
  response parsing, provider errors, timeouts, secret redaction, and bundled
  Registry v1/v2 equivalence.
