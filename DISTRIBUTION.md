# distribution

how veilist gets to a device: the signing key, the release flow, and what the
two f-droid-compatible stores need. the short version is that an android app's
identity IS its signing key, so everything here exists to make that key stable
and the build that uses it reproducible.

## the signing key

android refuses to update an app when the new apk carries a different signing
key, and both stores pin the key per app. so the release key must be created
once and kept forever: losing it strands every user on their installed version,
and the only way past that is uninstalling - which for veilist destroys the
device's veilid identity, its roster, and the writer keypair for every list.

create it once:

```
scripts/make_release_key.sh
```

that writes `android/veilist-release.jks` and `android/key.properties` (both
gitignored) and prints the certificate fingerprint. back up the keystore and its
password offline before publishing anything signed with it.

`android/app/build.gradle.kts` reads `android/key.properties` locally, or the
`VEILIST_KEYSTORE`, `VEILIST_KEYSTORE_PASSWORD`, `VEILIST_KEY_ALIAS` and
`VEILIST_KEY_PASSWORD` environment variables in ci. with none of them set, a
release build falls back to the debug key - fine for `flutter run --release` on
your own device, never for something published.

for ci, add four repository secrets: `VEILIST_KEYSTORE_BASE64`
(`base64 -w0 android/veilist-release.jks`), `VEILIST_KEYSTORE_PASSWORD`,
`VEILIST_KEY_ALIAS`, `VEILIST_KEY_PASSWORD`. the release workflow decodes the
keystore into the runner's temp dir, builds, asserts the apk is not debug-signed,
and deletes it again.

### history: the releases before this

v0.1.0 and v0.2.0 were built by ci with no signing config, so AGP generated a
throwaway debug key on each runner: v0.1.0 carries `b86a3c0e...`, v0.2.0 carries
`32bc2cd8...`, and neither key exists anywhere anymore. those two releases cannot
update each other, and nothing can update them. the first release with the
persistent key is a clean break - anyone running v0.2.0 has to uninstall (losing
local data) once, and never again.

## versioning

the version lives in `pubspec.yaml` and nowhere else:

```
version: 0.3.0+3000
```

`0.3.0` is the versionName, `3000` the versionCode, following
`major*1000000 + minor*1000 + patch`. it must only ever increase.

releases are built with `--split-per-abi`, and flutter adds an abi offset to the
versionCode of each split apk (+1000 armeabi-v7a, +2000 arm64-v8a, +4000 x86_64),
so the published arm64 apk for 0.3.0 reports **5000**. that is also where the odd
pre-0.3 numbers came from: the build number was the ci run number (5, 6), and the
arm64 splits shipped as 2005 and 2006. 3000 clears both.

the release workflow deliberately does NOT pass `--build-name`/`--build-number`.
anything ci injects cannot be derived from the source, which would make a rebuild
of the same tag produce a different apk - the one thing reproducible builds
cannot tolerate. ci only checks that the tag matches the pubspec version.

## release flow

1. bump `version:` in `pubspec.yaml` and add
   `fastlane/metadata/android/en-US/changelogs/<versionCode>.txt`.
2. commit, then tag `vX.Y.Z` and push the tag.
3. `.github/workflows/release.yml` builds the arm64 apk (signed) and the linux
   x64 tarball, and attaches both to a github release named after the tag.

the apk asset must be built from a clean tree at the tagged commit - both stores
fetch it from the release, and f-droid rebuilds that exact commit.

## izzyondroid

izzyondroid is the f-droid-compatible repo that ships developer-built apks, and
it is the lighter first step. it needs:

- a FOSS license (GPL-3.0 here) and public source.
- **no proprietary components.** this is why the qr scanner decodes in pure dart
  rather than via google's ml kit: the ml kit backend put `libbarhopper_v3.so`
  and its tflite models - closed-source blobs - inside the apk.
- apks attached to tagged github releases, signed with a release key, without
  `android:debuggable` or `android:testOnly`.
- fastlane metadata in the repo (`fastlane/metadata/android/en-US/`): title,
  short and full description, icon, and screenshots. **screenshots are still
  missing** - see the README in the phoneScreenshots directory.
- apk size around 30 MB or less. veilist sits right at that line: the arm64
  release was 31.8 MB before the scanner landed, and `libveilid_flutter.so` is
  most of it. worth measuring at submission time.

submission is an app-request issue on izzyondroid's codeberg (`IzzyOnDroid/repodata`).
their update checker then walks the releases daily and picks up new tags.

## f-droid, with reproducible builds

f-droid builds every app itself from source. with a reproducible build it goes
further: it rebuilds the tagged commit, compares its output against the apk we
published, and - if they match - ships OUR apk, signed with OUR key. that keeps a
single signing identity across every channel, which is the whole point of doing
it this way.

the recipe in `fdroiddata` needs `Binaries:` (where to fetch our apk) and
`AllowedAPKSigningKeys:` (the fingerprint of the key above), plus the build
recipe itself.

what our build already does right:

- toolchains pinned in `mise.toml` (flutter, rust, jdk, android sdk) and the
  veilid dependency pinned to a released tag, so a rebuild uses the same
  compilers.
- the version comes from the source tree, not from ci.
- AGP's `dependenciesInfo` blob is disabled in `android/app/build.gradle.kts`:
  it is a google-signed, opaque section that a rebuilder cannot reproduce.
- no proprietary dependencies to strip.

what still has to be worked out before submitting:

- the rust native library. veilid's core is cross-compiled by cargo during the
  gradle build; rust embeds absolute build paths, so the recipe likely needs
  `--remap-path-prefix` (or an equivalent) to make two machines agree.
- the flutter engine and `libapp.so`: aot snapshots must come out identical from
  the same pinned flutter revision, which is worth verifying by rebuilding the
  same tag twice in different directories and diffing the apks.
- ndk version pinning in the recipe, matching the one ci installs.
- f-droid recommends signing with `apksigner` from build-tools 34 or earlier;
  newer ones changed the signing block in ways their verifier trips over.

a practical way to make progress: build a tag twice locally, in different paths,
and diff the two apks entry by entry (`unzip -l`, then compare each differing
entry). anything that differs is what a rebuilder will trip over too.
