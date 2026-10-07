# PsyLingLLM Development Guide

## Project Mission

PsyLingLLM is an R package for controlled psychological, psycholinguistic, cognitive, and educational experiments with large language models.

The package must let researchers run the same experimental design across models and providers while preserving comparable prompts, timing, responses, reasoning fields, token metrics, trial status, and logs. Registry-driven adaptability exists to protect experimental reproducibility, not merely to add more provider integrations.

Project reference:

- Repository: <https://github.com/HanMingPsy/PsyLingLLM-R>
- Current architecture backup: `inst/design/current-architecture-backup.md`

`AGENTS.md` is the single normative implementation plan for the Registry v2 migration. Do not create a second target-architecture or migration-plan document unless the user explicitly requests one. The current architecture backup is descriptive evidence of the 0.3 implementation, not a competing source of requirements.

Before changing registry or runtime behavior, read the relevant section of the current architecture backup and identify the compatibility behavior that must remain stable.

## PsyLingLLM 0.4.0 Goal

The primary 0.4.0 goal is **stable model and API adaptability**.

PsyLingLLM must be able to support current and future models, cloud providers, proxy services, and local runtimes without adding model-specific branches to core experiment or runtime code.

Expected extension behavior:

- A new model using an existing protocol should normally require registry configuration only.
- A new provider using an existing protocol should normally require provider/deployment configuration only.
- A genuinely new protocol may require one reusable protocol adapter, request builder, transport decoder, or response parser.
- Adding a new model must not require editing `llm_caller()`.
- Provider API changes should be handled by versioned interface configuration or a reusable protocol component, not model-name conditionals.

The system must remain strict enough to reject invalid configuration before a real experiment begins. Flexibility belongs at registry and adapter boundaries; the compiled runtime configuration must be explicit and validated.

Core principle:

```text
Flexible registry inputs
  -> strict validation and compatibility conversion
  -> canonical runtime configuration
  -> deterministic runtime execution
```

Do not solve adaptability by making YAML arbitrary or silently permissive.

## Current Migration Phase

Current phase: **Phase 8 local release validation is complete after the
conversation API and persistence-safety maintenance pass. The exact updated tarball still requires
the normal external multi-platform release checks before formal CRAN
submission. The internal Experiment Spec v1 trial workflow is implemented and
live-verified with DeepSeek; public planner API design and formal CRAN
submission remain separate approval boundaries.**

### Current implementation track: Experiment Spec v1 foundation

The current implementation provides a stable, internal-only workflow for
turning natural-language experiment requirements into a reviewed PsyLingLLM
trial plan. It extends the package beside the existing experiment API and does
not alter existing experiment execution semantics.

The verified test-only prototype is backed up by these commits:

- `7908f23 fix(registry): harden registration credential handling`
- `d7bcd26 feat(runtime): classify normalized response status`
- `0a034e1 docs(package): rebuild experiment workflow guide`
- `33852bb test(experiment): prototype natural language planning workflow`

The production foundation is delivered through these atomic commits:

- `636a88d feat(experiment): add trial spec schema foundation`
  adds the packaged Draft-07 schema, internal schema loading, strict JSON
  parsing, R semantic validation, fixtures, and offline agreement tests.
- `f49a2df feat(experiment): add reviewed trial plan workflow`
  adds deterministic trial-data normalization, condition-type stability,
  source-material fidelity review, Registry model/interface resolution,
  execution preview, plan-integrity checks, and explicit approval objects.
- `0da261a feat(experiment): compile approved trial plans`
  adds an allowlisted compiler for the existing `trial_experiment()` contract;
  it never evaluates model-generated R code and keeps runtime secrets outside
  the compiled plan.
- `9146ccc feat(experiment): validate trial results and receipts`
  adds experiment-result validation and secret-free execution receipts.
- `7c52832 feat(runtime): add registry structured output adapters`
  adds protocol-scoped OpenAI Chat and Responses JSON object/JSON Schema wire
  adapters without adding provider branches to `llm_caller()`.
- `a9293b7 feat(registry): declare verified JSON output modes`
  enables JSON object output for the verified DeepSeek Chat, OpenAI Chat,
  OpenAI Responses, and Qwen Chat production interfaces while leaving the
  historical GPT-4o Responses compatibility route unchanged.
- `b1a7af9 feat(experiment): prepare registry-driven planner calls`
  adds the two-turn toolbox/schema prompt contract and credential-free planner
  call specifications selected through Registry components.
- `8afec67 feat(experiment): validate planner responses locally`
  adds strict JSON parsing, semantic validation, source fidelity review, and
  minimal repair feedback without retaining raw provider responses.
- `aa170fe feat(experiment): orchestrate reviewed planner sessions`
  adds an internal two-turn planner with dependency-injected offline tests,
  one bounded validation repair, transient credential injection, and no
  automatic approval or experiment execution.
- `4acbdde test(experiment): verify production planner live path`
  replaces the manual live prototype path with the production planner,
  explicit approval, compiled trial execution, result validation, and receipt
  validation.

On 2026-10-03, the production workflow passed an explicit opt-in live DeepSeek
test using the bundled Registry: onboarding, Experiment Spec generation,
deterministic review, explicit test-harness approval, two `trial_experiment()`
runs, result validation, and secret-free receipt creation all succeeded. This
does not claim that the planner workflow has been live-tested with OpenAI,
Qwen, Anthropic, or every Registry entry. Default and CRAN tests remain offline.

The next implementation boundary requires explicit review before code changes:

1. Decide whether Experiment Spec v1 remains an internal post-0.4 prototype or
   becomes a supported public feature in a later release.
2. If public, review the smallest user-facing API names and separate planning,
   human approval, compilation, and execution rather than exporting all
   internal helpers.
3. Add roxygen2 documentation and README guidance only after that public
   contract is approved; never manually edit `NAMESPACE` or `.Rd` files.
4. Keep factorial, conversation, adaptive-feedback, and multi-model schemas
   out of scope until the ordinary-trial public workflow is stable.
5. Before any release containing this track, repeat the complete offline suite,
   source-tarball CRAN checks, tarball inspection, and relevant multi-platform
   checks. Live tests remain a separate explicit opt-in gate.

Delivered implementation order:

1. Add one versioned JSON Schema Draft-07 asset for the `trial` experiment
   plan. Draft-07 is the initial production dialect because the CRAN
   `jsonvalidate` package and its AJV engine document support for Drafts 04,
   06, and 07. Do not claim Draft 2020-12 runtime validation until the selected
   R validator supports and tests it.
2. Add internal schema loading, JSON parsing, structural validation, and
   PsyLingLLM semantic validation. Keep actionable R validation errors even
   when JSON Schema validation is also available.
3. Add deterministic material normalization, source-fidelity review, execution
   preview, and explicit approval objects.
4. Add an allowlisted compiler that can produce only the existing
   `trial_experiment()` call contract. It must return an R call specification;
   it must never parse or evaluate model-generated R code.
5. Add result validation and a secret-free execution receipt containing schema
   versions, model/interface identity, planned/completed runs, status summaries,
   and request IDs.
6. Only after the offline foundation is complete, add Registry-selected
   structured-output adapters for provider-native JSON object, JSON Schema, or
   tool-input modes. Provider wire shapes must not be hard-coded in the
   experiment planner or `llm_caller()`.

Initial scope and gates:

- Experiment Spec v1 supports ordinary `trial` experiments only.
- Factorial, conversation, adaptive-feedback, and multi-model schemas remain
  out of production scope until the trial path is stable.
- New functions remain internal during the foundation phase. Do not export
  them or modify generated `NAMESPACE`/`.Rd` files.
- Do not modify `llm_caller()` or existing experiment functions for this
  foundation.
- Do not modify production Registry YAML in the schema/validator commit.
- Keep API keys, API URLs, output paths, results, and arbitrary function names
  outside the model-generated plan.
- Treat JSON Schema as structural validation, not scientific or semantic
  validation. Material fidelity, Registry resolution, run limits, protected
  request fields, and approval remain explicit R checks.
- Add `jsonvalidate` to `Suggests` initially and use it conditionally in tests
  to check that JSON Schema and R validators agree. Do not add V8 to the core
  runtime dependency chain during the foundation phase.
- Default tests remain network-free. The existing natural-language live test
  stays explicit opt-in, secret-safe, short, and skipped on CRAN.
- Every implementation step must pass focused tests and the complete offline
  suite before the next layer begins.

Phase 1 delivered:

1. Define Registry v2 schema boundaries.
2. Add strict Registry v2 validation.
3. Detect Registry v1 and v2 inputs.
4. Convert v1 and v2 inputs into equivalent normalized configuration in memory.
5. Add characterization tests for current registry behavior.
6. Add equivalent v1/v2 fixtures and compare their normalized output.

Phase 2 delivered:

1. A unified registry bundle loader with separate system, user, default, raw,
   and merged views.
2. Explicit whole-entry source precedence: default, then system, then user.
3. One strict resolver for model keys, normalized keys, aliases, providers,
   interfaces, capabilities, defaults, headers, and endpoints.
