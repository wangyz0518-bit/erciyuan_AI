# Person-scoped model gateway — Issue #39 development integration

This is a new development-only, character-scoped FastAPI gateway. It does not
replace the local SQLite original timeline or create server-side conversations.

## Local offline mock test

Use Python 3.12+:

~~~bash
cd services/person_gateway
python -m pip install -r requirements.txt
python -m pytest -q
~~~

Default provider is Mock; test cases never call a paid API. For a manually
launched local server, configure a strong local token (24+ characters):

~~~bash
export PERSON_GATEWAY_TOKEN="a-unique-long-local-development-token"
python gateway.py
~~~

The entry point binds to 127.0.0.1:8788 ONLY. This is not public deployment,
production authentication or user login. Keep local SQLite ledger and model keys
out of Git. A per-token synthetic local owner is used solely for development.

## Optional provider wiring — not authorized by this code change

DeepSeek stream adaptation is implemented but disabled by default. It can
only be enabled when both PERSON_GATEWAY_MODE=live and
PERSON_LIVE_CALLS_ENABLED=true are explicitly configured, and DEEPSEEK_API_KEY
is available outside the repository. This would incur external charges. No
such calls are made by the automated test suite or by this delivery.

Protocol design: docs/接口/person-text-gateway-v1-20261118.md.

## Proven/not proven

- Proven by offline tests once CI passes: owner+character+request_id ledger
  isolation, replay fingerprint, mock SSE, incomplete failure handling, cancel,
  stable identity-first prompt ordering and disabled-live-call guard.
- **Not yet proven**: real LLM quality, Prompt Cache hit rate, Token charge,
  true service authentication/authorization, production safe public networking,
  device-to-server integration, or real user authorization and data export.
- SQLite original events, archive and persona versioning are owned by
  apps/mobile/ (#36/#47); server never changes the user's logical timeline.

Reuse reviewed: repository-owner PR #21 Providers/streaming code patterns;
#22 transport retry/cancel principles. The older development gateway and
other contributor PRs are not modified or merged.
