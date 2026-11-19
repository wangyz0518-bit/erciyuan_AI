# Person-scoped model gateway — Issue #39 development integration

This is a development-only, character-scoped FastAPI gateway. It does not
replace the local SQLite original timeline or create server-side conversations.

## Local offline mock test

Use Python 3.12+:

~~~bash
cd services/person_gateway
python -m pip install -r requirements.txt
python -m pytest -q
~~~

The default provider is Mock. Tests use local fakes and httpx.MockTransport;
they never call a paid API.

## Local loopback server

Configure a strong development token and an explicit character allowlist:

~~~bash
export PERSON_GATEWAY_TOKEN="a-unique-long-local-development-token"
export PERSON_GATEWAY_CHARACTERS="star,moon"
python gateway.py
~~~

The entry point binds to 127.0.0.1:8788 only. The token maps to a synthetic
local owner and the allowlist restricts which character IDs it can address.
This is not production authentication, account management, or a deployable
multi-user service. Do not expose it to a public interface.

The SQLite ledger uses a uniqueness constraint and WAL. The active cancellation
registry is process-local. Run a single process only; multi-process production
concurrency, durable distributed cancellation, rate limiting and account-level
authorization are not implemented.

## Optional provider wiring — not authorized by this code change

DeepSeek streaming is implemented but disabled by default. It can only be
enabled when both PERSON_GATEWAY_MODE=live and
PERSON_LIVE_CALLS_ENABLED=true are explicitly configured, and
DEEPSEEK_API_KEY is available outside the repository. This may incur external
charges. No such calls are made by this delivery or its automated tests.

## Security and context boundaries

- The only system prompt is a fixed server-owned policy.
- The client-supplied stable identity prefix is serialized first as untrusted
  profile context; it is never inserted into the system role.
- Prior events, claimed speaker roles, memory summaries and expanded source
  events are serialized as untrusted reference data. Client-supplied
  assistant roles are never emitted as provider assistant messages.
- Context is capped at 24,000 dynamic characters and 64 KiB of UTF-8 context;
  the JSON turn body is capped at 64 KiB.
- expanded_sources is included in the provider context.
- Cancellation sets the request ledger state and cancels the active provider
  task in the same process. A disconnected client marks the result unknown and
  cancels the local provider task. A provider may already have incurred a
  charge before cancellation takes effect.
- A process restart converts unfinished requests to unknown; the client
  must query status and must not automatically retry a potentially charged call.

Protocol design: docs/接口/person-text-gateway-v1-20261118.md.

## Proven / not proven

Proven only when the offline test suite and GitHub Actions pass: mock SSE,
owner/character allowlist, request idempotency, restart recovery to unknown,
context trust boundaries and budgets, provider task cancellation, and mocked
DeepSeek SSE parsing/error mapping.

Not proven: real LLM quality, Prompt Cache hit rate, actual Token usage/cost,
true account authentication, production multi-process concurrency, public
network safety, real device integration, or real user authorization and data
export. SQLite original events, archive and persona versioning remain owned by
apps/mobile (#36/#47); the server never changes the user's logical timeline.

Reuse reviewed: repository-owner PR #21 provider/streaming patterns and PR #22
transport cancellation/retry principles. Other contributors' PRs are not
modified or merged.

## Try character reply playback on Android

Use the same person gateway for text and audio. In PowerShell, from this directory with the requirements installed:

```powershell
$env:PERSON_GATEWAY_TOKEN = [guid]::NewGuid().ToString('N')
$env:PERSON_GATEWAY_CHARACTERS = 'star,moon'
$env:PERSON_GATEWAY_MODE = 'mock'
$env:PERSON_VOICE_MODE = 'demo'
adb reverse tcp:8788 tcp:8788
$gateway = Start-Process -FilePath (Get-Command python).Source -ArgumentList 'gateway.py' -WindowStyle Hidden -PassThru
```

In the same terminal start the app. The child gateway and Flutter share the generated development token for this run.

```powershell
Push-Location ../../apps/mobile
try {
    flutter run --dart-define=PERSON_GATEWAY_URL=http://127.0.0.1:8788 --dart-define=PERSON_GATEWAY_DEV_TOKEN=$env:PERSON_GATEWAY_TOKEN
} finally {
    Pop-Location
    if (!$gateway.HasExited) { $gateway.Kill() }
}
```

Open 小星, tap the speaker in the title bar, confirm, then send a message. Demo mode returns mock text and a 440 Hz test tone. Switch to 小月 and enable her speaker to hear 660 Hz. Leaving the page or backgrounding the app stops the stream. The normal offline launch still works without a gateway.

For authorized real synthesis, set `PERSON_VOICE_MODE=live` and supply server-side `DASHSCOPE_API_KEY`. Set `PERSON_VOICE_CATALOG` to the absolute path to your existing PoC `voice_profiles.sqlite` to use its current bindings read-only. 小星 maps to `xing` and 小月 to `yue`. The model, workspace and provider account must match the original catalogue. Alternatively, configure the two role voices explicitly with `COSYVOICE_VOICE_ID` and `COSYVOICE_YUE_VOICE_ID`. An absent binding fails for that role. The existing DeepSeek live opt-in controls text separately. Keep private databases, account identifiers, voice IDs and credentials outside Git.