4. One validated canonical runtime configuration for equivalent v1 and v2
   registries.
5. Compatibility delegation from `get_registry_entry()` and
   `get_model_config()` without changing their public signatures.
6. Network-free coverage for precedence, aliases, ambiguity, v1/v2
   equivalence, public return structures, and failure diagnostics.

Phase 2 was delivered through these atomic commits:

- `ca9aeda refactor(registry): introduce unified registry loader`
- `f30ba5a refactor(registry): introduce canonical model resolver`
- `06f7242 refactor(registry): delegate public registry resolution`

The Phase 2 source tarball passed `R CMD check` with `Status: OK`, and the full
test suite passed without credentials or real API requests.

Phases 3 and 4 subsequently introduced tested request-builder, transport,
response-parser, result-normalization, and orchestration boundaries. Phase 6
then delivered native OpenAI Chat, DeepSeek-compatible Chat, OpenAI Responses,
and Anthropic Messages protocol contracts together with provider-native
parameter forwarding, structured provider errors, and secret redaction.

The following boundaries remain in force as compatibility guarantees:

- Preserve every existing `llm_caller()` argument, its order, default, and
  behavior. The approved usability extension may append trailing `...` for
  provider-native request parameters; this is an additive public signature
  change and must have dedicated compatibility tests and documentation.
- Do not modify or refactor experiment functions during the Registry v2 runtime migration.
- Keep the migrated `inst/registry/system_registry.yaml` as one validated v2
  bundle; do not split it into multiple production files during Phase 8.
- Do not automatically modify user registry files.
- Do not combine request-builder, transport, parser, caller, or registration
  extraction in one change.
- Do not add provider-specific runtime branches.

Phase 2 intentionally retains two explicit constraints:

- A native v2 user source must currently be a self-contained valid bundle.
  Partial v2 overlays that reference system-only providers or interfaces are
  not supported until their merge-before-cross-reference-validation contract
  is designed and tested. Existing v1 user overrides remain supported.
- Invalid user YAML now fails with `registry_load_error` before model or network
  execution instead of being silently ignored. This safety tightening prevents
  an experiment from unexpectedly falling back to another registry source.

The Phase 6 readiness gate was implemented in this order:

1. Redact credentials and secret-like values from `return_raw`, debug output,
   warnings, conditions, snapshots, and logs without altering the actual
   transmitted request.
2. Replace native v2 cross-provider parameter mapping and exhaustive parameter
   allowlisting with provider-native request parameters. Preserve the v1
   `${PARAMETER}` compatibility path unchanged.
3. Allow named provider parameters through both the existing
   `optionals = list(...)` form and trailing `...`. Undeclared and duplicate
   parameters produce warnings, not local rejection; duplicate resolution is
   deterministic and last-value-wins. Parameters are never renamed.
4. Preserve complete provider error evidence, including HTTP status, message,
   provider error type, parameter, provider code, response body, response
   headers, and request ID when available, while retaining the existing public
   `error$code` and `error$message` compatibility fields and status `599`.
5. Revise the uncommitted native v2 fixtures and tests to use exact official
   wire parameter names and nested structures. Run focused tests, the complete
   offline suite, `R CMD build`, and `R CMD check` before requesting approval.

Phase 7 migrated the bundled system registry to a single Registry v2 bundle.
DeepSeek Chat and DeepSeek Reasoner share one native OpenAI Chat-compatible
interface; GPT-4o Chat uses its native Chat component. The historical GPT-4o
Responses entry remains on the `legacy_template_v1` compatibility component
inside the v2 bundle because changing its historical string-input request
shape would be a behavior change. The native OpenAI Responses component remains
available for new, explicitly configured v2 entries.

`load_registry()` continues to expose its documented flat v1-compatible public
shape through a read-only projection. Internal runtime resolution consumes the
strict v2 bundle directly. Registry v1 user files remain readable, retain
whole-entry precedence over the bundled v2 model, and are never rewritten.
Compatibility metadata preserves legacy interface labels and the bundled
default-stream behavior without treating `stream` as a provider parameter
default. Reasoning extraction is capability-gated so models that do not declare
reasoning retain their historical result behavior even when they share a typed
protocol parser with reasoning-capable models.

Phase 7 adds an exact previous-system-registry v1 fixture plus network-free
tests covering schema validation, all bundled model/interface resolutions,
public projection equivalence, all three `optionals` states, request
equivalence, v1 user precedence, and the complete non-stream caller pipeline
for every bundled interface. The complete offline suite passes, and the built
source tarball passes `R CMD check --no-manual` with `Status: OK` under the
Windows `C` locale. Network access and real credentials were not used.

Real-provider smoke tests were initially deferred until the user supplied
credentials and approved their use. Phase 7 was reviewed and committed before
Phase 8 release metadata and documentation work began.

Phase 8 local release preparation has now:

1. Raised the package version to 0.4.0 and added `Authors@R`, `URL`,
   `BugReports`, `Language`, and an expanded CRAN-facing description.
2. Added `NEWS.md` and corrected only release-relevant README content,
   including Registry v2 behavior, role mapping, Markdown structure, and
   obvious typographical errors.
3. Regenerated documentation with roxygen2 7.3.2; no generated `NAMESPACE` or
   `.Rd` changes were required.
4. Passed the complete network-free test suite and built the source tarball.
5. Verified that the tarball excludes development plans, architecture backups,
   check directories, histories, session data, and credentials.
6. Passed independent URL validation for the repository and issue tracker.
7. Passed local `R CMD check --as-cran --no-manual` on the final source tarball
   with `Status: OK` when CRAN incoming remote checks were disabled. A separate
   incoming-check run completed every package check and reported only the
   expected new-submission NOTE plus one transient GitHub connection reset;
   the same URLs passed the dedicated URL checker.
8. Submitted the release candidate to Win-builder R-devel. The first external
   run passed installation, code, examples, and tests but failed PDF manual
   generation because two roxygen lines used the unsupported Unicode character
   `⇒`. The source comments were replaced with ASCII prose, the affected `.Rd`
   file was regenerated with roxygen2, and the rebuilt tarball again passed the
   complete local `--as-cran --no-manual` check. The corrected tarball then
   passed the complete Win-builder R-devel check, including PDF and HTML manual
   generation, with only the expected new-submission and domain-spelling NOTE.
9. Attempted the official macOS package builder after explicit approval. Local
   package construction succeeded on every attempt, but the remote
   `/macbuilder/v1/submit` endpoint returned HTTP 502. No macOS check job was
   created; this remains an external-service blocker rather than a package
   failure.
10. Prepared the official `r-lib/actions` standard R package check workflow for
    macOS release, Windows release, and Ubuntu devel/release/oldrel. The
    workflow is excluded from the CRAN source tarball through `.Rbuildignore`,
    performs no live model API calls, and requires no provider credentials.
11. Passed all five GitHub Actions matrix jobs: macOS release, Windows release,
    Ubuntu devel, Ubuntu release, and Ubuntu oldrel-1. The multi-platform run is
    recorded at <https://github.com/HanMingPsy/PsyLingLLM-R/actions/runs/34935311192>.
12. Prepared `cran-comments.md` to summarize the release checks and explain the
    expected new-submission and domain-spelling NOTE. The file is excluded from
    the CRAN source tarball.
13. Audited the expanded provider catalog against current upstream
    documentation and official SDK contracts. Corrected the xAI Responses
    reasoning request metadata to use nested `reasoning.effort`, and marked the
    undocumented Meta `/compat/v1` response contract as experimental and
    unverified rather than claiming production support.
14. Added an opt-in production Registry live-test layer that suppresses user
    Registry overrides. With explicit user approval and environment-provided
    credentials, OpenAI Responses (`gpt-5.6-luna`), DeepSeek Chat and Responses
    (`deepseek-flash`), and Qwen Chat and Responses (`qwen3.8-flash`) passed
    non-stream and stream tests on 2026-09-17. Qwen also passed a complete
    bundled-Registry `trial_experiment()` data path.
15. Re-ran the separate live adapter suite. The Anthropic Messages adapter
    passed through a Qwen Anthropic-compatible endpoint; provider error
    evidence, secret redaction, trial data, and multi-turn conversation data
    also passed. This does not claim that the bundled Anthropic provider has
    been tested against an official Anthropic account.
16. Added a user-facing 0.4 support matrix that distinguishes live-verified
    integrations, offline protocol contracts, deployment templates, and
    experimental entries. Registry presence alone is not documented as proof
    of live provider support.
17. Re-ran the complete default offline suite, rebuilt and inspected the source
    tarball, and passed the final local `R CMD check --as-cran --no-manual`
    with `Status: OK`. The tarball contains the production Registry and opt-in
    live-test source but excludes credentials, development plans, check output,
    temporary directories, and local API results.
