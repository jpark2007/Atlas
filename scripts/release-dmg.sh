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
#   3. export .app                 — Developer ID export from the archive
#   4. codesign --verify + runtime — confirm the .app is signed + hardened
#   5. hdiutil                     — build the DMG (app + /Applications alias)
#   6. notarytool submit --wait    — notarize the DMG  (skippable / resumable)
#   7. stapler + gatekeeper check  — staple the ticket, assess with spctl
#
# Usage:
#   scripts/release-dmg.sh                 full pipeline (needs atlas-notary profile)
#   scripts/release-dmg.sh --skip-notarize stop after the DMG (steps 1–5)
#   scripts/release-dmg.sh --notarize-only dist/Atlas-0.9.0.dmg
#                                          run only steps 6–7 on an existing DMG
#
# Notarization uses the keychain profile named "atlas-notary". Create it once:
#   xcrun notarytool store-credentials atlas-notary \
#     --apple-id <apple-id> --team-id 2WA54D67Y8 --password <app-specific-pw>
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

DIST="$ROOT/dist"
ARCHIVE="$DIST/Atlas.xcarchive"
EXPORT_DIR="$DIST/export"
APP_PATH="$EXPORT_DIR/$APP_NAME"

XCODEGEN="${XCODEGEN:-/opt/homebrew/bin/xcodegen}"

# ── flags ────────────────────────────────────────────────────────────────────
SKIP_NOTARIZE=0
NOTARIZE_ONLY=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-notarize) SKIP_NOTARIZE=1; shift ;;
    --notarize-only) NOTARIZE_ONLY="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
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

# ── notarize + staple (steps 6–7), reused by --notarize-only ─────────────────
notarize_and_staple() {
  local dmg="$1"
  [[ -f "$dmg" ]] || die "DMG not found: $dmg"

  step "6/7  Notarizing $dmg (this can take a few minutes)…"
  if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
    die "notarytool keychain profile '$NOTARY_PROFILE' not found.
     Create it with:  xcrun notarytool store-credentials $NOTARY_PROFILE \\
       --apple-id <apple-id> --team-id $TEAM_ID --password <app-specific-pw>
     Then re-run:     scripts/release-dmg.sh --notarize-only \"$dmg\""
  fi
  xcrun notarytool submit "$dmg" --keychain-profile "$NOTARY_PROFILE" --wait \
    || die "notarization failed — inspect with: xcrun notarytool log <submission-id> --keychain-profile $NOTARY_PROFILE"
  ok "Notarization accepted"

  step "7/7  Stapling + Gatekeeper assessment"
  xcrun stapler staple "$dmg" || die "stapler failed"
  xcrun stapler validate "$dmg" || die "stapler validate failed"
  # Assess the notarized DMG as Gatekeeper will on a clean Mac.
  spctl -a -t open --context context:primary-signature -v "$dmg" \
    || die "spctl assessment rejected the DMG"
  ok "DMG notarized, stapled, and Gatekeeper-approved"
}

# ── resume path: notarize an already-built DMG ───────────────────────────────
if [[ -n "$NOTARIZE_ONLY" ]]; then
  notarize_and_staple "$NOTARIZE_ONLY"
  echo; ok "Done. Ship: $NOTARIZE_ONLY"
  exit 0
fi

VERSION="$(version)"
[[ -n "$VERSION" ]] || die "could not read MARKETING_VERSION from project.yml"
DMG_PATH="$DIST/Atlas-$VERSION.dmg"
mkdir -p "$DIST"

# ── 1. regenerate project ────────────────────────────────────────────────────
step "1/7  xcodegen generate"
[[ -x "$XCODEGEN" ]] || command -v xcodegen >/dev/null || die "xcodegen not found (set XCODEGEN=/path)"
"${XCODEGEN}" generate >/dev/null || die "xcodegen generate failed — fix project.yml"
ok "Project regenerated"

# ── 2. archive ───────────────────────────────────────────────────────────────
step "2/7  xcodebuild archive (Release)"
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
step "3/7  Stage the .app from the archive"
rm -rf "$EXPORT_DIR"
mkdir -p "$EXPORT_DIR"
ARCHIVED_APP="$ARCHIVE/Products/Applications/$APP_NAME"
[[ -d "$ARCHIVED_APP" ]] || die "archived app missing at $ARCHIVED_APP"
cp -R "$ARCHIVED_APP" "$APP_PATH"
[[ -d "$APP_PATH" ]] || die "failed to stage $APP_PATH"
ok "Staged → $APP_PATH"

# ── 4. verify signature + hardened runtime ───────────────────────────────────
step "4/7  codesign verify + hardened runtime"
codesign --verify --deep --strict --verbose=2 "$APP_PATH" || die "codesign --verify failed"
codesign -dv --verbose=4 "$APP_PATH" 2>&1 | tee "$DIST/codesign.txt"
grep -q "flags=.*runtime" "$DIST/codesign.txt" || die "hardened runtime flag missing on $APP_PATH"
grep -q "Authority=Developer ID Application" "$DIST/codesign.txt" || die "not signed by Developer ID Application"
ok "Signature valid, hardened runtime present"

# ── 5. build the DMG ─────────────────────────────────────────────────────────
step "5/7  Build DMG"
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
codesign --force --sign "Developer ID Application" "$DMG_PATH" || die "signing the DMG failed"
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

echo
ok "Release complete → $DMG_PATH ($DMG_SIZE)"
echo "   Publish: copy to landing/downloads/Atlas.dmg and deploy the site."
