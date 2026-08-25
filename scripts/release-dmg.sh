#!/usr/bin/env bash
#
# release-dmg.sh — Developer ID release pipeline for the Atlas direct-download beta.
#
# Produces a signed, notarized, stapled DMG at dist/Atlas-<version>.dmg that
# Gatekeeper accepts on a clean Mac (no App Store, no dev tools installed).
#
# Steps (each fails loudly and can be resumed):
#   1. xcodegen generate           — regenerate Atlas.xcodeproj from project.yml
#   2. xcodebuild archive          — Release archive of the Atlas scheme
#   3. export .app                 — Developer ID export from the archive, then
#                                    deep re-sign Sparkle's nested helpers (3b)
#   4. codesign --verify + runtime — confirm the .app is signed + hardened
#   5. hdiutil                     — build the DMG (app + /Applications alias)
#   6. notarytool submit --wait    — notarize the DMG  (skippable / resumable)
#   7. stapler + gatekeeper check  — staple the ticket, assess with spctl
#   8. sign_update + appcast       — sign the stapled DMG for Sparkle and write the
#                                    landing/appcast.xml entry (skippable / resumable)
#
# Usage:
#   scripts/release-dmg.sh                 full pipeline (needs atlas-notary profile)
#   scripts/release-dmg.sh --skip-notarize stop after the DMG (steps 1–5)
#   scripts/release-dmg.sh --skip-appcast  stop after stapling (steps 1–7)
#   scripts/release-dmg.sh --notarize-only dist/Atlas-0.9.0.dmg
#                                          run only steps 6–8 on an existing DMG
#   scripts/release-dmg.sh --appcast-only  dist/Atlas-0.10.1.dmg
#                                          run only step 8 on an already-stapled DMG
#
# Notarization uses the keychain profile named "atlas-notary". Create it once:
#   xcrun notarytool store-credentials atlas-notary \
#     --apple-id <apple-id> --team-id 2WA54D67Y8 --password <app-specific-pw>
#
# ── ONE-TIME SPARKLE SETUP (do this before the first auto-update release) ─────
# Sparkle signs every update with an ed25519 key that lives in YOUR login keychain.
# This script never generates it — run Sparkle's own tool once:
#
#   generate_keys
#
# It stores the private key in the login keychain and PRINTS the public key. Paste
# that public key into project.yml → targets → Atlas → info → properties →
# SUPublicEDKey (replacing PLACEHOLDER_ED_PUBLIC_KEY), then `xcodegen generate`.
#
# `generate_keys` and `sign_update` both ship with the resolved Swift Package —
# after one build of the Atlas scheme they are at:
#   ~/Library/Developer/Xcode/DerivedData/Atlas-*/SourcePackages/artifacts/sparkle/Sparkle/bin/
# (`brew install --cask sparkle` is the alternative.)
#
# Back the private key up: lose it and existing installs can never be updated again.
#
set -euo pipefail

# ── locations ────────────────────────────────────────────────────────────────
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

PROJECT="Atlas.xcodeproj"
SCHEME="Atlas"
APP_NAME="Atlas.app"
# "Atlas Installer", not "Atlas": once Atlas.app is installed in /Applications,
# macOS App Management (TCC) blocks unprivileged access to /Volumes/Atlas/Atlas.app
# (a recognized install path for com.atlaslm.Atlas), so `hdiutil create` fails
# with "Operation not permitted". Any other volume name avoids the protected path.
VOL_NAME="Atlas Installer"
TEAM_ID="2WA54D67Y8"
NOTARY_PROFILE="atlas-notary"
SIGN_ID="Developer ID Application"
ENTITLEMENTS="Atlas/Atlas-DeveloperID.entitlements"

APPCAST="$ROOT/landing/appcast.xml"
# Where the appcast tells Sparkle to fetch the update from. Versioned on purpose:
# the site's own download button keeps pointing at the stable /downloads/Atlas.dmg,
# but the updater needs a URL whose bytes can never be a stale cached build.
DOWNLOAD_BASE="https://www.atlaslm.net/downloads"

DIST="$ROOT/dist"
ARCHIVE="$DIST/Atlas.xcarchive"
EXPORT_DIR="$DIST/export"
APP_PATH="$EXPORT_DIR/$APP_NAME"

XCODEGEN="${XCODEGEN:-/opt/homebrew/bin/xcodegen}"