18. Added `adaptive_feedback_experiment()` as the canonical adaptive
    conversation entry point while retaining
    `conversation_experiment_with_feedback()` as an exact compatibility alias.
    The ordinary and adaptive conversation paths now validate conversation
    structure and execution controls before network work, preserve explicit
    `optionals = NULL`, and record auditable feedback outcomes. The same
    explicit-NULL forwarding defect was corrected in `multi_model_experiment()`.
    The default result directory now uses
    `tools::R_user_dir("PsyLingLLM", "data")`, and explicit output paths no
    longer initialize that default directory. The complete offline suite
    passed 1106 tests with 14
    credential-gated tests skipped, and the rebuilt source tarball passed local
    `R CMD check --as-cran --no-manual` with `Status: OK` under the Windows `C`
    locale.
19. Live-tested `conversation_experiment()` and
    `adaptive_feedback_experiment()` against the production Registry
    `deepseek-flash` entry on 2026-10-04. Ordinary two-turn history correctly
    recovered the first-turn codeword, and bounded adaptive insertion applied
    the callback prompt and returned the expected second-turn response. All 12
    live assertions passed without exposing credentials; generated results
    were confined to the R temporary directory.
20. Hardened CRAN-facing persistence behavior. New user Registry writes now use
    `tools::R_user_dir("PsyLingLLM", "config")`; the historical
    `~/.psylingllm` Registry remains readable at lower precedence and is never
    migrated or rewritten during loading. The v1 registration writer preserves
    malformed files, rejects native v2 bundles, validates the complete result,
    and replaces files through a same-directory temporary file. Experiment and
    combined-result writes now create parent directories, use recoverable file
    replacement, and raise errors instead of reporting false success. The
    complete offline suite passed 1106 tests with 14 live tests skipped, and
    the rebuilt tarball passed local `R CMD check --as-cran --no-manual` with
    `Status: OK`.

The full local `--as-cran` run reached all package checks successfully, but PDF
manual generation was blocked by the host MiKTeX installation lacking
`stringenc.sty`; Rd validation and the HTML manual passed. This is an external
toolchain limitation, not evidence of an Rd defect. The final tarball has now
passed R-devel/Win-builder and practical Windows, macOS, and Linux checks.
The post-maintenance Phase 8 local release regression is complete. The final
offline suite, source build, tarball inspection, and CRAN-style check all
passed after the Registry, experiments, tests, README, NEWS, and this guide
were updated. The current source tarball must still repeat the configured
external multi-platform checks before submission. Formal CRAN submission
remains a separate external action requiring explicit user approval.
Real-provider smoke tests remain separately opt-in and require user-provided
credentials.

## CRAN Submission Standard

PsyLingLLM 0.4.0 is intended for CRAN submission. Development and release decisions must follow the current official CRAN Repository Policy, the CRAN submission checklist, and Writing R Extensions:

- <https://cran.r-project.org/web/packages/policies.html>
- <https://cran.r-project.org/web/packages/submission_checklist.html>
- <https://cran.r-project.org/doc/manuals/r-release/R-exts.html>
- <https://cran.r-project.org/submit.html>

Apply these rules throughout development rather than postponing them until release:

- Treat the current official CRAN policies, Writing R Extensions, the submission checklist, and current `R CMD check --as-cran` results as authoritative. The CRAN-passing 0.3 release is useful regression evidence only and must not override current requirements.
- Build the submission archive with `R CMD build`; run `R CMD check --as-cran` against the built source tarball, not only against the working directory.
- The release candidate must have no ERROR, no WARNING, and no unexplained significant NOTE. Treat new check findings as release blockers.
- Test with the current R release and, before submission, R-devel. Use Win-builder for the CRAN Windows environment and a multi-platform service such as R-hub when practical.
- Keep code portable across Windows, macOS, and Linux. Do not rely on shell behavior, path separators, locale, encoding, case-sensitive file systems, or platform-specific utilities without guarded alternatives.
- Keep the declared minimum R version consistent with syntax and APIs used by the package. The current source uses the native pipe while `DESCRIPTION` declares R >= 4.0; Phase 1 must decide whether to remove that syntax or raise the minimum version deliberately.
- Keep dependencies minimal. Runtime dependencies belong in `Imports`; test-only dependencies belong in `Suggests` and must be used conditionally where appropriate. Required dependencies must be available from CRAN or Bioconductor.
- Normal tests, examples, installation, package loading, and checks must not require credentials or Internet access. External services must fail gracefully and must not create CRAN check failures.
- Live API smoke tests must remain explicit opt-in tests, disabled on CRAN, short, low-cost, and secret-safe. `NOT_CRAN` alone is not permission to make an external request; require a project-specific opt-in variable and credentials.
- Roxygen `@examples` sections are not required for every function. Add or retain examples according to current CRAN requirements and user value, not according to the 0.3 file layout. Executed examples must be short, deterministic, offline, portable, and verified after roxygen2 generates the corresponding Rd file. Do not call paid or production APIs. Use `\dontrun{}` only when execution genuinely requires user setup or an external service and when current CRAN guidance supports it.
- Use UTF-8 and non-ASCII text only in ways permitted by current CRAN requirements and portable across supported locales. Do not remove or forbid characters solely because they are non-ASCII; fix or escape them when generated Rd, parsing, encoding, locale, or check results show a real problem. Avoid decorative symbols that add no user value.
- Tests and examples may write only inside `tempdir()`. Package installation and loading must not write files, modify the global environment, start external applications, or make network requests.
- Runtime functions may write user data only after an explicit user action. New user-specific config/cache locations must use `tools::R_user_dir("PsyLingLLM", ...)`; retain a read-compatible path for the existing `~/.psylingllm` registry and do not silently move or rewrite it.
- Never expose API keys in examples, fixtures, condition messages, snapshots, logs, raw debug output, or returned diagnostic objects.
- Keep checks and examples efficient. Do not use more than two cores during checks, and do not introduce timing-sensitive tests.
- Keep source packages small and clean. Exclude development archives, IDE state, session files, check directories, local design artifacts not intended for users, and other non-package files through `.Rbuildignore`. In this repository, `AGENTS.md` and `inst/design/current-architecture-backup.md` are development inputs and must not be included in the CRAN tarball.
- Do not ship merge-conflict markers, generated session data, binary archives, or hidden workspace files. The existing conflicted `.gitignore`, root `R.zip`, `.Rhistory`, and hidden files under `R/` must be resolved or excluded before a release build.
- Use `Authors@R`, an informative CRAN-compliant `Title` and `Description`, current maintainer details, `URL`, and `BugReports` before submission. Review licenses and attribution for every bundled fixture, data file, and derived configuration.
- Generate `NAMESPACE` and `man/*.Rd` only from roxygen2 source. Verify documentation coverage, examples, aliases, argument documentation, and cross-references during every release check.
- Validate URLs and spelling, inspect the built tarball contents, and review the final CRAN check log before submission.

CRAN compatibility is a continuous phase gate. A refactor that passes focused tests but makes the package less portable, writes outside permitted locations during checks, requires network access, or introduces a check WARNING is not complete.

## Product Stability Requirements

Preserve the scientific and public contract of the package:

- Keep all existing exported functions available.
- Preserve every existing `llm_caller()` argument, order, default, and
  behavior. A trailing `...` may be added only for the approved
  provider-native parameter input described in this guide.
- Keep experiment modules provider-independent.
- Preserve experiment input semantics and output columns.
- Preserve response, reasoning, timing, token, request-ID, streaming, and trial-status behavior.
- Preserve status `599` behavior relied on by experiment code unless a separately approved compatibility change replaces it.
- Preserve user-registry precedence.
- Preserve Registry v1 readability throughout 0.4 development.
- Preserve missing-versus-`NULL` behavior, especially the three-state `optionals` contract.
- Preserve explicit `api_url` and `stream` override behavior unless an approved migration explicitly changes it.
- Do not automatically rewrite or migrate user files.

When architectural cleanliness conflicts with compatibility, add a compatibility adapter first. Remove legacy behavior only through a separately reviewed deprecation plan.

## Stability-First Engineering Policy

PsyLingLLM is a research tool, not an architecture demonstration. Reliability, understandable behavior, reproducible results, and maintainability take priority over architectural purity or theoretical extensibility.

Apply these rules to every migration decision:

- Prefer the smallest change that creates a clear compatibility or adaptability benefit.
- Do not introduce an abstraction solely because a future provider might need it. Require a current protocol difference, a tested fixture, or a concrete near-term use case.
- Do not create a general plugin framework while a small allowlisted component registry is sufficient.
- Do not split one stable file into many files unless the split produces an independently testable responsibility.
- Do not physically split Registry v2 into multiple production YAML files until loading, merging, validation, diagnostics, and rollback behavior are proven with a single bundle.
- Preserve the current working path while introducing a new path beside it. Switch defaults only after equivalence and integration tests pass.
- Keep compatibility wrappers until all internal callers and representative user workflows have migrated.
- Make each change independently reviewable and reversible. Avoid changes that simultaneously alter schema, resolution, request generation, transport, parsing, and experiment output.
- Prefer explicit code and data contracts over clever metaprogramming, implicit dispatch, or permissive recursive merging.
- Reject invalid configuration early, but provide actionable errors identifying the model, interface, field, and expected value.
- A registry configuration is not considered supported until its request and response contract passes network-free end-to-end tests.
- Optional live smoke tests confirm current external API availability, but failures in external services must not make normal package tests unstable.
- Preserve a known-good v1 execution route until the corresponding v2 route demonstrates equivalent behavior.
- If a proposed refactor makes debugging harder for package maintainers or researchers, simplify the design before implementation.

