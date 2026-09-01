\# PsyLingLLM Development Guide



\## Project



PsyLingLLM is an R package for psychological and psycholinguistic experiments using LLMs.



\## Current Goal



Migrate the LLM runtime to Registry v2 architecture.



Current phase:



Phase 1: Registry v2 compatibility foundation.



\## Architecture Rules



\- Keep existing public APIs.

\- Keep llm\_caller() function signature unchanged.

\- Do not rewrite experiment functions during registry migration.

\- Do not automatically modify user registry files.



\## R Package Rules



\- Use roxygen2 documentation for exported functions.

\- Use snake\_case function names.

\- Follow tidyverse style.

\- Never manually edit man/\*.Rd.

\- Never manually edit generated NAMESPACE.



\## Git Rules



Use Conventional Commits:



feat:

fix:

refactor:

docs:

test:



\## Registry v2 Migration Strategy



Order:



1\. Registry schema validation.

2\. v1/v2 compatibility layer.

3\. Unified registry resolver.

4\. Request builder abstraction.

5\. Transport abstraction.

6\. Response parser abstraction.

7\. Refactor llm\_caller() into orchestration layer.



\## Development Workflow



Before major changes:



1\. Explain planned changes.

2\. List affected files.

3\. Show git diff after changes.

4\. Do not commit automatically.