# ── flags ────────────────────────────────────────────────────────────────────
SKIP_NOTARIZE=0
SKIP_APPCAST=0
NOTARIZE_ONLY=""
APPCAST_ONLY=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-notarize) SKIP_NOTARIZE=1; shift ;;
    --skip-appcast)  SKIP_APPCAST=1; shift ;;
    --notarize-only) NOTARIZE_ONLY="${2:-}"; shift 2 ;;
    --appcast-only)  APPCAST_ONLY="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,49p' "$0"; exit 0 ;;
    *) echo "error: unknown argument '$1'" >&2; exit 2 ;;
  esac
done

# ── helpers ──────────────────────────────────────────────────────────────────
step()  { printf '\n\033[1;36m▶ %s\033[0m\n' "$*"; }
ok()    { printf '\033[1;32m✓ %s\033[0m\n' "$*"; }
die()   { printf '\033[1;31m✗ %s\033[0m\n' "$*" >&2; exit 1; }

version() {
  # Marketing version from project.yml (single source of truth).
  awk -F'"' '/MARKETING_VERSION:/ {print $2; exit}' "$ROOT/project.yml"
}

# ── Sparkle helpers (step 8) ─────────────────────────────────────────────────

# The public key must be real before we cut a release: with the placeholder still
# in project.yml the shipped app can verify nothing and would reject every update.
require_public_key() {
  local key
  key="$(awk -F'"' '/SUPublicEDKey:/ {print $2; exit}' "$ROOT/project.yml")"
  [[ -n "$key" ]] || die "SUPublicEDKey is missing from project.yml"
  [[ "$key" != "PLACEHOLDER_ED_PUBLIC_KEY" ]] || die "SUPublicEDKey is still PLACEHOLDER_ED_PUBLIC_KEY.
     Sparkle cannot verify updates until a real key is in place. Once:
       generate_keys              # stores the private key in your login keychain
     then paste the printed public key into project.yml (targets → Atlas → info →
     properties → SUPublicEDKey) and re-run:  xcodegen generate
     Cutting a DMG without updates is still fine:  scripts/release-dmg.sh --skip-appcast"
}

# Sparkle's sign_update. The Swift Package artifact ships it (alongside
# generate_keys) under DerivedData, so a resolved checkout usually has it already;
# fall back to PATH and a Homebrew cask install.
find_sign_update() {
  local candidate
  if candidate="$(command -v sign_update 2>/dev/null)"; then
    echo "$candidate"; return 0
  fi
  for candidate in \
    "$HOME"/Library/Developer/Xcode/DerivedData/Atlas-*/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update \
    /opt/homebrew/Caskroom/sparkle/*/bin/sign_update \
    /usr/local/Caskroom/sparkle/*/bin/sign_update
  do
    [[ -x "$candidate" ]] && { echo "$candidate"; return 0; }
  done
  return 1
}