Use this priority order when trade-offs arise:

```text
1. Correct and reproducible experiment behavior
2. Backward compatibility
3. Clear diagnostics and testability
4. Maintainable model/API adaptability
5. Performance where measured and relevant
6. Architectural elegance
```

Do not claim support based only on schema validation or unit-level parsing. Support requires a resolved configuration, correct request generation, transport-level verification through a mock server or equivalent harness, correct response normalization, and an unchanged experiment-facing contract.

## `llm_caller()` Optimization Policy

`llm_caller()` may be optimized incrementally before the final orchestration-only stage. It does not need to remain structurally frozen during the migration.

Allowed work includes:

- Adding characterization tests around its current behavior.
- Extracting existing request construction, transport, streaming, parsing, and result-normalization logic into internal functions without changing behavior.
- Removing duplicated internal logic after equivalence is demonstrated by tests.
- Improving internal naming and data boundaries in small, reviewable changes.
- Fixing a confirmed defect when the fix is separately identified, tested, and approved.

Every `llm_caller()` change must preserve:

- Every existing public formal argument, its order, and its default. The only
  approved signature extension is trailing `...` for provider-native request
  parameters.
- The missing-versus-`NULL` semantics of `optionals`.
- URL and streaming override precedence.
- Message ordering and history behavior.
- Public return field names and compatible value types.
- Status, timeout, error, reasoning, usage, and first-token-latency behavior relied on by experiments.

Do not combine behavior-preserving extraction with new provider support in the same change. Do not add temporary provider branches as a shortcut. First capture the current contract, then move one responsibility at a time.

Experiment functions are out of scope for structural refactoring. They may be exercised by compatibility tests, but must not be edited unless the user separately approves a specific experiment-layer change.

## Registry v2 Domain Model

Registry v2 must separate:

```text
Model != Provider != Interface != Capability
```

### Model

Describes model identity and references:

- Registry key and aliases
- Provider reference
- Provider-facing model ID
- Supported interfaces
- Default interface
- Declared capabilities
- Provider-native model defaults and protection of protocol-owned structural
  fields

Models must not contain duplicated protocol implementations when an interface can be reused.

### Provider

Describes service or deployment information:

- Provider identity
- Cloud, local, proxy, or custom deployment type
- Endpoint defaults
- Authentication scheme and environment-variable name
- Provider-level headers or connection metadata

Provider identity must remain separate from deployment type. `openai`, `deepseek`, or `anthropic` are identities; `official`, `proxy`, and `local` are deployment properties.

Never store API keys or other secrets in registry files, fixtures, logs, previews, or raw diagnostic output.

### Interface

Describes a reusable, versioned API protocol:

- Request builder ID
- HTTP method and body encoding
- Endpoint path rules
- Message/input structure
- Provider-native parameter defaults and optional help metadata
- Non-stream and stream transport IDs
- Response decoder ID
- Semantic response channels
- Streaming event or framing rules

Examples include OpenAI Chat-compatible, OpenAI Responses, Anthropic Messages, Ollama, and future protocols.

Reuse interfaces by protocol. Do not create one adapter per model.

Native Registry v2 interfaces must use the exact parameter names and nested
request shapes documented by their upstream API. They must not map, alias,
rename, normalize, or guess parameters across providers or API generations.
For example, `max_tokens`, `max_completion_tokens`, and `max_output_tokens` are
distinct wire parameters. Compatibility is provided by retaining old
interfaces and the v1 template adapter, not by translating one parameter into
another.

### Capability

Describes research-relevant model behavior:

- Reasoning
- Streaming
- Vision
- Tools
- Structured output
- Log probabilities
- Token probabilities
- Long context

Capabilities are not limited to booleans. They may carry defaults, limits, or supported modes.

The model declares whether a capability is supported. The interface defines how a protocol activates or exposes that capability. Do not store provider-specific absolute response paths in the capability definition itself.

## Registry Representation

Registry v2 may initially use one bundle:

```yaml
schema_version: 2
providers: {}
interfaces: {}
capabilities: {}
models: {}
```

This keeps conceptual separation without introducing premature multi-file merge complexity.

The loader may later support separate files:

- `inst/registry/models.yaml`
- `inst/registry/providers.yaml`
- `inst/registry/interfaces.yaml`
- `inst/registry/capabilities.yaml`

Single-file and multi-file sources must compile into the same internal registry bundle. Do not migrate the production YAML until the compatibility layer and resolver are tested.

Resolution priority remains:

```text
Runtime arguments > User registry > System registry > Default registry
```

Define merge behavior explicitly for each domain. Do not use unrestricted recursive list merging when it can silently discard or combine incompatible interface definitions.

## Strictness and Extensibility Rules

- Detect the registry version before normalization.
- Treat missing version plus the existing model/interface shape as Registry v1.
- Reject unsupported explicit schema versions.
- Reject ambiguous mixed v1/v2 documents.
- Validate document, provider, interface, capability, and model structures.
- Validate all cross-references before runtime.
- Validate bundled and Registry-owned defaults for structural serializability,
  but do not use parameter metadata as a runtime allowlist for user values.
- Restrict request builders, transports, and response decoders to registered component IDs.
- Reject unknown component IDs before making a network request.
- Do not allow YAML to name or execute arbitrary R functions.
- Do not silently fall back to an OpenAI response path when a validated v2 selector fails.
- Keep permissive legacy parsing inside the v1 compatibility layer; do not copy legacy looseness into v2.
- Fail with specific errors for YAML syntax, schema, reference, adapter, model, interface, authentication, transport, and response failures.

## Provider-Native Parameter Policy

PsyLingLLM does not define a cross-provider generation-parameter vocabulary.
Native Registry v2 request parameters use upstream wire names and values
exactly as supplied by the Registry or user. Do not add `parameter_map`,
parameter aliases, automatic renaming, value translation, or fallback retries
for native v2 interfaces. Any mapping retained for `legacy_template_v1` is an
internal compatibility detail and must not influence native v2 behavior.

The Registry may provide:

- Provider-native defaults that make a bundled template usable.
- Optional parameter help text for discovery and documentation.
- Upstream source and verification metadata.

Parameter help is advisory. It is not a send allowlist and does not determine
whether a user-supplied value may reach the provider. If a Registry has no
default for a parameter, PsyLingLLM does not invent one. Missing provider
parameters and invalid user values normally reach the provider so the official
API can return its authoritative error. Bundled templates remain maintainer
responsibility and must include any defaults needed for their tested baseline
request; custom Registry API correctness remains the user's responsibility
after structural validation.

Preserve the existing `optionals` three-state contract:

```text
missing optionals -> use Registry defaults when present, otherwise send none
optionals = NULL  -> suppress Registry defaults
named list        -> use user values only, without merging Registry defaults
```

The approved trailing `...` extension provides a second, more convenient input
form. Named values captured from `...` are provider-native request parameters.
Nested lists, vectors, logical values, and explicit named `NULL` values must
remain JSON-serializable without flattening or coercive rewriting.

Parameter handling rules:

- User parameter names and values are transmitted unchanged.
- Undeclared parameter names produce a warning and are still transmitted.
- Values outside advisory Registry help metadata produce a warning and are
  still transmitted.
- Duplicate names produce a warning and resolve deterministically using the
  last supplied value; never emit duplicate JSON object keys.
- When both `optionals` and trailing `...` provide a name, the trailing `...`
  value wins with a warning.
- Existing formal arguments such as `stream`, `timeout`, `api_url`, and
  `return_raw` remain runtime controls. A provider body parameter that collides
  with a formal name must use `optionals`.
- Protocol-owned structural fields such as `model`, `messages`, `input`, and
  `system` must not be overridden through provider parameters because doing so
  would make resolved and transmitted experiment metadata disagree.
- Explicit `stream` precedence and the existing missing-versus-`NULL`
  semantics remain unchanged.
- Do not delete a rejected parameter, rename it, switch interfaces, or retry a
  billable request automatically after a provider error.

Registry structure remains strict even though provider parameters are open.
Reject malformed YAML, broken references, unknown internal component IDs,
unsupported authentication or HTTP structures, non-serializable Registry
defaults, and invalid request envelopes before transport. This is the boundary
between PsyLingLLM execution safety and user-owned upstream API correctness.

## Provider Error and Diagnostic Safety Contract

Provider errors are experimental evidence and must survive the complete
transport, parser, and normalization path. Preserve, when available:

- HTTP status and response headers.
- Official message, error type, failing parameter, and provider error code.
- Provider response body, including malformed or non-JSON error text.
- Provider request ID from either body or headers.
- Streaming error event details.

Retain existing public `error$code` and `error$message` behavior and status
`599` compatibility. Extend error details compatibly rather than replacing
those fields. Never silently turn a provider error into an apparently
successful empty answer.

