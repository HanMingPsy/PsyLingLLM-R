# PsyLingLLM 0.3 Current Architecture Backup

## Purpose

This document records the repository architecture before the Registry v2 runtime migration. It is a behavioral and structural reference for later compatibility reviews; it is not the Registry v2 target specification.

Snapshot context:

- Package: PsyLingLLM
- Package version: 0.3.0
- Development branch: `refactor/registry-v2`
- Migration target: PsyLingLLM 0.4.0
- Current migration phase: Phase 1, Registry v2 compatibility foundation

The existing architecture is already partly registry-driven. Its main limitation is that model identity, provider/deployment information, API interface details, capabilities, request construction, transport, and response extraction are not separated consistently.

## 1. Package-Level Architecture

The package has four main functional areas:

1. Experiment orchestration
2. Registry loading and registration
3. LLM request execution
4. Experiment result normalization and persistence

Current high-level flow:

```text
Experiment function
  -> validate_experiment_config()
  -> llm_caller()
      -> get_registry_entry()
      -> construct request
      -> execute HTTP/SSE request
      -> extract answer/reasoning/usage
      -> return normalized call result
  -> map call result to experiment output schema
  -> save/log results
```

Relevant experiment entry points include:

- `trial_experiment()`
- `factorial_trial_experiment()`
- `conversation_experiment()`
- `conversation_experiment_with_feedback()`
- `multi_model_experiment()`

These functions delegate model calls to `llm_caller()`. This provider-independent experiment boundary is useful and should be preserved.

## 2. Current Registry Structure

### 2.1 Production registry

The bundled production registry is:

```text
inst/registry/system_registry.yaml
```

Its effective v1 structure is:

```yaml
model-key:
  generation-interface:
    provider: official
    reasoning: false
    input:
      default_url: https://example.test/v1/chat/completions
      headers: {}
      body: {}
      fallback_body: {}
      optional_defaults: {}
      default_system: null
      role_mapping: {}
    output:
      respond_path: null
      thinking_path: null
      id_path: null
      object_path: null
      token_usage_path: {}
    streaming:
      enabled: false
      delta_path: null
      thinking_delta_path: null
      param_name: null
```

Model, provider, interface, request template, capability flags, response selectors, and streaming configuration are stored together under each model interface.

### 2.2 Bundled models and interfaces

The current system registry includes:

- `deepseek-chat`
  - `chat`
- `deepseek-reasoner`
  - `chat`
- `gpt-4o`
  - `chat`
  - `responses`

The `chat` entries use an OpenAI-compatible message body. The `responses` entry uses a role-less `${CONTENT}` template.

### 2.3 Placeholders

The v1 request-template convention uses:

- `${API_KEY}` for runtime credential substitution
- `${ROLE}` for role-bearing message templates
- `${CONTENT}` for prompt/message content
- `${PARAMETER}` as the optional-parameter insertion anchor
- `${VALUE}` as the structural value associated with the parameter anchor
- `${OPTIONAL_DEFAULTS}` in registration templates

These placeholders are package conventions rather than a separately versioned template language.

### 2.4 Optional defaults

Optional defaults may be persisted with explicit type information:

```yaml
temperature:
  value: 0.7
  type: numeric
```

`wrap_typed_defaults()` stores type metadata, and `unwrap_typed_defaults()` restores R values during registry normalization.

### 2.5 Response path format

The production registry commonly stores paths as strings resembling R list expressions:

```yaml
respond_path: list("choices..message.content")
```

The double dot represents a wildcard numeric array index in the flatten-and-match implementation.

Other parts of the package also support:

- dotted paths such as `choices.0.message.content`
- explicit path vectors
- `*` wildcard segments
- zero-based JSON indices

The repository therefore has multiple path representations and traversal implementations.

## 3. Registry Loading and Resolution

### 3.1 User registry

`get_registry_path()` returns:

```text
~/.psylingllm/model_registry.yaml
```

