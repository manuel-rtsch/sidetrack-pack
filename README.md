# Sidetrack App Pack

## What this is

This is an F-Droid repository that carries [Sidetrack](https://github.com/manuel-rtsch/Sidetrack) for the [Sidephone SP-01](https://www.sidephone.com).

The SP-01's stock **Library** app is upstream F-Droid Basic (`org.fdroid.basic`) with "repository" renamed to "app pack". An app pack is therefore an F-Droid repo. One QR code installs Sidetrack with no unknown-sources prompt and automatic updates, because the Library is a privileged system installer.

> Not affiliated with Sidephone. The same APK is on GitHub Releases for Obtainium or a manual install, and that path stays supported permanently.

| | |
| --- | --- |
| Address | `https://manuel-rtsch.github.io/sidetrack-pack/fdroid/repo` |
| Install page | `https://manuel-rtsch.github.io/sidetrack-pack/` |
| QR image | `/fdroid/repo/index.png` |

`fdroid update` writes the QR image, encoding the address plus `?fingerprint=…`. Nobody draws it by hand.

**Fingerprint (SHA-256):**

```
07E18BC404C077F38C71CE05FD953E0077CBE73687A843FFF3A35B10FAE17488
```

The install page gets this value injected at deploy time from the built index (`scripts/fingerprint.sh`). Derive it again and never retype it.

## Installing

1. On the SP-01, open `Library → Settings → App Packs → +`.
2. Scan the QR code on the install page, or enter the address by hand.
3. Check that the fingerprint the phone shows matches the one above.
4. Install Sidetrack from the Library.

The Library checks every later update against this fingerprint. To confirm it against the live index at any time:

```sh
curl -sO https://manuel-rtsch.github.io/sidetrack-pack/fdroid/repo/entry.jar
keytool -printcert -jarfile entry.jar | grep SHA256
```

## How it works

| Layer | What | Where |
|---|---|---|
| **Source of truth** | signed release APKs | GitHub Releases in `manuel-rtsch/Sidetrack` |
| **Derivation** | `fdroid update` over the fetched APKs | this repo's CI |
| **Serving** | static files | GitHub Pages |

The build is stateless. `repo/` is rebuilt from GitHub Releases on every run and is gitignored, so no APK enters git history and the pack can always be rebuilt by re-running the workflow. Committing APKs made `xarantolus/fdroid` grow without limit until it died in 2022.

### Three releases per run

Each run fetches the last three releases of the app, and `archive_older: 0` keeps all of them in the main index. The reason is stale clients. An F-Droid client downloads an APK by the exact filename in the index it last synced, so a client that has not refreshed since the previous publish still asks for the old filename. If only the newest APK is served, that request returns a 404 and the client shows a bare `ClientRequestException`. Do not trim this back to one version per app.

### Sidetrack specifics

- **One APK per release.** A release carries `Sidetrack-<v>.apk` (universal) and `Sidetrack-<v>-arm64-v8a.apk`. The index cannot hold both for one `versionCode`, so `apps.json` names the asset glob and the pack ships the arm64-v8a build. The SP-01 is arm64, and the download is half the size. The universal APK stays on the GitHub release.
- **The release certificate is the APK's identity.** It stays in Sidetrack's repository secrets and never enters this repo or its CI. Android needs the same key to update an installed app, and `scripts/verify-apk.sh` in Sidetrack pins it.
- **`versionCode` already increases monotonically.** It is derived from `git describe`, so clients order versions correctly.
- **The `.dev` build is never in the pack.** Its application id is `io.github.manuelrtsch.sidetrack.dev`, a different package that the index never sees.

### Why this address

`repo_url` is baked into the signed index, stored by every client that adds the pack and printed into every QR code ever published. Changing the host later is free: point a custom domain at this Pages site. Changing the address strands every printed QR and every installed client. It is fixed from day one, and `verify-index.py` fails the build if `config.yml` and the index disagree.

Cloudflare Pages is ruled out, because its 25 MiB per-asset limit is smaller than Sidetrack's universal APK. If Pages bandwidth becomes a problem, the exit is Cloudflare R2 behind the same address. Mirror the bytes and keep `config.yml`.

A repo cannot delegate APK hosting to GitHub Releases. `PackageVersionV2.file` has no absolute-URL field, and the client joins repo-relative paths and does not follow redirects. The repo must serve the bytes itself.

## Maintaining

### First-time setup

**1. Create the repo.** Name it `manuel-rtsch/sidetrack-pack` and make it public. CI needs **Settings → Pages → Source: GitHub Actions**. Set no CNAME, because the address above is the plain Pages URL.

**2. Generate the index key, once, ever.**

```sh
./scripts/make-index-key.sh
```

The script writes `sidetrack-repo.p12` here (gitignored) and the password to `../sidetrack-pack-secrets/`, so it never appears in terminal scrollback. It refuses to run if a keystore already exists. Follow the steps it prints: password manager, offline backup, then secrets.

The index key's SHA-256 fingerprint is pinned into every QR you publish. **If you lose the key, the pack is dead.** Clients reject a differently signed index, and every user must delete and re-add the pack. The F-Droid client has no key rotation. Before the first publish, starting over costs nothing.

Never use `fdroid update --create-key` in CI. It writes a random password back into `config.yml`.

**3. Repository secrets.** Set these on `manuel-rtsch/sidetrack-pack`:

| Secret | What |
|---|---|
| `SIDETRACK_REPO_KEYSTORE_B64` | `base64 -w0 sidetrack-repo.p12` |
| `KEYSTOREPASS` | keystore password |
| `KEYPASS` | key password (identical, because PKCS12 requires it) |
| `APPS_READ_TOKEN` | optional, only if the Sidetrack repo goes private |

Pipe the values in. Secrets are write-only once set, so a typo stays invisible until a run fails.

```sh
base64 -w0 sidetrack-repo.p12 | tr -d '\n' \
  | gh secret set SIDETRACK_REPO_KEYSTORE_B64 -R manuel-rtsch/sidetrack-pack
gh secret set KEYSTOREPASS -R manuel-rtsch/sidetrack-pack < ../sidetrack-pack-secrets/repo-index-key-password.txt
gh secret set KEYPASS      -R manuel-rtsch/sidetrack-pack < ../sidetrack-pack-secrets/repo-index-key-password.txt
gh secret list -R manuel-rtsch/sidetrack-pack
```

**4. Release-to-pack trigger.** Sidetrack's `release.yml` already ends with a "Notify the app pack" step, documented in `integrations/release-step.yml`. It needs a fine-grained PAT with `contents: write` on `manuel-rtsch/sidetrack-pack` and nothing else. Store it in **Sidetrack** as `APP_PACK_DISPATCH_TOKEN`. Without it, the step warns and the pack still updates on the weekly cron. With it, the pack updates minutes after a release.

The trigger is a step in the release workflow, not a release-triggered workflow. An event produced with `GITHUB_TOKEN` does not start another workflow, so a release-triggered one would never fire for releases cut by CI.

**5. First publish.** Run **Actions → Publish App Pack → Run workflow**. Take the fingerprint from the job summary (`./scripts/fingerprint.sh` prints it too) and put it in this README. The install page fills itself in.

### Publishing after a release

The dispatch from Sidetrack's release workflow does this automatically. To publish by hand:

```sh
gh workflow run "Publish App Pack" -R manuel-rtsch/sidetrack-pack
```

The weekly schedule is the safety net for any release whose dispatch was skipped. A publish always rebuilds from whatever GitHub Releases holds, so re-running it is safe.

### Building locally

You need `fdroidserver` 2.4.x, a **JDK** (a JRE is not enough, because `fdroid update` calls `jar` for the legacy `index-v1.jar`), `apksigner` via `ANDROID_HOME`, an authenticated `gh` and `jq`.

```sh
uv venv --python 3.12 .venv && . .venv/bin/activate && uv pip install fdroidserver==2.4.5
export KEYSTOREPASS=... KEYPASS=...
./scripts/build.sh
```

If the machine has only a JRE, point `JAVA_HOME` at any installed JDK first. Gradle's provisioning cache usually has one, for example `~/.gradle/jdks/eclipse_adoptium-21-amd64-linux.2`.

### Testing on a real SP-01

No publishing is needed. The Library's `networkSecurityConfig` sets `base-config cleartextTrafficPermitted="true"`, so the phone can fetch over plain HTTP from your machine through the USB cable.

```sh
KEYSTOREPASS=... ./scripts/test-on-device.sh
```

The script runs `adb reverse tcp:8777`, serves `repo/` and opens the Library's "Add app pack" screen.

Two things will confuse you:

- After you tap **Add app pack**, the client opens the app list with the repo name pre-filled in the search field and shows "No matching applications available." This is not a failure. Clear the field, or open Sidetrack with `am start ... AppDetailsActivity -e appid io.github.manuelrtsch.sidetrack`.
- Every app shows a placeholder icon in the Library, including Sidephone's own packs. This is device-wide, so do not look for an index bug.

To prove a silent install, uninstall Sidetrack and reinstall it from the pack. Success is `installerPackageName=org.fdroid.basic` with no unknown-sources prompt. Uninstalling wipes app data and resets runtime permissions, so use a scratch phone.

Remove the test pack afterwards via **Library → Settings → App Packs**. `ManageReposActivity` cannot be launched externally, so this step is manual.

### Gotchas

Confirmed on the SideSuite pack.

- An APK with no `metadata/<pkg>.yml` is silently excluded from the index, with only a warning. `verify-index.py` turns that into a failure.
- Secrets syntax in `config.yml` is `{env: VAR}`, not `${VAR}`. But `keystore: {env: ...}` is broken ([fdroidserver#870](https://gitlab.com/fdroid/fdroidserver/-/issues/870)). It stays a literal path, written from the base64 secret at runtime.
- `FDROID_KEY_STORE_PASS` and `FDROID_KEY_PASS` are internal to fdroidserver. It does not read them from the environment.
- `repo_icon` resolves relative to `repo/icons/`, so `icon.png` is copied there before `fdroid update` runs.
- The fingerprint is not in any index JSON file. It lives in the JAR signature block of `entry.jar`, which is exactly what a client verifies.
- `fdroid update` needs `apksigner` from `$ANDROID_HOME/build-tools` to sign `entry.jar`.