# ── 8. sign the DMG for Sparkle + write the appcast entry ────────────────────
sign_and_appcast() {
  local dmg="$1"
  [[ -f "$dmg" ]] || die "DMG not found: $dmg"
  [[ -f "$APPCAST" ]] || die "appcast not found at $APPCAST"
  require_public_key

  step "8/8  Sparkle signature + appcast entry"

  local tool
  tool="$(find_sign_update)" || die "Sparkle's sign_update not found.
     It normally ships with the resolved Swift Package, at
       ~/Library/Developer/Xcode/DerivedData/Atlas-*/SourcePackages/artifacts/sparkle/Sparkle/bin/
     Build the Atlas scheme once to fetch it, or install the tools separately:
       brew install --cask sparkle
     Then resume with:  scripts/release-dmg.sh --appcast-only \"$dmg\""

  # sign_update prints an attribute fragment, e.g.
  #   sparkle:edSignature="…" length="…"
  local fragment signature
  fragment="$("$tool" "$dmg")" || die "sign_update failed — is the private key in your login keychain? (run generate_keys once)"
  signature="$(printf '%s' "$fragment" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p')"
  [[ -n "$signature" ]] || die "could not read a signature out of sign_update's output: $fragment"
  ok "DMG signed for Sparkle"

  local ver length pubdate url
  ver="$(version)"
  length="$(stat -f%z "$dmg")"
  pubdate="$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')"
  url="$DOWNLOAD_BASE/Atlas-$ver.dmg"

  APPCAST="$APPCAST" VER="$ver" LENGTH="$length" PUBDATE="$pubdate" \
  URL="$url" SIGNATURE="$signature" MIN_OS="$(awk -F'"' '/macOS:/ {print $2; exit}' "$ROOT/project.yml")" \
  python3 - <<'PY' || die "failed to update the appcast"
import os, xml.etree.ElementTree as ET

SPARKLE = "http://www.andymatuschak.org/xml-namespaces/sparkle"
ET.register_namespace("sparkle", SPARKLE)
path = os.environ["APPCAST"]
ver  = os.environ["VER"]

# insert_comments keeps the file's "don't hand-edit this" header through a rewrite.
tree = ET.parse(path, ET.XMLParser(target=ET.TreeBuilder(insert_comments=True)))
channel = tree.getroot().find("channel")

def sp(tag): return f"{{{SPARKLE}}}{tag}"

# Re-running a release rewrites that version's entry rather than duplicating it.
for old in [i for i in channel.findall("item")
            if (i.findtext(sp("shortVersionString")) or i.findtext("title")) == ver]:
    channel.remove(old)

# Newest first: sit ahead of the existing items.
existing = channel.findall("item")
position = list(channel).index(existing[0]) if existing else len(list(channel))
item = ET.Element("item")
channel.insert(position, item)

def child(tag, text):
    ET.SubElement(item, tag).text = text

child("title", ver)
child("pubDate", os.environ["PUBDATE"])
child(sp("version"), ver)
child(sp("shortVersionString"), ver)
child(sp("minimumSystemVersion"), os.environ["MIN_OS"] or "14.0")
ET.SubElement(item, "enclosure", {
    "url": os.environ["URL"],
    "length": os.environ["LENGTH"],
    "type": "application/x-apple-diskimage",
    sp("edSignature"): os.environ["SIGNATURE"],
})

ET.indent(tree, space="  ")
tree.write(path, encoding="utf-8", xml_declaration=True)
PY
  ok "Appcast updated → $APPCAST (version $ver, $length bytes)"

  echo
  printf '\033[1mPublish this release:\033[0m\n'
  echo "   1. cp \"$dmg\" landing/downloads/Atlas-$ver.dmg   # the URL Sparkle fetches"
  echo "   2. cp \"$dmg\" landing/downloads/Atlas.dmg         # the site's download button"
  echo "   3. commit landing/appcast.xml and deploy the site"
  echo "   Sparkle only sees the release once $url and"
  echo "   https://www.atlaslm.net/appcast.xml are both live."
}

# ── notarize + staple (steps 6–7), reused by --notarize-only ─────────────────
notarize_and_staple() {
  local dmg="$1"
  [[ -f "$dmg" ]] || die "DMG not found: $dmg"

  step "6/8  Notarizing $dmg (this can take a few minutes)…"
  if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
    die "notarytool keychain profile '$NOTARY_PROFILE' not found.
     Create it with:  xcrun notarytool store-credentials $NOTARY_PROFILE \\
       --apple-id <apple-id> --team-id $TEAM_ID --password <app-specific-pw>
     Then re-run:     scripts/release-dmg.sh --notarize-only \"$dmg\""
  fi
  # notarytool exits 0 even when the submission comes back Invalid, so the real
  # status has to be read out of its output (0.10.1 printed "✓ accepted" over an
  # Invalid result).
  local notary_out status submission_id
  notary_out="$(xcrun notarytool submit "$dmg" --keychain-profile "$NOTARY_PROFILE" --wait 2>&1)" || true
  printf '%s\n' "$notary_out"
  submission_id="$(printf '%s\n' "$notary_out" | sed -n 's/^ *id: *\([0-9a-f-]*\).*/\1/p' | head -1)"
  status="$(printf '%s\n' "$notary_out" | sed -n 's/^ *status: *//p' | tail -1)"
  [[ -n "$status" ]] || die "could not read a status out of notarytool's output — treat this as a failure.
     Inspect with: xcrun notarytool log ${submission_id:-<submission-id>} --keychain-profile $NOTARY_PROFILE"
  [[ "$status" == "Accepted" ]] || die "notarization returned status '$status' (not Accepted).
     Inspect with: xcrun notarytool log ${submission_id:-<submission-id>} --keychain-profile $NOTARY_PROFILE"
  ok "Notarization accepted"

  step "7/8  Stapling + Gatekeeper assessment"
  xcrun stapler staple "$dmg" || die "stapler failed"
  xcrun stapler validate "$dmg" || die "stapler validate failed"
  # Assess the notarized DMG as Gatekeeper will on a clean Mac.
  spctl -a -t open --context context:primary-signature -v "$dmg" \
    || die "spctl assessment rejected the DMG"
  ok "DMG notarized, stapled, and Gatekeeper-approved"
}

