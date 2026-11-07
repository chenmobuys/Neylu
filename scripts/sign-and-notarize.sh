#!/bin/bash
set -euo pipefail
# All secrets arrive via environment. Do not enable shell tracing.
app_path="$1"
: "${APPLE_CERTIFICATE_BASE64:?Missing signing certificate}"
: "${APPLE_CERTIFICATE_PASSWORD:?Missing certificate password}"
: "${APPLE_SIGNING_IDENTITY:?Missing Developer ID Application identity}"
: "${APPLE_API_KEY_BASE64:?Missing App Store Connect API key}"
: "${APPLE_API_KEY_ID:?Missing API key ID}"
: "${APPLE_API_ISSUER_ID:?Missing API issuer ID}"
case "$APPLE_SIGNING_IDENTITY" in 'Developer ID Application: '*) ;; *) echo 'Developer ID Application identity required' >&2; exit 1;; esac
private_dir="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/neylu-sign.XXXXXX")"
keychain="$private_dir/signing.keychain-db"
keychain_password="$(openssl rand -hex 32)"
cleanup() { security delete-keychain "$keychain" >/dev/null 2>&1 || true; rm -rf "$private_dir"; }
trap cleanup EXIT
umask 077
printf '%s' "$APPLE_CERTIFICATE_BASE64" | base64 --decode > "$private_dir/certificate.p12"
printf '%s' "$APPLE_API_KEY_BASE64" | base64 --decode > "$private_dir/AuthKey.p8"
security create-keychain -p "$keychain_password" "$keychain"
security set-keychain-settings -lut 21600 "$keychain"
security unlock-keychain -p "$keychain_password" "$keychain"
security import "$private_dir/certificate.p12" -k "$keychain" -P "$APPLE_CERTIFICATE_PASSWORD" -T /usr/bin/codesign >/dev/null
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$keychain_password" "$keychain" >/dev/null
case "$app_path" in
  *.app)
    codesign --force --options runtime --timestamp --keychain "$keychain" --sign "$APPLE_SIGNING_IDENTITY" "$app_path/Contents/Helpers/NeyluUpdater"
    codesign --force --options runtime --timestamp --keychain "$keychain" --sign "$APPLE_SIGNING_IDENTITY" "$app_path"
    ditto -c -k --keepParent --norsrc "$app_path" "$private_dir/notarize.zip"
    submission="$private_dir/notarize.zip"
    ;;
  *.dmg)
    codesign --force --timestamp --keychain "$keychain" --sign "$APPLE_SIGNING_IDENTITY" "$app_path"
    submission="$app_path"
    ;;
  *) echo 'Expected an .app or .dmg' >&2; exit 1 ;;
esac
codesign --verify --strict --verbose=2 "$app_path"
xcrun notarytool submit "$submission" --key "$private_dir/AuthKey.p8" \
  --key-id "$APPLE_API_KEY_ID" --issuer "$APPLE_API_ISSUER_ID" --wait --timeout 30m \
  --output-format json > "$private_dir/notary.json"
python3 - "$private_dir/notary.json" <<'PY'
import json,sys
result=json.load(open(sys.argv[1]))
if result.get('status') != 'Accepted':
    raise SystemExit('Apple notarization failed; submission ID: '+str(result.get('id')))
print('Apple notarization: Accepted')
PY
xcrun stapler staple "$app_path"
xcrun stapler validate "$app_path"
case "$app_path" in
  *.app) spctl --assess --type execute --verbose=2 "$app_path" ;;
  *.dmg) spctl --assess --type open --context context:primary-signature --verbose=2 "$app_path" ;;
esac