The package must not automatically rewrite or migrate this file during Registry v2 development.

### 3.2 `get_registry_entry()`

`get_registry_entry()` is the effective runtime resolver.

Resolution order:

```text
User registry model
  -> System registry model fallback
  -> Error when absent from both
```

Interface behavior:

- An explicitly requested interface must exist.
- A model with exactly one interface can be resolved without specifying it.
- A model with multiple interfaces requires `generation_interface`.

User precedence currently occurs at model level. If a model exists in the user registry but the requested interface does not exist there, resolution does not merge the missing interface from the system model.

### 3.3 Registry normalization

`normalize_registry_entry()` converts a raw interface node into the structure consumed by `llm_caller()`.

It currently:

- lowercases the provider label
- normalizes logical-like values
- unwraps typed optional defaults
- normalizes known role-mapping keys
- supplies empty lists or `NULL` for missing input/output fields
- retains response and streaming path specifications

The returned object contains:

```r
list(
  model_key = ...,
  interface = ...,
  provider = ...,
  reasoning = ...,
  input = list(...),
  output = list(...),
  streaming = list(...),
  interfaces = ...
)
```

### 3.4 `load_registry()`

`load_registry()` reads only the bundled system registry and returns the parsed YAML list. It does not currently load or merge the user registry.

Some comments and newer code refer to a registry bundle containing `$merged`, but the current implementation does not produce that bundle.

### 3.5 `get_model_config()`

`get_model_config()` contains broader name-resolution logic:

1. Exact key
2. Normalized key
3. Explicit alias
4. Bare model ID
5. Model family
6. Provider default
7. Heuristic provider guess
8. OpenAI default fallback

The current system registry does not define the alias and provider-default structures expected by most of this logic. In addition, a `NULL` registry is not currently replaced by `load_registry()` inside the function.

### 3.6 Duplicate system registry path helper

`get_system_registry_path()` currently has two definitions:

- one points to `registry/model_registry.yaml`
- one points to `registry/system_registry.yaml`

The latter matches the real bundled file. Runtime behavior can depend on R file load order or how files are sourced during development.

## 4. Current Registration and Probe Pipeline

### 4.1 `llm_register()`

`llm_register()` is a large registration orchestrator with two probe passes.

Current workflow:

```text
User URL, headers, body, key, defaults
  -> Normalize provider and inputs
  -> Pass-1 non-stream request
  -> Pass-1 streaming request
  -> Rank response and reasoning candidates
  -> Infer request structure and role mapping
  -> Build standardized Pass-2 request
  -> Pass-2 non-stream and streaming probes
  -> Compare Pass-1 and Pass-2 paths
  -> Build v1 registry entry
  -> Preview
  -> Optional user-registry upsert
```

It currently combines:

- user input processing
- endpoint discovery
- HTTP transport
- SSE detection
- candidate scoring
- capability inference
- registry compilation
- preview generation
- persistence orchestration

### 4.2 Probe transport

`probe_llm_streaming()` performs:

- a non-streaming JSON POST
- a streaming JSON POST
- optional retry with `Accept: text/event-stream`
- SSE `data:` detection
- JSON parsing of stream events

The probe can detect whether streaming appears to be honored and whether the Accept header was required.

Its current protocol assumptions include:

- JSON request bodies
- POST requests
- body-level streaming flags
- SSE-style streaming
- `data:` event lines

### 4.3 Candidate ranking

`score_candidates_ns()` and `score_candidates_st()` flatten JSON structures and rank possible answer and reasoning fields using:

- path and field-name keywords
- answer/reasoning vocabulary
- blacklist terms
- path boosts and penalties
- content length
- temporal properties for streaming deltas
- softmax-normalized scores
- configurable acceptance thresholds

This machinery is valuable as discovery evidence. It should not be treated as a guarantee that a selected path is semantically correct.

### 4.4 Pass-2 standardization