Credentials and secret-like fields must never appear in `return_raw`, debug
output, warnings, conditions, snapshots, logs, or persisted results. Redact
authorization headers, API-key headers, known credential placeholders, and
secret-like body fields in diagnostic copies only. The actual transmitted
request must retain the original credential. Secret redaction is a hard gate
before any optional live API test.

## Response and Streaming Adaptability

Prefer semantic extraction over fixed structural paths.

For typed protocols, describe semantic channels using item, block, role, or event types:

```text
answer
reasoning
usage
request_id
answer_delta
reasoning_delta
error
done
```

OpenAI Responses-style and Anthropic-style protocols should be decoded by typed item/event semantics rather than assumptions about array position.

Fixed path selectors remain acceptable for legacy or untyped OpenAI-compatible JSON, but they must:

- Live in a reusable versioned interface, not in every model.
- Support ordered candidates where providers expose documented variants.
- Remain a compatibility mechanism rather than the default design for typed protocols.

New Registry v2 paths should use explicit YAML path segments. Keep legacy `list("...")`, dotted-path, and `..` wildcard conversion inside the v1 compatibility boundary.

Streaming framing and semantic event parsing are separate concerns. A transport may decode SSE or JSON Lines frames; a response parser interprets provider/protocol event meaning.

## Target Runtime Architecture

The final runtime flow is:

```text
User request
  -> Registry resolver
  -> Canonical model/provider/interface/capability configuration
  -> Request builder
  -> Transport
  -> Response parser
  -> Standardized result
```

The three primary runtime extension boundaries are:

1. Request Builder
2. Transport
3. Response Parser

Avoid adding additional abstraction layers until a concrete protocol requires them.

The final `llm_caller()` must only orchestrate:

```text
resolve -> build -> send -> parse -> normalize
```

It must not contain:

- Provider-name branches
- Model-name branches
- Provider-specific request bodies
- curl callbacks
- SSE or JSON Lines framing logic
- Provider-specific JSON paths
- Typed item/event parsing
- Provider-specific error extraction

## Registry Resolver Requirements

The resolver must eventually handle:

- Registry source loading
- User/system/default precedence
- v1 compatibility conversion
- Model key and alias resolution
- Provider resolution
- Interface selection
- Capability lookup
- Provider-native defaults and protocol-owned structural-field protection
- Cross-reference validation
- Compilation into one canonical runtime configuration

Registry resolution must not perform HTTP requests or parse provider responses.

Existing public functions such as `load_registry()`, `get_registry_entry()`, and `get_model_config()` must remain available as compatibility-facing APIs.

## Registration and Probe Requirements

Treat probing as discovery, not as the registry itself.

Target registration flow:

```text
User input
  -> Endpoint/protocol discovery
  -> Discovery evidence
  -> Capability analysis
  -> Registry compiler
  -> Validation
  -> Preview
  -> Optional persistence
```

Separate:

- User input normalization
- Network probing
- Protocol detection
- Candidate response analysis
- Capability analysis
- Registry compilation
- Validation
- Preview
- Persistence

Preserve the existing `llm_register()` public API while introducing these internal boundaries incrementally.

Future registration should support:

- A simple mode for known provider/protocol profiles.
- An advanced mode for explicit custom interfaces and semantic capability
  declarations.

Probe results are evidence, not guaranteed configuration. Store candidates, confidence, and warnings. Do not automatically compile or persist low-confidence discoveries.

Probe logic must not assume every endpoint uses OpenAI JSON, `stream`, SSE `data:`, or `[DONE]`.

## Testing and Real API Usability

Current credential policy:

- Normal development, examples, package checks, and default tests do not
  request, use, store, or transmit any real API key.
- Complete schema, compatibility, resolver, request-builder, transport, parser, caller, and experiment-compatibility tests with fixtures, injected mocks, or a local mock server.
- Real-provider smoke testing requires credentials supplied outside source
  control and explicit approval for the specific run. The maintained 0.4
  production paths were approved and tested on 2026-09-17; future reruns remain
  opt-in.
- Absence of credentials does not block Phases 1 through 4 or network-free protocol contract tests.
- Never copy a credential into source code, YAML, test fixtures, command history, snapshots, logs, Git diffs, or persisted debug output.

Registry v2 is not complete when YAML merely parses. A configuration must be proven through the full contract:

```text
Registry fixture
  -> validate
  -> resolve
  -> build request
  -> mock transport or local mock server
  -> parse response
  -> standardized result
```

Before changing existing behavior, add characterization tests for:

- System registry loading
- User registry precedence
- Interface selection
- Typed defaults
- Message ordering
- Role behavior
- `optionals` missing/`NULL`/named-list semantics
- Streaming precedence
- URL overrides
- Answer, reasoning, usage, and request-ID extraction
- Status `599`
- Existing experiment result fields

For Registry v2, test:

- Schema and cross-reference failures
- Equivalent v1/v2 normalized configuration
- Multiple models sharing one interface
- A previously unknown model added without core R changes
- Request generation for every supported interface
- Non-streaming and streaming response parsing
- Arbitrary network chunk boundaries
- Unicode split across chunks
- Typed output items and events
- Provider errors, malformed payloads, timeouts, and interrupted streams
- Secret redaction
- Provider-native parameters supplied through both `optionals` and trailing
  `...`
- Undeclared and advisory-value warnings without blocking transport
- Duplicate parameter warnings and deterministic last-value-wins behavior
- Exact preservation of nested objects, vectors, logicals, and named `NULL`
- Protection of protocol-owned request fields
- Complete provider error evidence and request IDs through normalization
- Equivalence of legacy v1 `${PARAMETER}` injection before and after the
  native v2 parameter changes

Normal tests must not use real provider APIs or credentials. Prefer fixtures, injected mock transports, and a local mock HTTP server.

Optional live smoke tests may be added separately and must:

- Be disabled by default and on CRAN.
- Require an explicit environment-variable opt-in.
- Use environment-provided credentials.
- Use short, low-cost requests.
- Never persist secrets or sensitive responses.

Run focused tests first, then the full test suite and `R CMD check` when practical. Do not weaken tests to make a refactor pass.

## PsyLingLLM 0.4.0 Acceptance Criteria

- A model using an existing interface can be added through registry configuration without changing core runtime code.
- A provider using an existing protocol can be added without changing `llm_caller()`.
- A new protocol can be added through reusable runtime components without provider branches in orchestration.
- OpenAI-compatible, DeepSeek, and Anthropic-style scenarios have network-free contract tests. Add a local-runtime scenario only when PsyLingLLM claims that protocol as supported in 0.4.0.
- The README support matrix accurately separates live-verified integrations,
  offline contracts, deployment templates, and experimental entries.
- Opt-in production Registry tests cover the maintained live-verified 0.4
  paths without altering user Registry files or persisting credentials.
- Existing bundled models continue working.
- Existing experiments, exported names, function signatures, and documented return contracts remain compatible.
- All existing `llm_caller()` formals retain their order, defaults, and
  behavior; the approved trailing `...` extension accepts provider-native
  parameters without renaming them.
- Existing v1 user registries remain readable and are not rewritten automatically.
- Invalid registry configuration fails before network execution.
- Request, transport, parsing, streaming, error, and timeout behavior are independently testable.
- Public model/capability discovery can eventually be provided through `llm_models()`, `llm_capabilities()`, and `find_llm()`.
- `llm_caller()` contains orchestration only.
- `return_raw`, debug output, warnings, conditions, and logs never expose
  credentials.
- Undeclared provider parameters can reach the provider after a warning, and
  official provider errors remain actionable after normalization.
- The built source tarball passes `R CMD check --as-cran` with no ERROR, no WARNING, and no unexplained significant NOTE.
- Normal tests and examples work without network access, credentials, or writes outside temporary directories.

## Scope Control for 0.4.0

The required 0.4.0 path is deliberately smaller than the complete long-term roadmap:

1. Phase 1A through Phase 1C: characterize v1, freeze the v2 schema, and add in-memory compatibility.
2. Phase 2: introduce one strict resolver and canonical runtime configuration.
3. Phase 3A through Phase 3C: extract request, transport, and response boundaries without behavior changes.
4. Phase 4: reduce `llm_caller()` to orchestration.
5. Phase 6 Readiness Gate: redact secrets, accept provider-native parameters,
   remove native mappings/allowlists, and preserve provider errors.
6. Phase 6 minimum proof: OpenAI-compatible and DeepSeek protocol-component
   reuse plus one genuinely different Anthropic-style protocol.
7. Phase 7: migrate only the bundled registry after equivalence is demonstrated.
8. Phase 8: complete CRAN release validation.

The following work is independently deferrable to 0.4.x and must not delay a stable 0.4.0 unless it becomes necessary for compatibility:

- Broad registration/probe redesign in Phase 5.
- A new local JSON Lines transport when no maintained 0.4.0 model requires it.
- New public query APIs such as `llm_models()`, `llm_capabilities()`, and `find_llm()`.
- A general external plugin system or user-defined executable adapter API.

Do not claim support for a deferred provider or protocol in 0.4.0 documentation. A smaller tested support matrix is preferable to a broad, partially verified one.

