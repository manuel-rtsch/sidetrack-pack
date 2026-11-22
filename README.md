# Sidetrack App Pack

An **F-Droid repository** carrying [Sidetrack](https://github.com/manuel-rtsch/Sidetrack)
for the [Sidephone SP-01](https://www.sidephone.com).

The SP-01's stock **Library** app is upstream F-Droid Basic (`org.fdroid.basic`)
with "repository" renamed to "app pack". So an App Pack *is* an F-Droid repo, and
one QR code installs Sidetrack — with **no unknown-sources prompt and automatic
updates**, because the Library is a privileged system installer.

> Not affiliated with Sidephone. The same APK is published on GitHub Releases
> for Obtainium or a manual install; that path is supported permanently and is
> not a fallback.

**Address:** `https://manuel-rtsch.github.io/sidetrack-pack/fdroid/repo`

**Install QR:** `https://manuel-rtsch.github.io/sidetrack-pack/` (the generated
QR lives at `/fdroid/repo/index.png`; `fdroid update` writes it, encoding the
address plus `?fingerprint=…`, so it is never drawn by hand)

**Fingerprint (SHA-256):** _not published yet — it appears here and on the
install page once the first publish has run. Generate it with
`./scripts/fingerprint.sh`; never type it from anywhere else. The publish
workflow injects it into `web/index.html` from the built index, so the page
cannot disagree with what a client pins._

The Library shows this as it adds the pack, and checks every update against it
afterwards without asking. Confirm it against the live index at any time:

```sh
curl -sO https://manuel-rtsch.github.io/sidetrack-pack/fdroid/repo/entry.jar
keytool -printcert -jarfile entry.jar | grep SHA256
```

---

## How it works

Three layers, deliberately separate:

| Layer | What | Where |
|---|---|---|
| **Source of truth** | signed release APKs | GitHub Releases in `manuel-rtsch/Sidetrack` |
| **Derivation** | `fdroid update` over the fetched APKs | this repo's CI |
| **Serving** | static files | GitHub Pages |

The build is **stateless**. `repo/` is rebuilt from GitHub Releases on every run
and is `.gitignore`d — no APKs ever enter git history. The pack must always be
reconstructible from scratch by re-running the workflow. Committing APKs is what
grew `xarantolus/fdroid` unboundedly before it died in 2022.

Each run fetches the **last three releases** per app, not just the newest, and
`archive_older: 0` keeps all of them in the main index. This is not for history
— it is what keeps stale clients working. An F-Droid client downloads an APK by
the exact filename in the index it last synced, so a client that has not
refreshed since the previous publish still asks for the old filename. Serving
only the newest APK makes that request 404 and the client surfaces a bare
`ClientRequestException`. Do not trim this back to one version per app.

### Sidetrack specifics

- **One APK per release, chosen here.** A Sidetrack release carries both
  `Sidetrack-<v>.apk` (universal) and `Sidetrack-<v>-arm64-v8a.apk`. The index
  cannot hold both for one `versionCode`, so `apps.json` names the asset glob and
  the pack ships the **arm64-v8a** build: the SP-01 is arm64, the pack is not for
  emulators, and it halves the download and the Pages egress. The universal APK
  stays on the GitHub release for everyone else.
- **The release certificate is the APK's identity.** It stays in Sidetrack's
  repository secrets; it never enters this repo or its CI. Android requires the
  same key to update an installed app, and `scripts/verify-apk.sh` there pins it.
- **`versionCode` is monotonic already** (derived from `git describe`), so F-Droid
  clients order versions correctly with no extra work.
- **The `.dev` build is never in the pack.** Its application id is
  `io.github.manuelrtsch.sidetrack.dev`, a different package the index never sees.

### Why this address

`repo_url` is baked into the signed index, stored by every client that adds the
pack, and printed into **every QR code ever published**. Changing the *host*
later is free: point a custom domain at this Pages site and nothing else changes.
Changing the *address* strands every printed QR and every installed client, so
it is fixed from day one and `verify-index.py` fails the build if `config.yml`
and the built index disagree.

Cloudflare Pages is ruled out as a host: its 25 MiB per-asset limit is smaller
than Sidetrack's universal APK. If Pages bandwidth ever becomes a problem, the
exit is Cloudflare R2 behind the same address — mirror the bytes, keep
`config.yml`, and no client notices.

A repo **cannot** delegate APK hosting to GitHub Releases. `PackageVersionV2.file`
has no absolute-URL field, the client concatenates repo-relative paths, and it
does not follow redirects. The repo must serve the bytes itself.

---

# Maintaining the pack

Everything below is for whoever runs this repo.

## First-time setup

**1. Create the repo.** `manuel-rtsch/sidetrack-pack`, public. CI needs
**Settings → Pages → Source: GitHub Actions**. No CNAME: the address above is
the plain Pages URL.

**2. Generate the index key, once, ever.**

```sh
./scripts/make-index-key.sh
```

It writes `sidetrack-repo.p12` here (gitignored) and the password to
`../sidetrack-pack-secrets/`, rather than echoing it into a terminal scrollback.
It refuses to run if a keystore already exists. Follow the steps it prints:
password manager first, offline backup second, secrets third.

The index key's SHA-256 fingerprint is pinned into every QR you publish. **Lose
it and the pack is dead** — clients reject a differently-signed index and every
user must delete and re-add the pack. There is no rotation story in the F-Droid
client. Before the first publish, starting over is free.

Never use `fdroid update --create-key` in CI — it generates a random password and
writes it back into `config.yml`.

**3. Repository secrets** on `manuel-rtsch/sidetrack-pack`:

| Secret | What |
|---|---|
| `SIDETRACK_REPO_KEYSTORE_B64` | `base64 -w0 sidetrack-repo.p12` |
| `KEYSTOREPASS` | keystore password |
| `KEYPASS` | key password (identical — PKCS12 requires it) |
| `APPS_READ_TOKEN` | *optional*, only if the Sidetrack repo goes private |

Pipe values in; secrets are write-only once set, so a typo is invisible until a
run fails.

```sh
base64 -w0 sidetrack-repo.p12 | tr -d '\n' \
  | gh secret set SIDETRACK_REPO_KEYSTORE_B64 -R manuel-rtsch/sidetrack-pack
gh secret set KEYSTOREPASS -R manuel-rtsch/sidetrack-pack < ../sidetrack-pack-secrets/repo-index-key-password.txt
gh secret set KEYPASS      -R manuel-rtsch/sidetrack-pack < ../sidetrack-pack-secrets/repo-index-key-password.txt
gh secret list -R manuel-rtsch/sidetrack-pack
```

**4. Release → pack trigger.** Copy `integrations/notify-app-pack.yml` to
`.github/workflows/notify-app-pack.yml` in `manuel-rtsch/Sidetrack`, then create a
fine-grained PAT with `contents: write` on `manuel-rtsch/sidetrack-pack` and
store it there as `APP_PACK_DISPATCH_TOKEN`. Without it the pack still updates
on the weekly cron; with it, minutes after a release.

**5. First publish.** Actions → **Publish App Pack** → Run workflow. Then take
the fingerprint from the job summary (`./scripts/fingerprint.sh` prints the same
value) and put it in this README. The site page is filled in automatically.

## Publishing after a release

Automatic via the dispatch. Manual:

```sh
gh workflow run "Publish App Pack" -R manuel-rtsch/sidetrack-pack
```

The weekly schedule is the safety net.

## Building locally

Requires `fdroidserver` 2.4.x, a **JDK** (not just a JRE — `fdroid update` shells
out to `jar` for the legacy `index-v1.jar`), `apksigner` via `ANDROID_HOME`, plus
an authenticated `gh` and `jq`.

```sh
uv venv --python 3.12 .venv && . .venv/bin/activate && uv pip install fdroidserver==2.4.5
export KEYSTOREPASS=... KEYPASS=...
./scripts/build.sh
```

If the machine has only a JRE, point `JAVA_HOME` at any installed JDK first; on
this machine Gradle's provisioning cache has one at
`~/.gradle/jdks/eclipse_adoptium-21-amd64-linux.2`.

## Testing on a real SP-01 — no publishing needed

The Library's `networkSecurityConfig` sets
`base-config cleartextTrafficPermitted="true"`, so the phone can fetch over plain
HTTP from this machine through the USB cable:

```sh
KEYSTOREPASS=... ./scripts/test-on-device.sh
```

That does `adb reverse tcp:8777`, serves `repo/` locally, and opens the Library's
"Add app pack" screen pointed at it.

Two things that will confuse you:

- After tapping **Add app pack**, the client opens the app list with the repo
  name pre-filled in the **search field**, showing *"No matching applications
  available."* This is not a failure. Clear the field, or open Sidetrack directly
  with `am start ... AppDetailsActivity -e appid io.github.manuelrtsch.sidetrack`.
- **Every** app renders a placeholder icon in the Library, including Sidephone's
  own packs. Device-wide behaviour — do not go hunting for an index bug.

To prove silent install, uninstall Sidetrack first and reinstall from the pack.
Success is `installerPackageName=org.fdroid.basic` with no unknown-sources
prompt. Uninstalling wipes app data and resets runtime permissions, so use a
scratch phone or accept the data loss.

Remove the test pack afterwards via **Library → Settings → App Packs**;
`ManageReposActivity` is not externally launchable, so this is a manual step.

## Gotchas, all confirmed on the SideSuite pack

- An APK with **no `metadata/<pkg>.yml` is silently excluded** from the index —
  warning only. `verify-index.py` turns that into a failure.
- Secrets syntax in `config.yml` is `{env: VAR}`, not `${VAR}`. But
  `keystore: {env: ...}` is **broken**
  ([fdroidserver#870](https://gitlab.com/fdroid/fdroidserver/-/issues/870)) — it
  stays a literal path, written from the base64 secret at runtime.
- `FDROID_KEY_STORE_PASS` / `FDROID_KEY_PASS` are internal to fdroidserver and
  are **not** read from the environment.
- `repo_icon` resolves relative to `repo/icons/`, so `icon.png` is copied there
  before `fdroid update` runs.
- The fingerprint is **not** in any index JSON file. It lives in the JAR
  signature block of `entry.jar` — which is exactly what a client verifies.
- `fdroid update` needs `apksigner` from `$ANDROID_HOME/build-tools` to sign
  `entry.jar`.