# ── resume path: sign + appcast an already-stapled DMG ───────────────────────
if [[ -n "$APPCAST_ONLY" ]]; then
  sign_and_appcast "$APPCAST_ONLY"
  echo; ok "Done. Ship: $APPCAST_ONLY"
  exit 0
fi

# ── resume path: notarize an already-built DMG ───────────────────────────────
if [[ -n "$NOTARIZE_ONLY" ]]; then
  notarize_and_staple "$NOTARIZE_ONLY"
  if [[ "$SKIP_APPCAST" -eq 1 ]]; then
    echo; ok "Stopped before the appcast (--skip-appcast)."
    echo "   Finish later with:  scripts/release-dmg.sh --appcast-only \"$NOTARIZE_ONLY\""
  else
    sign_and_appcast "$NOTARIZE_ONLY"
  fi
  echo; ok "Done. Ship: $NOTARIZE_ONLY"
  exit 0
fi

VERSION="$(version)"
[[ -n "$VERSION" ]] || die "could not read MARKETING_VERSION from project.yml"
DMG_PATH="$DIST/Atlas-$VERSION.dmg"
mkdir -p "$DIST"

# Catch a placeholder signing key NOW rather than after a long archive+notarize.
[[ "$SKIP_APPCAST" -eq 1 ]] || require_public_key

# ── 1. regenerate project ────────────────────────────────────────────────────
step "1/8  xcodegen generate"
[[ -x "$XCODEGEN" ]] || command -v xcodegen >/dev/null || die "xcodegen not found (set XCODEGEN=/path)"
"${XCODEGEN}" generate >/dev/null || die "xcodegen generate failed — fix project.yml"
ok "Project regenerated"

# ── 2. archive ───────────────────────────────────────────────────────────────
step "2/8  xcodebuild archive (Release)"
rm -rf "$ARCHIVE"
# NOTE: The Release config signs against Atlas/Atlas-DeveloperID.entitlements,
# which omits com.apple.developer.applesignin (Apple does not allow Sign In with
# Apple in Developer ID builds). With no SIWA entitlement, Developer ID needs NO
# provisioning profile — manual signing with the "Developer ID Application" cert
# is sufficient. -allowProvisioningUpdates is kept as a harmless fallback.
xcodebuild archive \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$ARCHIVE" \
  -allowProvisioningUpdates \
  | tail -20
[[ -d "$ARCHIVE" ]] || die "archive failed — check the Developer ID Application cert is in the login keychain"
ok "Archived → $ARCHIVE"

# ── 3. take the .app straight from the archive ───────────────────────────────
# We copy directly from the archive rather than `xcodebuild -exportArchive`.
# The archived .app is already Developer ID signed with the hardened runtime
# (Xcode signs during archive using the Release config). exportArchive would
# re-sign against a provisioning profile. Direct copy keeps the exact bytes that
# were signed and notarizes fine. See release notes / task report.
step "3/8  Stage the .app from the archive"
rm -rf "$EXPORT_DIR"
mkdir -p "$EXPORT_DIR"
ARCHIVED_APP="$ARCHIVE/Products/Applications/$APP_NAME"
[[ -d "$ARCHIVED_APP" ]] || die "archived app missing at $ARCHIVED_APP"
cp -R "$ARCHIVED_APP" "$APP_PATH"
[[ -d "$APP_PATH" ]] || die "failed to stage $APP_PATH"
ok "Staged → $APP_PATH"

