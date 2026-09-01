\# Registry v2 Design



Goals:



\- API changes should mostly be YAML-driven.

\- Remove model-specific branches.

\- Support multiple protocols.



Supported protocols:



\- openai\_chat

\- openai\_responses

\- anthropic\_messages

\- gemini



Registry fields:



\- provider

\- capabilities

\- interfaces

\- request

\- response

\- streaming

