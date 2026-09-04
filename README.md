<div align="center">

# Nota

**A macOS agent that notices when you are stuck, and quietly tells you why.**

</div>

```
  you, at 16:04                              Nota, top-right of your screen
  ────────────────────────────               ─────────────────────────────────
  D14 just went red and you                 ╭───────────────────────────────╮
  have no idea why. The formula             │  Fix the #REF! error in D14   │
  looks fine. You start opening             │  Microsoft Excel · Q3-Budget  │
  sheets to find out what moved.            │                               │
                                            │  ✔  D14 points at Sheet2!B7,  │
                                            │     which no longer exists    │
                                            │  ○  Repoint it at the renamed │
                                            │     Costs range               │
                                            ╰───────────────────────────────╯
```

No hotkey, no prompt, no tab-switch. It was already watching, it worked out
what broke, and it said so in the corner.

Named for the *nota* of *nota bene*: the mark a reader leaves in the margin
next to the thing that matters. Beside the work, never on top of it, and easy
to ignore.

Everything runs on-device. No API keys, no per-token cost, nothing leaves the
machine.

## Where the project is now

Working today, for two apps:

| | |
| --- | --- |
| **Watches** | Ghostty and Excel, via the Accessibility API and AppleScript |
| **Decides** | Apple Foundation Models, 0.4-0.8 s, 8/8 correct over the fixture suite |
| **Writes** | The card, from the screen text alone |
| **Costs** | Nothing. No network, no tokens, no account |

The pipeline is real and end-to-end: something changes on screen, the readers
describe it, triage decides whether you are stuck, and a card appears only if
you are. `nota-probe` holds it to 13 fixtures and passes.

Two things are honestly not done.

**Advice quality.** The on-device model reliably tells you *that* something is
wrong and *what* is wrong. It does not reliably tell you *how to fix it* — it
invents keyboard shortcuts, recommends `gem install` for a Homebrew formula, and
once emitted a fragment of webpack source. The Tier 3 sidecar exists to take
over the writing and is fully wired and tested, but its weights cannot be
downloaded on the network this was built on, so nothing has measured whether a
27B model actually fixes it.

**Everything else on screen.** Browsers and Teams expose no usable text, so they
are excluded rather than guessed at. They need the OCR path, which is not
written.

Not started: Tier 4, the voice in and voice out.

## Why it is built in tiers

Sending screenshots to a model on a timer is the obvious design and the wrong
one. At Claude's high-resolution tier a 3024x1964 screen costs 4,784 visual
tokens per frame, which is roughly $56/day on Haiku at one frame per second.
Running locally removes the dollars but not the latency or the battery drain, so
the same ladder applies: extract structured text where possible, and only wake a
model on a real event.

| Tier | What it does | Cost |
| ---- | ------------ | ---- |
| 0 | Accessibility observers and frontmost-app changes decide something happened at all | ~1 ms |
| 1 | Pull structured context: AX tree, AppleScript for Excel/Word/Numbers, Vision OCR as fallback | ~10-50 ms |
| 2 | Apple Foundation Models triages "does this need help?" from text alone | ~400-800 ms |
| 3 | A local model via MLX writes the actual guidance | ~1-3 s |
| 4 | SpeechTranscriber in, Kokoro-82M out | ~180-500 ms to first audio |

Tier 2 is the load-bearing one. It is free and on-device, so it can run on every
screen event and keep the expensive vision model idle most of the time.

### Where the ladder actually stops today

Two apps hand over real text: Ghostty exposes its buffer through the
Accessibility API, and Excel answers AppleScript with the active cell's address,
formula and computed value. Browsers and Teams expose a focused element with
nothing in it, so they are excluded until the OCR path exists — otherwise every
screen event there spends a model call describing an empty room.

Tier 3 was originally a vision model, and for these two apps it has nothing to
do: once the context is already text, re-reading it from pixels costs seconds
and gigabytes to learn what Tier 1 stated exactly. So the first working
prototype had no Python in it at all — Tier 2 wrote the cards as well as
triaging them.

That is still the fallback, but it is not the plan, because Tier 2 turned out to
be bad at writing. Tier 3 is now a *text* model whose only job is the prose,
which is a different tier-3 than the table above originally meant. Vision moves
to whenever the OCR path arrives.

### What the on-device model is and is not good at

Measured with `nota-probe` against fixed screens, the split is sharp and it
did not move across three prompt revisions.

Triage is good. Eight of eight decisions were correct in 0.4-0.8 s: it catches a
missing scheme, a `command not found`, a `#DIV/0!` and a `#REF!`, and it stays
quiet for a clean run, a long successful build, an idle prompt and a
non-blocking `npm warn`. Diagnosis is good too — "Scheme 'Notta' not found in
the project", "xcodegen is not installed".

Writing the fix is not good, and prompting did not save it:

- It invents mechanisms. Early versions produced "Press Command + Shift + A"
  and "open the Formula Auditing Tool", neither of which exists. Banning
  keystrokes and menu paths outright removed those, but not the underlying
  habit.