The Pass-2 builder attempts to turn the original provider body into a reusable template. It infers:

- message-style versus single-content input
- message container
- content and role fields
- role mapping
- default system text
- optional request fields
- streaming parameter

Pass-2 then probes the standardized form to confirm that selected ports remain retrievable.

### 4.5 Registry entry compilation

`build_registry_entry_from_analysis()` compiles probe output into the current v1 model-interface entry.

It stores:

- normalized request body
- fallback original body
- headers
- typed defaults
- inferred role mapping
- answer and reasoning paths
- usage paths
- streaming paths
- Accept-header requirement
- stream parameter name

Official providers use the bare model key. Other providers generally use `model@provider`.

### 4.6 Registry persistence

`register_endpoint_to_user_registry()`:

- reads the existing user registry
- replaces or adds interface fields under the model key
- preserves other model entries
- sorts fields
- rewrites the YAML file with model comments

The write is direct rather than temporary-file plus atomic replacement. Existing comments and formatting are not generally preserved.

## 5. Current `llm_caller()` Runtime

### 5.1 Public contract

The current signature is:

```r
llm_caller(
  model_key,
  generation_interface = NULL,
  api_url = NULL,
  trial_prompt = NULL,
  material = NULL,
  system_content = NULL,
  assistant_content = NULL,
  api_key = NULL,
  optionals,
  stream = NULL,
  role_mapping = NULL,
  timeout = 120,
  return_raw = FALSE,
  debug = FALSE
)
```

The absence of a default for `optionals` is intentional because the implementation distinguishes a missing argument from an explicit `NULL`.

### 5.2 Current responsibilities

`llm_caller()` currently performs:

1. Dependency checks
2. Registry lookup
3. URL resolution
4. Request-template inspection
5. Prompt/material composition
6. System/history/user message construction
7. Role mapping
8. Optional-parameter resolution
9. Streaming-mode resolution
10. Placeholder substitution
11. JSON serialization
12. curl execution
13. SSE framing and JSON event parsing
14. Answer extraction
15. Reasoning extraction
16. Usage and request-ID extraction
17. Timing collection
18. Error normalization
19. Public result construction

It is therefore both orchestration layer and implementation layer.

### 5.3 URL rules

Current URL precedence:

```text
Explicit api_url
  > registry default_url for provider == "official"
  > error
```

Non-official providers must receive an explicit runtime `api_url`.

The `official` label currently mixes provider identity with deployment policy.

### 5.4 Content construction

`trial_prompt` and `material` are joined with a blank line. At least one must produce non-empty content.

For message-style bodies, the runtime constructs:

```text
Optional system message
  + normalized assistant/history messages
  + current user message
```

For role-less bodies, it substitutes `${CONTENT}` directly and ignores system/history input after warning.

### 5.5 Message-template detection

Message support is detected only when:

- the top-level body contains `messages`
- its first item is a list
- one field equals `${ROLE}`
- one field equals `${CONTENT}`

This is an OpenAI-compatible structural assumption and cannot represent all message protocols.

### 5.6 Role mapping

The normalized registry entry contains role mapping, but `llm_caller()` applies mapping only when the caller explicitly supplies the `role_mapping` argument.

This behavior is part of the current compatibility surface even though it limits registry-driven adaptation.

### 5.7 Optional parameters

Current tri-state behavior:

- missing `optionals`: use registry defaults
- `optionals = NULL`: inject no optional parameters
- named list: use only caller values, without merging defaults

Parameters are injected only when the body contains a `${PARAMETER}` key.

### 5.8 Streaming precedence

Streaming is resolved as:

```text
Explicit stream argument
  > optionals$stream
  > registry streaming.enabled
```

If streaming is enabled, the configured `streaming.param_name` is used. Otherwise the runtime falls back to a body field named `stream`.

### 5.9 Authentication substitution

When `api_key` is provided, `${API_KEY}` is recursively replaced in headers and body values.

