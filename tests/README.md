# Test workflow

The default test suite is deterministic, credential-free, and network-free. It
covers Registry v1/v2 loading, request construction, transport normalization,
stream and non-stream response parsing, diagnostic redaction, result
compatibility, and experiment data flow.

Live provider tests are part of the `testthat` suite but are skipped unless
explicitly enabled. They must never run on CRAN. To enable them, set:

```text
PSYLINGLLM_LIVE_API_TESTS=true
```

Credentials may be stored in the ignored project-root `API.Renviron` file:

```text
OPENAI_API_KEY=...
DEEPSEEK_API_KEY=...
QWEN_API_KEY=...
```

Qwen workspace endpoints are configuration rather than credentials and must be
provided explicitly:

```text
QWEN_OPENAI_BASE_URL=https://{workspace}.cn-beijing.maas.aliyuncs.com/compatible-mode/v1
QWEN_ANTHROPIC_BASE_URL=https://{workspace}.cn-beijing.maas.aliyuncs.com/apps/anthropic
```

When OpenAI requires a local HTTPS proxy, set `OPENAI_HTTPS_PROXY`. Model IDs
can be overridden through `OPENAI_TEST_MODEL`, `DEEPSEEK_TEST_MODEL`, and
`QWEN_TEST_MODEL` as upstream offerings change.

Run the complete suite with `devtools::test()`. Run only the opt-in integration
layer with:

```r
devtools::test(filter = "live-api-integration")
```

Live tests use temporary Registry v2 and output paths. They assert protocol
connectivity, streaming, error evidence, secret redaction, trial data, and
multi-turn conversation history without modifying the bundled or user
registry.