- It states remembered facts that are wrong. `sudo gem install xcodegen`
  survived every revision; xcodegen is a Homebrew formula.
- It gets the direction backwards. Told that `Notta` is not a scheme in a
  project containing `Nota`, it suggested changing `Nota` to `Notta`.
- Under the sampled retry path it emitted `var __webpack_require__ = ...` into
  a step, which is training data rather than advice.

So the model can tell you reliably *that* something is wrong and *what* is
wrong, and cannot tell you *how to fix it*. `isPlausibleStep` exists to keep the
worst of that off the screen, and a card with no surviving steps is dropped
rather than shown.

### The probe

```sh
xcodebuild -project Nota.xcodeproj -scheme NotaProbe build
"$(xcodebuild -project Nota.xcodeproj -scheme NotaProbe \
  -showBuildSettings | awk -F' = ' '/ BUILT_PRODUCTS_DIR /{print $2; exit}')/nota-probe"
```

It runs the real `ContextBrief` and provider code against the fixtures in
`probe/Fixtures.swift` and exits non-zero when a verdict disagrees with its
expectation. It shares the sources it exercises rather than copying them, so a
prompt cannot drift away from its test.

Pass `--tiered` to send the writing to the sidecar, which is the shipping
configuration; without it everything runs on the system model, so the two are
comparable over identical fixtures.

Most fixtures are negative cases, because the silence bias is what an innocuous
prompt edit breaks first. The fixtures that expect no brief at all need no
model, so they still run with Apple Intelligence switched off.

Note what the probe does *not* check: it asserts the decision, not the prose. It
passed 13/13 on the run that emitted webpack source.

## Layout

```
app/Sources/Context/    Tier 0 and 1: what happened, and the cheap description of it
app/Sources/Guidance/   Tier 2: triage, guidance, and the engine that rations calls
app/Sources/Overlay/    The floating card
probe/                  Fixture-driven harness for the prompts
sidecar/                Python MLX sidecar: vision-language model + TTS
tools/render-icon.swift Draws the app icon; run it to regenerate the .appiconset
project.yml             XcodeGen spec; Nota.xcodeproj is generated, not committed
```

Swift owns OS integration because it is the only reasonable way to handle TCC
permissions, ScreenCaptureKit, the Accessibility API and `SpeechAnalyzer`.
Python owns inference because `mlx-vlm` and `mlx-audio` are far ahead of
`mlx-swift` for vision-language and TTS work.

## Requirements

- macOS 26 or later (Apple Foundation Models, `SpeechAnalyzer`)
- Apple Intelligence switched on in System Settings. Being on an eligible Mac is
  not enough; until it is enabled `SystemLanguageModel.availability` reports
  `appleIntelligenceNotEnabled` and the menu-bar item says so
- Apple Silicon; 48 GB unified memory comfortably runs Qwen3.8-27B-4bit
- Xcode 26, XcodeGen (`brew install xcodegen`)
- For the sidecar: uv (`brew install uv`), and about 16 GB of disk for weights

## Install

```sh
./install.sh
```

Builds Release, installs to `/Applications/Nota.app`, and launches it. Safe
to re-run; it quits the running copy first. Once installed it appears in
Spotlight and Launchpad like any other app, and Settings (Cmd-comma) has a
launch-at-login toggle.

`./uninstall.sh` removes it and resets the privacy grants.

The installer deletes the built bundle out of DerivedData once it has been
copied. Spotlight indexes DerivedData on some machines, and a second identical
"Nota" in the launcher is confusing. Only the `.app` is removed, so the next
build relinks rather than recompiling.

## Build for development

```sh
xcodegen generate
xcodebuild -project Nota.xcodeproj -scheme Nota -configuration Debug build
```

Or just open `Nota.xcodeproj`. Note that a Debug build carries the same
bundle ID as the installed copy, so run one or the other, not both.

## Signing, and why it matters here

macOS keys Screen Recording and Accessibility grants to an app's code
signature. Under an ad-hoc signature every rebuild changes that signature and
macOS silently revokes both grants, so you re-approve after every single build.

An Apple Development certificate fixes this. The designated requirement then
binds to the bundle ID and the certificate rather than a binary hash:

```
identifier "dev.nota.Nota" and anchor apple generic and
certificate leaf[subject.CN] = "Apple Development: ..."
```

Rebuilds keep satisfying that, so the grants persist. A free Apple ID is
enough; the paid Developer Program is not needed. Add it in Xcode > Settings >
Accounts, then Manage Certificates > + > Apple Development. Set
`DEVELOPMENT_TEAM` in `project.yml` to the `OU` field of the certificate
subject.

Signing is Manual rather than Automatic on purpose. A macOS app signed for
local development needs no provisioning profile as long as its entitlements
don't require one, and ours don't, which avoids the profile dance entirely.

### If `find-identity` reports zero valid identities

A certificate can exist and still be invalid because its **intermediate** is
missing or expired. Check what is actually wrong:

```sh
security find-identity -p codesigning     # lists it even when invalid
security find-certificate -c "Apple Worldwide Developer Relations Certification Authority" \
  -p | openssl x509 -noout -subject -dates
```

Current certificates are issued by WWDR **G3**. The original WWDR intermediate
expired in February 2023, and if that is the only one in the keychain the chain
cannot be built. Install the current one:

```sh
curl -fsSLO https://www.apple.com/certificateauthority/AppleWWDRCAG3.cer
security add-certificates -k ~/Library/Keychains/login.keychain-db AppleWWDRCAG3.cer
```

After changing how the app is signed, clear the grants tied to the old
signature so the prompts come back cleanly:

```sh
for s in Accessibility ScreenCapture Microphone AppleEvents; do
  tccutil reset $s dev.nota.Nota
done
```

## What keeps the model idle

The readers run on a timer, so nearly every tick describes a screen that has not
meaningfully changed. `GuidanceEngine` applies three rules before anything
reaches a model, and they matter more than the prompts do:

- Reads are flattened into a `ContextBrief` and compared by a fingerprint of the
  text that *would be sent*. A moving mouse or a clock in a window title is not
  an event.
- A brief that differs from the last one re-arms a 1.2 s settle timer, so
  nothing runs while a command is still being typed.
- Triage gates guidance. The longer call only happens after a yes, and the
  in-flight request is cancelled as soon as the screen changes under it.

Triage is also deliberately biased toward silence — a successful command, long
output, an empty cell and a non-blocking warning all have to come back false,
because interrupting someone who is working is worse than staying quiet. The
Context Inspector shows each verdict with its reason and the exact text the
model saw, which is where to look when a verdict seems wrong.

## The sidecar

```sh
brew install uv
sidecar/setup.sh          # virtualenv, MLX, CA bundle, reachability check
sidecar/run.sh            # start it
sidecar/run.sh --stub     # start it with no weights
sidecar/.venv/bin/python sidecar/test_prompt.py
```

`setup.sh` is safe to re-run.

Tier 2 triages and Tier 3 writes, which follows what each is actually good at.
`TieredGuidanceProvider` composes them, and Tier 3 is optional: the sidecar
holds gigabytes of weights in a separate process and will often not be running,
in which case Tier 2 writes the card as before. That is worse advice, not no
advice, and the inspector's "Written by" row says which one answered.

It is an HTTP server on loopback rather than a subprocess the app spawns, for
two reasons. Loading a 27B model takes tens of seconds and Nota is a login
item that gets quit and relaunched, so tying the weights to the app's lifetime
would pay that cost every time. And a crash inside MLX cannot take the menu-bar
app down with it. It binds `127.0.0.1` only: this process receives the contents
of the screen and must never be reachable from the network.

`--stub` answers from the screen text without a model, deriving its reply from
the brief it was given rather than returning a constant, so a wiring bug that
drops the brief still shows up as a wrong answer. That is what makes the whole
path testable before any weights exist.

The parsing is the part worth testing, and `test_prompt.py` covers it without a
model. A local model wraps its JSON in a fence, in prose, or in a `<think>`
block, inconsistently, and formulas and shell snippets put braces inside string
values — which is why `_first_json_object` counts depth rather than matching a
regex.

Two environment problems are worth knowing about, because both present as
something else entirely.

**Python does not use the macOS keychain.** It ships its own CA list via
`certifi`, so on a network that terminates TLS for inspection every HTTPS call
from Python dies with `CERTIFICATE_VERIFY_FAILED: self-signed certificate in
certificate chain` while `curl` and the browser work fine. `setup.sh` appends
the machine's own trusted roots to certifi's bundle and writes
`.venv/nota-ca.pem`; pass it as `SSL_CERT_FILE`. Disabling verification would
also make the error go away and is the wrong trade.

**The weights come from a different host than the API.** `huggingface.co`
serves metadata and small files; the model shards come from `us.aws.cdn.hf.co`
and `cas-server.xethub.hf.co`. A filtering proxy that allows the first and
blocks the rest fails in a thoroughly misleading way: `hf download` reports
`503 Service Unavailable` from the CDN, which reads like an outage at
HuggingFace rather than a local policy, and the returned body is the proxy's own
block page. `setup.sh` range-requests a shard and says so plainly instead.

Once the weights are cached under `~/.cache/huggingface` the sidecar never needs
the network again, so fetching them once on an unfiltered network is enough.

## Two constraints worth knowing early

**The overlay must be excluded from capture.** Screen capture uses
`SCContentFilter(display:excludingWindows:)` with the overlay's window ID.
Without it the model reads its own last suggestion off the screen and feeds it
back to itself.

**The App Sandbox has to stay off.** Accessibility access and sending Apple
events to arbitrary applications are both incompatible with it, which also
rules out Mac App Store distribution.

## Non-goals for v1

Nota does not click, type, or control anything. Guidance only. That keeps it
out of computer-use territory, where a wrong action has real consequences.

A cloud escape hatch for hard questions sits behind a `GuidanceProvider`
protocol so a hosted model can be added later without rearchitecting, but it is
deliberately unimplemented.