The current mechanism assumes authentication can be represented by string substitution. It does not model authentication schemes independently.

### 5.10 Non-streaming transport

`do_nonstream_request()`:

- uses curl
- sends POST
- uses registry headers exactly as provided
- sends the JSON string as the request body
- applies an integer timeout
- reads the complete response into memory
- parses JSON when possible
- maps curl exceptions to status `599`

### 5.11 Streaming transport

`do_stream_request()`:

- uses curl streaming callbacks
- buffers incomplete newline-delimited chunks
- selects lines beginning with `data:`
- skips `[DONE]`
- parses each selected payload as a standalone JSON object
- records the first observed data-event latency
- collects raw JSON events
- maps curl exceptions to status `599`

This is an OpenAI-compatible SSE implementation. It does not implement general SSE event grouping, Anthropic event state, Ollama JSON Lines, or other protocols.

### 5.12 Non-streaming response extraction

The parsed JSON is flattened into path/value rows. `extract_text_by_spec()` first checks an exact normalized path and then a wildcard-index regular expression.

Answer, reasoning, usage, and request ID are independently extracted from registry paths.

### 5.13 Streaming response extraction

`stream_reconstruct_text()` flattens every parsed JSON event, finds the configured path, converts matching leaves to character, and concatenates them in event order.

This works for simple delta protocols but does not support semantic typed-item or typed-event state machines.

### 5.14 Return structure

The public return object contains:

```r
list(
  status = ...,
  interface = ...,
  model_key = ...,
  streaming = ...,
  usage = list(
    prompt = ...,
    completion = ...,
    id = ...
  ),
  answer = ...,
  thinking = ...,
  first_token_latency = ...,
  raw = ...,
  error = ...
)
```

`first_token_latency` is present in the streaming branch. Existing callers may depend on status `599`, empty strings, `NULL` reasoning values, and the exact nested usage names.

## 6. Other Response and JSON Parsing Logic

### 6.1 `llm_parser.R`

`parse_answer_and_think()` implements a separate parser contract based on fields such as:

- `cfg$respond$respond_path`
- `cfg$respond$thinking_path`
- `cfg$reasoning$reasoning_path`
- `cfg$reasoning$reasoning_field`
- `cfg$streaming$thinking_delta_path`

It also supports inline `<thinking>` and `<answer>` markers.

The current `llm_caller()` does not use this parser; it implements response extraction directly.

### 6.2 `json_utils.R`

`extract_by_path()` supports:

- zero-based numeric indices
- dotted or bracket-like path strings
- explicit vectors/lists
- `*` wildcards
- optional simplification and collapse
- optional strict failures

This is separate from the flatten-and-regex path implementation currently used by `llm_caller()`.

### 6.3 `register_read.R`

`register_read.R` contains another set of structural and path helpers:

- placeholder discovery
- mixed key/index traversal
- message-structure inference
- JSON path retrieval
- path-segment coercion

Legacy string paths resembling `list(...)` are accepted under a constrained pattern and parsed as R expressions.

### 6.4 Error parsing fallback

`safe_parse_response()` invokes the older parser and falls back to the OpenAI Chat path `choices[0].message.content` when configured extraction returns no text.

This fallback is useful for compatibility but is provider-specific and can hide configuration errors.

## 7. Error Handling

### 7.1 Experiment configuration validation

`validate_experiment_config()` checks:

- required data columns
- non-empty API key
- registry availability
- provider/default URL rules

Its `registry` argument is retained for backward compatibility but currently ignored.

### 7.2 Runtime network errors

Both transport functions map curl exceptions to status `599`. Experiment functions use this convention to distinguish timeout/network failures from normal provider responses.

### 7.3 Experiment error records

`handle_llm_error()` maps broad categories into experiment-facing status details such as:

- `NETWORK_ERROR`
- `HTTP_ERROR`
- `API_ERROR`
- `MODEL_NOT_FOUND`