## Engineering Implementation Plan

The migration must proceed through the following engineering phases. Each phase must leave the package in a usable state. Do not combine phases into one large change.

### Phase 1A — Characterize the Current Contract

Goal: create a safety net before changing registry or runtime behavior.

Implementation steps:

1. Build the package tarball and record the baseline `R CMD check` findings before changing behavior.
2. Resolve or exclude non-package build inputs, including merge-conflict markers, session files, IDE state, root archives, and hidden files under `R/`.
3. Decide and document the minimum supported R version; reconcile the current R >= 4.0 declaration with native-pipe syntax.
4. Audit current roxygen examples and source/documentation encodings against current CRAN requirements and generated Rd checks. Use 0.3 only to explain historical decisions; do not bulk-add, delete, or rewrite content without evidence from the current checks.
5. Add testthat edition 3 infrastructure using `Suggests` and `Config/testthat/edition: 3`.
6. Snapshot all existing exported names and the formals of compatibility-critical public functions, not only `llm_caller()`.
7. Create sanitized Registry v1 fixtures based on representative bundled entries.
8. Test system-registry loading and user-registry precedence without writing to the real user registry.
9. Test single-interface selection, multi-interface ambiguity, missing-model errors, and current `get_model_config()` fallback behavior.
10. Test typed optional defaults and role mapping normalization.
11. Record the exact `llm_caller()` formal arguments, especially the missing `optionals` default.
12. Test request message ordering and the three-state `optionals` contract through existing internal helpers or a mock boundary.
13. Test current non-stream and stream extraction, status `599`, usage fields, request ID, and first-token latency behavior.
14. Add minimal experiment-facing contract tests without modifying experiment functions.

Expected files:

- Modify `DESCRIPTION` to add test dependencies under `Suggests`.
- Modify `.Rbuildignore` and repair `.gitignore` as separate package-hygiene changes where required.
- Add `tests/testthat.R`.
- Add focused files under `tests/testthat/`.
- Add sanitized fixtures under `tests/testthat/fixtures/`.
- Do not modify `R/llm_caller.R` or experiment modules in this step.

Exit criteria:

- Current Registry v1 behavior is reproducible in network-free tests.
- Existing exports, critical public signatures, and result structures have explicit tests.
- Tests never read or write the real user registry.
- A built tarball excludes development-only files and has a recorded baseline check result.

Suggested commit:

```text
fix(package): establish CRAN-safe build inputs
test(registry): characterize existing registry and runtime behavior
```

### Phase 1B — Define Registry v2 Schema

Goal: define a strict, minimal Registry v2 bundle without changing production loading behavior.

Implementation steps:

1. Define the top-level v2 bundle with `models`, `providers`, `interfaces`, and `capabilities` domains.
2. Define required and optional fields for each domain.
3. Define the built-in component-ID vocabulary for request builders, transports, and response decoders without implementing runtime dispatch yet.
4. Validate types, required fields, allowed values, and unknown fields.
5. Validate all cross-references between models, providers, interfaces, and capabilities.
6. Define explicit allowlists for Registry-owned structural overrides rather
   than unrestricted recursive merging. These structural allowlists must not
   become provider request-parameter allowlists.
7. Define canonical error messages containing the registry domain, entry ID, and invalid field.
8. Freeze the public contract of exported `validate_registry_schema()`: it must detect v1/v2 documents, dispatch to version-specific validation, return `TRUE` for valid supported documents, and fail with a stable `registry_validation_error` condition for invalid documents.
9. Keep implementation-availability checks separate from structural schema checks until the built-in component dispatchers exist.

Expected files:

- Modify `R/registry_schema.R`.
- Add schema-focused tests under `tests/testthat/`.
- Add a minimal valid Registry v2 fixture and multiple invalid fixtures.
- Regenerate documentation with roxygen2 only if public documentation changes.

Exit criteria:

- Valid v2 fixtures pass.
- Broken references and syntactically invalid or undeclared component IDs fail during validation; missing R implementations fail during resolver/dispatcher validation once those components exist.
- Validation performs no network or filesystem writes.
- Existing v1 registries are not rejected by the public compatibility-facing validation path.

Suggested commit:

```text
feat(registry): define strict Registry v2 schema
```

### Phase 1C — Add the v1/v2 Compatibility Layer

Goal: normalize current Registry v1 and future Registry v2 data without changing the production YAML or user files.

Implementation steps:

1. Detect v1, v2, unsupported versions, and invalid mixed documents.
2. Convert v1 registry entries into a v2-compatible in-memory representation.
3. Convert legacy provider labels into provider identity and deployment metadata without losing the original value.
4. Convert legacy request templates and typed defaults into compatibility configuration.
5. Convert legacy response and streaming paths into canonical selectors.
6. Preserve a `legacy_template_v1` compatibility mechanism for shapes that cannot yet use a native v2 interface.
7. Produce one canonical registry intermediate representation for equivalent v1 and v2 fixtures. Runtime model selection and compilation remain Phase 2 responsibilities.
8. Do not write converted data back to disk.

Expected files:

- Add `R/registry_compatibility.R`.
- Add `tests/testthat/test-registry-compatibility.R`.
- Add equivalent v1/v2 fixtures under `tests/fixtures/`.
- Do not modify `inst/registry/system_registry.yaml`.

Exit criteria:

- Equivalent v1 and v2 fixtures normalize to equivalent canonical registry values.
- Existing user-registry shapes remain readable.
- No compatibility conversion performs filesystem writes.

Suggested commit:

```text
feat(registry): add v1 and v2 compatibility conversion
```

### Phase 2 — Introduce the Unified Registry Resolver

Goal: make one internal layer responsible for model, provider, interface, capability, alias, default, and precedence resolution.

Implementation steps:

1. Define a registry bundle loader that keeps system, user, default, and merged views distinguishable.
2. Resolve model keys and aliases without heuristic provider fallbacks that can silently select the wrong model.
3. Resolve provider identity and deployment metadata.
4. Select the requested or default interface and reject ambiguity.
5. Resolve capabilities and provider-native defaults, and protect
   protocol-owned structural fields without treating parameter metadata as an
   allowlist.
6. Compile the resolved entry into a strict canonical runtime configuration.
7. Validate the compiled configuration before returning it.
8. Make `get_registry_entry()`, `get_model_config()`, and `load_registry()` delegate incrementally while preserving their public return contracts.
9. Resolve the existing untracked `R/resolve_registry_entry.R` ownership before editing or replacing it.

Expected files:

- Add or modify `R/registry_loader.R`.
- Add or modify `R/registry_resolver.R` or `R/resolve_registry_entry.R` after ownership is confirmed.
- Modify `R/get_registry_entry.R` incrementally.
- Modify `R/get_model_config.R` incrementally.
- Modify `R/register_utils.R` only where loader delegation is needed.
- Add resolver, alias, precedence, ambiguity, and compiled-config tests.

Exit criteria:

- One resolver produces canonical configuration from both v1 and v2 fixtures.
- Existing public registry functions retain documented behavior.
- Resolution performs no HTTP requests.
- User, system, and default precedence is explicit and tested.

Suggested commits:

```text
refactor(registry): introduce unified registry loader
refactor(registry): introduce canonical model resolver
```

### Phase 3A — Extract the Request Builder Boundary

Goal: move existing request construction behind an independently testable boundary without changing generated requests.

Implementation steps:

1. Define a normalized call context that preserves prompt, material, system message, history, role mapping, stream override, and `optionals` missing state.
2. Define a transport-neutral request object containing method, URL, headers, body, encoding, stream mode, transport ID, and timeout.
3. Move existing v1 template construction into a legacy request builder without changing its output.
4. Add an allowlisted request-builder dispatcher based on interface configuration.
5. Keep authentication values out of logs and snapshots.
6. Make `llm_caller()` delegate request construction while preserving its signature and results.

Expected files:

- Add `R/runtime_request_builder.R`.
- Add request-builder tests and request snapshots or structural assertions.
- Modify `R/llm_caller.R` only to delegate existing behavior.
- Do not modify experiment modules.

Exit criteria:

- Existing v1 calls generate equivalent URLs, headers, bodies, messages, parameters, and stream flags.
- Request generation is testable without curl or a live server.
- No provider-name or model-name branches are added.

Suggested commit:

```text
refactor(runtime): extract request builder without behavior changes
```

### Phase 3B — Extract the Transport Boundary

Goal: isolate HTTP execution and stream framing from request construction and response semantics.

Implementation steps:

1. Define a transport response object containing status, headers, raw/text body, frames/events, timing, and structured transport errors.
2. Move existing JSON POST behavior into `http_json` transport.
3. Move existing SSE framing into `sse_json` transport while preserving current behavior.
4. Preserve status `599` compatibility at the public normalization boundary.
5. Add injected/mock transport support for tests.
6. Add a local mock-server test for URL, headers, payload, timeout, HTTP errors, and stream chunk boundaries.
7. Do not interpret answer, reasoning, or usage fields in the transport layer.
8. Preserve the current no-automatic-retry behavior. Any future retry policy must be explicit, bounded, separately tested, and safe for potentially billable non-idempotent requests.