# ── 3b. deep re-sign Sparkle's nested helpers ────────────────────────────────
# Xcode signs the app and the Sparkle framework binary, but leaves the helpers
# embedded in the SPM-built Sparkle.framework ad-hoc signed. Notarization then
# rejects the whole DMG: "not signed with a valid Developer ID certificate" +
# "signature does not include a secure timestamp" for Autoupdate, Updater.app
# and the XPC services. Re-sign them here, inside-out — each nested seal must be
# final before the enclosing bundle is sealed over it.
#
# No --entitlements on the helpers: Atlas is not sandboxed, so Sparkle's helpers
# need none, and the ad-hoc com.apple.application-identifier Sparkle ships on
# Autoupdate would not match our team prefix.
step "3b/8  Re-sign Sparkle's nested helpers (Developer ID + timestamp)"
SPARKLE_VERSION_DIR="$APP_PATH/Contents/Frameworks/Sparkle.framework/Versions/B"
if [[ -d "$SPARKLE_VERSION_DIR" ]]; then
  sign_nested() {
    codesign --force --options runtime --timestamp --sign "$SIGN_ID" "$1" \
      || die "failed to re-sign $1"
    echo "   signed $(basename "$1")"
  }
  # innermost first
  for xpc in "$SPARKLE_VERSION_DIR"/XPCServices/*.xpc; do
    if [[ -d "$xpc" ]]; then sign_nested "$xpc"; fi
  done
  if [[ -f "$SPARKLE_VERSION_DIR/Autoupdate" ]];  then sign_nested "$SPARKLE_VERSION_DIR/Autoupdate"; fi
  if [[ -d "$SPARKLE_VERSION_DIR/Updater.app" ]]; then sign_nested "$SPARKLE_VERSION_DIR/Updater.app"; fi
  # then the framework itself (sign the versioned directory, per Apple's rule for
  # versioned bundles), which re-seals over the helpers above
  sign_nested "$SPARKLE_VERSION_DIR"
  # …and finally the app, whose seal the nested re-signing just invalidated.
  codesign --force --options runtime --timestamp \
    --entitlements "$ROOT/$ENTITLEMENTS" \
    --sign "$SIGN_ID" "$APP_PATH" || die "failed to re-sign $APP_PATH"
  ok "Sparkle helpers + Atlas.app re-signed"
else
  ok "No Sparkle.framework embedded — nothing to re-sign"
fi

# ── 4. verify signature + hardened runtime ───────────────────────────────────
step "4/8  codesign verify + hardened runtime"
codesign --verify --deep --strict --verbose=2 "$APP_PATH" || die "codesign --verify failed"
codesign -dv --verbose=4 "$APP_PATH" 2>&1 | tee "$DIST/codesign.txt"
grep -q "flags=.*runtime" "$DIST/codesign.txt" || die "hardened runtime flag missing on $APP_PATH"
grep -q "Authority=Developer ID Application" "$DIST/codesign.txt" || die "not signed by Developer ID Application"
ok "Signature valid, hardened runtime present"

# ── 5. build the DMG ─────────────────────────────────────────────────────────
step "5/8  Build DMG"
STAGE="$(mktemp -d)"
cp -R "$APP_PATH" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG_PATH"
hdiutil create \
  -volname "$VOL_NAME" \
  -srcfolder "$STAGE" \
  -ov -format UDZO \
  "$DMG_PATH" >/dev/null
rm -rf "$STAGE"
[[ -f "$DMG_PATH" ]] || die "DMG not created"
# The DMG itself must also carry the Developer ID signature.
codesign --force --timestamp --sign "$SIGN_ID" "$DMG_PATH" || die "signing the DMG failed"
codesign --verify --verbose=2 "$DMG_PATH" || die "DMG signature verify failed"
DMG_SIZE="$(du -h "$DMG_PATH" | cut -f1 | tr -d ' ')"
ok "DMG built + signed → $DMG_PATH ($DMG_SIZE)"

# ── 6–7. notarize + staple ───────────────────────────────────────────────────
if [[ "$SKIP_NOTARIZE" -eq 1 ]]; then
  echo
  ok "Stopped before notarization (--skip-notarize)."
  echo "   Finish later with:  scripts/release-dmg.sh --notarize-only \"$DMG_PATH\""
  exit 0
fi

notarize_and_staple "$DMG_PATH"

# ── 8. Sparkle signature + appcast ───────────────────────────────────────────
if [[ "$SKIP_APPCAST" -eq 1 ]]; then
  echo
  ok "Stopped before the appcast (--skip-appcast)."
  echo "   Finish later with:  scripts/release-dmg.sh --appcast-only \"$DMG_PATH\""
  echo
  ok "Release complete → $DMG_PATH ($DMG_SIZE)"
  echo "   Publish: copy to landing/downloads/Atlas.dmg and deploy the site."
  exit 0
fi

sign_and_appcast "$DMG_PATH"

echo
ok "Release complete → $DMG_PATH ($DMG_SIZE)"