### 7.4 Current observability and security concerns

- Debug mode may print complete headers after API-key substitution.
- Raw return mode may contain authentication headers.
- Provider error bodies are not consistently converted into structured public errors.
- YAML read failures are sometimes converted to `NULL` or empty lists without preserving a precise failure category.

## 8. Existing Registry Validation

### 8.1 `validate_registry_entry()`

This function validates a current interface-style entry. It checks selected v1 fields and reports problems through messages rather than consistently throwing structured errors.

Its assumptions include:

- `provider`, `input`, and `output` at the same level
- non-null default URL
- response path and token usage path
- logical streaming flag
- character streaming delta path

Some valid interfaces may not satisfy all of these assumptions.

### 8.2 `validate_registry_schema()`

The current Registry v2 validator requires:

```text
schema_version
provider
capabilities
interfaces
```

This format is not produced by the current registry builder and is not used by the current production YAML.

### 8.3 Unfinished v2 resolver

An untracked `R/resolve_registry_entry.R` is present in the working tree. Its current draft expects a possible `$merged` registry bundle and calls the v2 validator, but does not yet resolve interfaces, aliases, providers, capabilities, or normalized runtime configuration.

This file overlaps the intended Phase 2 resolver and must not be overwritten without confirming ownership.

## 9. Public API and Documentation Surface

Important exported registry/runtime functions include:

- `get_registry_entry()`
- `get_model_config()`
- `load_registry()`
- `validate_registry_entry()`
- `validate_registry_schema()`
- `build_registry_entry_from_analysis()`
- `register_endpoint_to_user_registry()`
- `register_endpoint_offline()`
- `llm_register()`
- `probe_llm_streaming()`
- `llm_caller()`

Several lower-level helpers are also exported, including path, candidate-scoring, message-normalization, and streaming-reconstruction functions. These exports increase the backward-compatibility surface.

Documentation is generated from roxygen2. `man/*.Rd` and `NAMESPACE` must not be edited manually.

The package currently does not contain a visible `tests/` test suite or a `testthat` development dependency.

## 10. Strengths of the Existing Architecture

The current implementation should not be discarded. Useful foundations include:

- experiment functions are already mostly provider-independent
- user registry takes precedence over the system registry
- model entries can expose multiple interfaces
- request headers and bodies are YAML-driven
- response and reasoning fields are configurable
- optional defaults preserve type information
- optional arguments have deliberate three-state semantics
- non-streaming and streaming calls share a normalized result
- endpoint probes can discover candidate response fields
- registration includes a second verification pass
- curl errors have a stable experiment-facing status convention

## 11. Main Architectural Limitations

### 11.1 Domain concepts are mixed

Model identity, provider/deployment, protocol interface, capabilities, request templates, and response extraction rules are repeated under each model interface.

### 11.2 Protocol assumptions remain in R runtime

Current hard-coded assumptions include:

- top-level `messages`
- role/content placeholders
- JSON POST
- body-level `stream`
- SSE `data:` events
- `[DONE]`
- path-based delta reconstruction
- provider label `official`

### 11.3 `llm_caller()` has excessive responsibilities

Registry resolution, request building, transport, streaming framing, parsing, normalization, and error conversion are combined in one runtime module.

### 11.4 Configuration is permissive before runtime

YAML may parse successfully even when references, selectors, templates, streaming settings, or required placeholders are inconsistent. Many failures are detected only during a real API call.

### 11.5 Paths are structural rather than semantic

Fixed paths can confuse answer, reasoning, tool-call, and content-block objects. New typed protocols require item/event semantics rather than only nested paths.

### 11.6 Probe inference can be mistaken for verified capability

Candidate scoring provides evidence, but a high-scoring field is not necessarily a stable semantic contract.

### 11.7 Registration is difficult for ordinary users

Users currently need to understand request JSON, headers, placeholders, streaming, and output paths.

## 12. Safe Optimization Opportunities in the Existing Architecture