Expected files:

- Add `R/runtime_transport.R`.
- Add `R/runtime_transport_http.R` if separation is justified by independent testing.
- Add `R/runtime_transport_sse.R` if separation is justified by independent testing.
- Add a minimal CRAN-available mock-server package to `Suggests` only if injected transports cannot cover the HTTP integration contract; guard its use conditionally.
- Add transport and mock-server tests.
- Modify `R/llm_caller.R` only to delegate transport execution.

Exit criteria:

- Non-stream and SSE behavior remains compatible.
- Transport tests use no external API.
- Arbitrary chunks, multiple events per chunk, incomplete final frames, Unicode, timeout, and interruption are covered.
- The transport layer contains no provider-specific response extraction.

Suggested commit:

```text
refactor(runtime): extract transport without behavior changes
```

### Phase 3C — Extract the Response Parser Boundary

Goal: isolate response semantics and support strict reusable decoders.

Implementation steps:

1. Define a parsed response object for answer, reasoning, usage, request ID, finish reason, and provider error.
2. Consolidate overlapping path extraction behavior behind one compatibility implementation.
3. Preserve the legacy path decoder for current v1 entries.
4. Add typed-item and typed-event decoder contracts for modern protocols only when supported by concrete fixtures.
5. Keep stream framing in transport and event meaning in the parser.
6. Remove direct provider JSON extraction from `llm_caller()` by delegation.
7. Preserve whitespace, empty-response, reasoning, usage, and error semantics through characterization tests.

Expected files:

- Add `R/runtime_response_parser.R`.
- Modify `R/llm_parser.R` and `R/json_utils.R` incrementally where logic is reused.
- Modify `R/llm_caller.R` only to delegate parsing.
- Add parser fixtures and tests for legacy paths, typed items, typed events, malformed responses, and provider errors.

Exit criteria:

- Existing v1 response fixtures produce equivalent normalized values.
- Typed protocols are selected by interface decoder ID, not provider branches.
- `llm_caller()` no longer traverses provider response JSON directly.

Suggested commit:

```text
refactor(runtime): extract response parser without behavior changes
```

### Phase 4 — Complete `llm_caller()` Orchestration

Goal: simplify `llm_caller()` after its responsibilities have already moved behind tested boundaries.

Implementation steps:

1. Retain all existing public arguments, order, defaults, and behavior. The
   separately approved readiness work may append trailing `...` without
   changing the historical arguments.
2. Capture `missing(optionals)` at the public boundary.
3. Resolve canonical configuration.
4. Normalize call context.
5. Build the request.
6. Send the request.
7. Parse the response.
8. Normalize the existing public result.
9. Keep compatibility wrappers for existing internal helpers until removal is separately approved.
10. Verify experiment-facing behavior without editing experiment modules.

Expected files:

- Modify `R/llm_caller.R`.
- Add or modify `R/runtime_result.R` if result normalization has a meaningful independent contract.
- Extend caller compatibility and experiment-facing tests.

Exit criteria:

- `llm_caller()` performs `resolve -> build -> send -> parse -> normalize` only.
- Its public signature and return contract remain compatible.
- It contains no provider/model branches, curl callbacks, stream framing, or provider JSON traversal.
- Representative experiment tests pass without experiment-source changes.

Suggested commit:

```text
refactor(runtime): simplify llm caller orchestration
```

### Phase 5 — Separate Registration Discovery and Compilation

Goal: improve registration without discarding the existing two-pass probe investment.

This phase is independently deferrable to 0.4.x. Do not begin it merely because the core Registry v2 runtime is ready; require a concrete registration defect or approved 0.4.0 release need.

Implementation steps:

1. Define a stable discovery-result object containing evidence, candidates, confidence, and warnings.
2. Separate network probing from protocol detection.
3. Separate response candidate ranking from capability conclusions.
4. Add a Registry compiler that converts reviewed discovery results into valid v2 entries.
5. Keep Pass-1/Pass-2 validation as evidence where useful.
6. Prevent low-confidence results from being automatically persisted.
7. Preserve the existing `llm_register()` signature and advanced workflow.
8. Add simple registration only for provider/protocol profiles with reliable defaults.
9. Improve user-registry persistence atomically in a separate reviewed change.

Expected files:

- Modify `R/register_orchestrator.R` incrementally.
- Reuse and delegate from `R/register_probe_request.R`, `R/register_rank_endpoint.R`, `R/register_build_input.R`, and `R/register_entry.R`.
- Add discovery-result and Registry-compiler files only when their responsibilities are independently testable.
- Add registration compiler and persistence tests without live APIs.

Exit criteria:

- Probe output is not treated as automatically valid Registry configuration.
- Registration can compile a validated v2 entry without writing it.
- Existing registration entry points remain available.
- User files are never migrated implicitly.

Suggested commits:

```text
refactor(registration): separate discovery from registry compilation
feat(registration): compile validated Registry v2 entries
```

### Phase 6 Readiness Gate — Runtime Safety and Provider-Native Parameters

Goal: correct the confirmed safety and adaptability gaps before adding more
native protocol coverage. This gate is the active implementation phase and is
not optional.

Implement it through separately reviewable steps.

#### Gate A — Diagnostic Secret Redaction

1. Add one reusable recursive redaction helper for diagnostic copies.
2. Redact authorization and API-key headers case-insensitively.
3. Redact secret-like body fields and credential placeholders without changing
   the request sent to transport.
4. Apply redaction to `return_raw`, debug output, warnings, conditions, and any
   persisted logs.
5. Add tests using obvious fake secrets and assert that neither exact values
   nor bearer-token fragments appear in captured output or returned objects.

Expected files:

- Modify `R/runtime_result.R`.
- Modify `R/runtime_transport.R` or its debug helper.
- Add a small internal redaction helper only if reuse justifies it.
- Modify focused runtime-result and transport tests.

Exit criteria:

- Actual mock transport receives the unmodified fake credential.
- Every diagnostic representation contains only redacted values.
- Existing `return_raw` shape remains compatible.

Suggested commit:

```text
fix(runtime): redact credentials from diagnostics
```

#### Gate B — Provider-Native Parameter Input

1. Revise native v2 schema fields so parameter defaults and help use exact
   upstream wire names; remove native `parameter_map` and exhaustive rule
   coverage requirements.
2. Keep legacy v1 template parameter injection unchanged.
3. Append trailing `...` to `llm_caller()` while preserving every historical
   formal argument, order, default, and behavior.
4. Capture named values from `...` as provider-native request parameters.
5. Preserve `optionals = list(...)` as the compatibility input form.
6. Warn and transmit undeclared parameters unchanged.
7. Warn on duplicates and use the last supplied value, with trailing `...`
   taking precedence over `optionals`; do not emit duplicate JSON keys.
8. Preserve nested lists, vectors, logicals, and explicit named `NULL` values.
9. Reject only attempts to replace protocol-owned structural fields or values
   that cannot be represented as a named parameter collection.
10. Do not merge Registry defaults when either user parameter form is used.

Expected files:

- Modify `R/registry_schema.R`.
- Modify `R/runtime_request_builder.R`.
- Modify `R/llm_caller.R` only for trailing `...` capture and delegation.
- Modify public-formals, request-builder, caller, and Registry schema tests.
- Revise the uncommitted native Registry v2 fixtures.

Exit criteria:

- No native v2 request parameter is renamed or value-mapped.
- A newly introduced upstream parameter can be sent without R source changes.
- Unknown and duplicate parameters warn but do not prevent mock transport.
- Existing `optionals` three-state and v1 `${PARAMETER}` tests remain green.
- Experiment modules require no source edits.

Suggested commits:

```text
refactor(registry): simplify native parameter metadata
feat(runtime): accept provider-native request parameters
```

#### Gate C — Complete Provider Error Evidence

1. Preserve HTTP status, response headers, raw/text body, and parsed body in
   the transport response for successful and error responses.
2. Extract provider message, type, failing parameter, provider code, and
   request ID without assuming one provider shape.
3. Obtain request IDs from typed body fields or provider response headers when
   available.
4. Preserve malformed and non-JSON provider error text.
5. Extend normalized error details compatibly while retaining existing
   `error$code`, `error$message`, public result fields, and status `599`.
6. Ensure stream error events cannot normalize as successful empty results.

Expected files:

- Modify `R/runtime_transport.R` only where evidence is currently discarded.
- Modify `R/runtime_response_parser.R`.
- Modify `R/runtime_result.R` only through a compatibility-tested extension.
- Add provider-error fixtures and focused transport/parser/result tests.

Exit criteria:

- OpenAI-style, DeepSeek-style, Anthropic-style, generic JSON, plain-text, and
  streaming mock errors remain actionable after public normalization.
- Request IDs survive whether supplied in the response body or headers.
- No provider error triggers parameter deletion, interface fallback, or
  automatic retry.
- Error diagnostics are fully redacted.

Suggested commit:

```text
fix(runtime): preserve provider error details
```

#### Readiness Review

After Gates A through C:

1. Run focused schema, builder, transport, parser, result, caller, and public
   API tests.
2. Run the complete offline test suite.
3. Build the source tarball and run `R CMD check` on it.
4. Show the complete relevant diff and report all pre-existing working-tree
   changes.
5. Obtain explicit approval before committing the final gate change or
   resuming Phase 6.

### Phase 6 — Add Native Registry v2 Protocol Coverage

Goal: prove adaptability with a small set of real protocol families before migrating production configuration.

Implementation steps:

1. Add one native OpenAI Chat Completions-compatible interface fixture using
   exact official wire parameter names.
2. Add a DeepSeek fixture that reuses builders, transports, or parsers only
   where the actual contract is compatible. Use a distinct versioned interface
   when endpoints, roles, parameters, reasoning fields, or tool-call history
   requirements differ.
3. Add one typed OpenAI Responses fixture using item/event semantics.
4. Add one Anthropic-style fixture using content-block/event semantics.
5. Add a local-runtime fixture only if that protocol is part of the approved 0.4.0 support matrix; otherwise defer it rather than adding an unused transport.
6. Verify that a newly named model using an existing interface requires no R runtime change.
7. Add optional, explicit live smoke tests separately from normal package tests.
8. Do not add native parameter mappings or treat advisory parameter help as an
   allowlist.

Expected files:

- Add protocol-focused Registry fixtures.
- Add only the builders, transports, or decoders required by concrete fixtures.
- Add network-free end-to-end contract tests.
- Do not edit experiment modules.

Exit criteria:

- Supported protocol fixtures complete validate, resolve, build, send-mock, parse, and normalize flows.
- New models reuse interfaces rather than duplicating adapters.
- No provider-specific branches appear in `llm_caller()`.

Suggested commits should be protocol-scoped, for example:

```text
feat(runtime): add typed Responses protocol adapter
feat(runtime): add Anthropic messages protocol adapter
feat(runtime): add JSON Lines transport for local models
```

### Phase 7 — Migrate the Production System Registry

Goal: switch bundled configuration only after v2 behavior is proven equivalent.

Implementation steps:

1. Compile the existing bundled models into a reviewed Registry v2 bundle.
2. Compare v1 and v2 resolved configurations and generated requests.
3. Run network-free end-to-end fixtures for every bundled interface.
4. Keep the v1 compatibility loader available for user registries.
5. Switch the bundled default only after all equivalence gates pass.
6. Do not rewrite user registry files.
7. Provide an explicit, backup-producing migration tool only if persistent user migration is later required.

Expected files:

- Add or migrate the production Registry v2 bundle under `inst/registry/`.
- Modify the internal registry loader.
- Add complete bundled-registry regression tests.
- Update roxygen source documentation and regenerate generated documentation when necessary.

Exit criteria:

- Every bundled model resolves and produces a valid request.
- Existing v1 user registries still resolve.
- Switching production Registry versions does not change experiment-facing results.
- Rollback to the previous bundled Registry path remains straightforward for the release candidate.

Suggested commit:

```text
feat(registry): migrate bundled models to Registry v2
```

### Phase 8 — Complete CRAN Release Validation

Goal: produce a clean, portable 0.4.0 source tarball ready for CRAN submission. New query APIs are not part of this release gate and may be added later.

Implementation steps:

1. Confirm all existing exports remain documented and compatible; do not add release-only APIs without separate approval.
2. Update roxygen2 source documentation and regenerate `NAMESPACE` and `man/*.Rd` through roxygen2 only.
3. Make `DESCRIPTION` CRAN-ready, including `Authors@R`, informative `Title` and `Description`, correct dependency fields, minimum R version, `URL`, and `BugReports`.
4. Review license, attribution, bundled fixtures, data files, registry content, and package size.
5. Review `.Rbuildignore`, build the source tarball, and inspect its file list for archives, histories, IDE state, credentials, check output, and development-only files.
6. Run the complete offline test suite and `R CMD check --as-cran` on the built tarball under the current R release.
7. Check with R-devel on Win-builder and use multi-platform checks for Windows, macOS, and Linux when practical.
8. Resolve every ERROR and WARNING and every significant NOTE; record a concise explanation only for findings that are genuinely unavoidable.
9. Run explicitly enabled live smoke tests for maintained providers outside normal CRAN checks.
10. Update the package version and release notes only after all engineering and CRAN acceptance criteria pass.

Exit criteria:

- No existing export is removed or silently changes contract.
- Normal tests and examples require no network, credentials, or user-directory writes.
- The built source tarball passes `R CMD check --as-cran` with no ERROR, no WARNING, and no unexplained significant NOTE.
- Cross-platform check results do not reveal portability failures.
- The final tarball contains only intended package files and the v0.4.0 acceptance criteria in this file are satisfied.

Suggested commits:

```text
test(registry): complete Registry v2 compatibility coverage
docs(package): prepare Registry v2 release documentation
fix(package): satisfy CRAN release checks
```

### Phase Gate for Every Implementation Step

Before editing:

1. Confirm the work belongs to the active phase.
2. Read the affected current-architecture sections.
3. List files to add and modify.
4. State the compatibility behavior being protected.
5. State the focused tests that will prove the change.

After editing:

1. Run focused tests.
2. Compare old and new behavior where applicable.
3. Run the broader suite and package check when practical.
4. Show the complete relevant Git diff.
5. Report unrelated working-tree changes.
6. Do not commit until the user approves the diff.

If a phase cannot meet its exit criteria without broadening scope, stop and request review instead of silently continuing into the next phase.

## Important Files

Current architecture reference:

- `inst/design/current-architecture-backup.md`

Registry loading, compatibility, and validation:

- `R/register_utils.R`
- `R/register_read.R`
- `R/register_io.R`
- `R/register_entry.R`
- `R/register_validate.R`
- `R/get_registry_entry.R`
- `R/get_model_config.R`
- `R/registry_schema.R`
- `R/registry_compatibility.R`
- `R/registry_loader.R`
- `R/registry_resolver.R`
- `R/registry_query.R` when introduced

Registration and discovery:

- `R/register_orchestrator.R`
- `R/register_probe_request.R`
- `R/register_build_input.R`
- `R/register_rank_endpoint.R`
- `R/register_classify.R`
- `R/register_preview.R`
- Discovery-result, capability-analysis, and Registry-compiler files introduced later

Runtime:

- `R/llm_caller.R`
- `R/llm_parser.R`
- `R/json_utils.R`
- `R/error_handling.R`
- `R/runtime_request_builder.R`
- `R/runtime_transport.R`
- `R/runtime_response_parser.R`
- `R/runtime_result.R`

Experiment compatibility:

- `R/trial_experiment.R`
- `R/factorial_trial_experiment.R`
- `R/conversation_experiment.R`
- `R/adaptive_feedback_experiment.R`
- `R/adaptive_feedback_utils.R`
- `R/multi_model.R`
- `R/schema.R`

Registry configuration and tests:

- `inst/registry/system_registry.yaml`
- Future Registry v2 bundle or domain files
- `tests/testthat.R`
- `tests/testthat/`
- `tests/testthat/fixtures/`

Package metadata and generated documentation:

- `DESCRIPTION`
- `NAMESPACE`
- `man/`

## R Package Rules

- Follow standard R package structure and conventions.
- Use snake_case for new function and argument names.
- Follow tidyverse style unless a small compatibility-preserving deviation is necessary.
- Use roxygen2 for all exported functions and public documentation.
- Never manually edit generated `man/*.Rd` files.
- Never manually edit generated `NAMESPACE`.
- Regenerate documentation with roxygen2 after changing exported APIs or documentation.
- Declare runtime dependencies in `Imports` and development/test dependencies in `Suggests`.
- Use testthat edition 3 for new tests.
- Do not add a dependency without explaining its architectural need.
- Avoid unrelated formatting, renaming, or file rewrites during migration work.
- Keep `DESCRIPTION`'s minimum R version aligned with every syntax feature and API used in production code.
- Build and check the source tarball, not only the development directory.
- Keep normal tests and examples offline, deterministic, credential-free, and confined to temporary files.
- Treat CRAN portability and package-policy failures as correctness defects, not release housekeeping.
- Follow current CRAN documentation checks. Use 0.3 documentation only as regression evidence, and verify generated Rd output whenever roxygen text changes.

## Git and Change-Control Rules

Use Conventional Commits:

- `feat:` for new user-visible capability
- `fix:` for bug fixes
- `refactor:` for behavior-preserving structural changes
- `test:` for test-only changes
- `docs:` for documentation-only changes

Keep commits atomic and scoped to one migration concern. Do not commit automatically.

Before a major change:

1. Read the applicable architecture documentation.
2. Explain the planned change and why it belongs to the current phase.
3. List files to add and modify.
4. Identify compatibility and test risks.

After a change:

1. Run focused tests.
2. Run the full suite and package check when practical.
3. Show `git diff` for review.
4. Report pre-existing or unrelated working-tree changes.
5. Wait for approval before committing.

Do not overwrite unrelated user changes or untracked work. If an existing change overlaps the task, stop and report the conflict before proceeding.
