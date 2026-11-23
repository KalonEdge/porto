# Releases and automatic updates

Porto updates itself with [Sparkle 2](https://sparkle-project.org/documentation/): it checks a signed feed once a day, downloads in the background and installs when the app quits. People can turn checks or automatic installs off, or check by hand, in Settings → About. Both the feed and every archive are Ed25519-signed, and the private key never ships in the app or the website.

Local builds need none of this. `./build-app.sh` works without configuration, and Settings shows that updates aren't available in that build.

## One-time setup

```bash
swift package resolve
.build/artifacts/sparkle/Sparkle/bin/generate_keys   # creates the key in your login Keychain, prints the public key
cp release.env.example release.env
```

In `release.env` (gitignored), set:

- `SPARKLE_FEED_URL`: your permanent feed, e.g. `https://porto.example/updates/appcast.xml`
- `SPARKLE_PUBLIC_KEY`: the public key `generate_keys` printed
- `PORTO_REPOSITORY`, `PORTO_WEBSITE`: links for About, feedback and the tip jar (`<website>/tip`)
- `CODE_SIGN_IDENTITY` and `NOTARYTOOL_PROFILE`: your Developer ID Application identity and a profile saved with `xcrun notarytool store-credentials`. In CI, use `NOTARY_API_KEY_PATH`, `NOTARY_API_KEY_ID` and `NOTARY_API_ISSUER_ID` instead, and `SPARKLE_PRIVATE_KEY_FILE` for an exported Sparkle key.

Back up the Sparkle key (`generate_keys -x <file>`). Installed copies only accept updates signed with the key they shipped with.

## Each release

Use a new, higher build number every time:

```bash
./release.sh 1.1 2
```

The script validates the settings (`scripts/configure.py`), builds and signs the app inside out, notarizes and staples it when credentials are set, packages `.build/Porto.dmg`, signs the update archive, checks that signature against the public key embedded in the app (`scripts/verify-update-signature.swift`), and generates the appcast. It publishes nothing. Then, from the repository root:

```bash
mkdir -p web/public/updates
rsync -av --exclude old_updates/ app/.build/updates/ web/public/updates/
cp app/.build/Porto.dmg web/public/Porto.dmg
```

Deploy the archives before (or with) the feed, keep old archive URLs working, and keep `.build/updates` between releases so Sparkle can build delta updates.

## Checks

```bash
python3 scripts/test-configure.py
codesign --verify --deep --strict .build/Porto.app
spctl --assess --verbose=2 .build/Porto.app     # notarized builds: "source=Notarized Developer ID"
```

## Anonymous usage

Copies that share usage (on by default, off in Settings → General) request `https://<feed host>/usage/<feature>` at most once a day per feature, plus `active`. The feed host comes from `SUFeedURL`, so builds without a feed never report. The website's `proxy.ts` answers known features with an empty `204`; count them in your host's request logs.