These improvements can be made incrementally without rewriting the package.

### 12.1 Establish characterization tests

Before moving code, capture:

- current registry selection
- typed defaults
- user/system priority
- message ordering
- optional-parameter tri-state behavior
- streaming precedence
- request serialization
- answer/reasoning/usage extraction
- status `599`
- experiment output fields

### 12.2 Centralize registry path and loading behavior

Use one system path helper and one internal loader while keeping existing public functions as compatibility wrappers.

### 12.3 Compile registry data before runtime

Convert raw v1/v2 YAML into a strictly validated canonical runtime configuration before `llm_caller()` constructs a request.

### 12.4 Unify selector syntax

New Registry v2 configuration should prefer explicit YAML path segments and semantic typed-item/event selectors. Legacy path syntax should remain confined to the v1 compatibility layer.

### 12.5 Extract runtime boundaries

Move current behavior behind three principal interfaces:

```text
Request Builder
Transport
Response Parser
```

Keep the existing helper names temporarily as compatibility wrappers where necessary.

### 12.6 Separate probe discovery from registry compilation

Probe output should contain candidates, confidence, and evidence. A separate compiler should decide whether those results are sufficient to produce valid registry configuration.

### 12.7 Improve user-registry writes

Future writes should use a temporary file, validate the complete result, and then atomically replace the target. User files must never be migrated implicitly.

### 12.8 Redact secrets

Debug and raw-request output should redact authentication values while preserving useful diagnostics.

## 13. Compatibility Invariants for Registry v2 Migration

The migration must preserve:

- all existing exported function names
- the complete `llm_caller()` signature
- missing versus `NULL` semantics for `optionals`
- streaming override precedence
- explicit `api_url` precedence
- assistant/history input forms
- public call-result field names
- status `599` behavior relied on by experiments
- experiment output field names and meanings
- user registry priority
- existing v1 registry readability
- current public registration entry points

Any intentional behavioral change should be isolated, documented, and covered by compatibility tests.

## 14. Recommended Refactoring Boundary

The existing architecture can be evolved rather than replaced:

```text
Current v1 registry
  -> v1 compatibility adapter
  -> validated canonical runtime configuration
  -> request builder
  -> transport
  -> response parser
  -> existing normalized result
  -> unchanged experiment modules
```

This boundary retains the package's useful experiment and registration behavior while allowing Registry v2 to improve model and protocol adaptability.

## 15. Files Most Relevant to the Migration

Registry runtime:

- `R/register_utils.R`
- `R/register_read.R`
- `R/register_io.R`
- `R/register_entry.R`
- `R/register_validate.R`
- `R/get_registry_entry.R`
- `R/get_model_config.R`
- `R/registry_schema.R`
- `R/resolve_registry_entry.R` draft
- `inst/registry/system_registry.yaml`

Registration and discovery:

- `R/register_orchestrator.R`
- `R/register_probe_request.R`
- `R/register_build_input.R`
- `R/register_rank_endpoint.R`
- `R/register_classify.R`
- `R/register_preview.R`

Runtime:

- `R/llm_caller.R`
- `R/llm_parser.R`
- `R/json_utils.R`
- `R/error_handling.R`

Experiment compatibility:

- `R/trial_experiment.R`
- `R/factorial_trial_experiment.R`
- `R/conversation_experiment.R`
- `R/conversation_experiment_with_feedback.R`
- `R/multi_model.R`
- `R/schema.R`

Package metadata and documentation:

- `DESCRIPTION`
- `NAMESPACE`
- `man/`
- `AGENTS.md`

## 16. Backup Use

During later refactoring, use this document to answer three questions:

1. Which behavior existed before Registry v2?
2. Which part was configuration-driven and which part was hard-coded?
3. Which compatibility behavior must be retained or intentionally deprecated?

This document should remain descriptive. The evolving Registry v2 target architecture should be maintained separately from this current-state backup.
