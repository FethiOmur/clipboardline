#!/bin/bash
# Builds Copyline.app: this fork under its own name, icon, bundle identifier
# and storage folder. The sources keep upstream's internal names so upstream
# changes still merge; the product name is applied to a staged copy here, the
# same way scripts/build-community.sh does it.
#
# Usage: bash scripts/build-copyline.sh [debug|release]
#   COPYLINE_BUNDLE_ID      bundle identifier (default com.fethi.copyline)
#   COPYLINE_SIGN_IDENTITY  codesign identity; default is the first
#                           "Apple Development" identity in the keychain,
#                           or ad-hoc ("-") when there is none.
# A stable signing identity matters: macOS ties the Accessibility grant to it,
# so an ad-hoc build loses the grant on every rebuild.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
CONFIG="${1:-release}"
case "$CONFIG" in debug|release) ;; *) echo "Usage: bash scripts/build-copyline.sh [debug|release]" >&2; exit 2 ;; esac
test -f Sources/Tendedero/main.swift || { echo "Run from a complete source checkout" >&2; exit 1; }
BUNDLE_ID="${COPYLINE_BUNDLE_ID:-com.fethi.copyline}"
OUT="$ROOT/.build/copyline"
APP="$ROOT/build/Copyline.app"
FRAMEWORK="$ROOT/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
mkdir -p "$OUT/Sources" "$OUT/ModuleCache" "$ROOT/build"
if [ -L "$APP" ] || [ -L "$OUT/Sources" ]; then
  echo "Refusing a symbolic-link output" >&2; exit 1
fi
rm -rf "$OUT/Sources"
mkdir -p "$OUT/Sources"
swift package resolve
test -d "$FRAMEWORK" || { echo "The pinned Sparkle framework is missing" >&2; exit 1; }
SDK="${SDKROOT:-$(xcrun --show-sdk-path)}"
ARCH="$(uname -m)"
case "$ARCH" in arm64|x86_64) ;; *) echo "Unsupported build architecture" >&2; exit 1 ;; esac

IDENTITY="${COPYLINE_SIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ]; then
  IDENTITY="$(security find-identity -p codesigning -v 2>/dev/null | sed -n 's/.*"\(Apple Development: [^"]*\)".*/\1/p' | head -1)"
fi
if [ -z "$IDENTITY" ]; then
  IDENTITY="-"
  echo "No Apple Development identity found: signing ad-hoc. Privacy grants will not survive a rebuild." >&2
fi

python3 - "$ROOT" "$OUT" "$BUNDLE_ID" <<'PY'
import pathlib, sys
root, out, bundle_id = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2]), sys.argv[3]
for source in sorted((root / 'Sources/Tendedero').glob('*.swift')):
    text = source.read_text()
    if source.name == 'Inbox.swift':
        previous = '"Tendedero/Screenshots"'
        if text.count(previous) != 1:
            raise SystemExit('Review the storage namespace before building')
        text = text.replace(previous, '"Copyline/Screenshots"')
    text = text.replace('Tendedero', 'Copyline').replace('ClipBoardLine', 'Copyline')
    text = text.replace('"tshirt"', '"square.stack"').replace('"tshirt.fill"', '"square.stack.fill"')
    text = text.replace('"local.clipboardline.recovery"', '"%s.recovery"' % bundle_id)
    (out / 'Sources' / source.name).write_text(text)
PY
OPT=(-O)
if [ "$CONFIG" = debug ]; then OPT=(-Onone -g); fi
swiftc "${OPT[@]}" -swift-version 5 -sdk "$SDK" -target "$ARCH-apple-macosx14.0" \
  -file-prefix-map "$ROOT=." -module-cache-path "$OUT/ModuleCache" \
  -F "$(dirname "$FRAMEWORK")" -framework Sparkle \
  -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
  "$OUT"/Sources/*.swift -o "$OUT/Copyline"

# Refuse to replace anything that is not a previous Copyline build.
if [ -e "$APP" ]; then
  python3 - "$APP" "$BUNDLE_ID" <<'PY'
import pathlib, plistlib, sys
app = pathlib.Path(sys.argv[1])
if app.is_symlink() or not app.is_dir():
    raise SystemExit('The output is not a normal application directory')
info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
if info.get('CFBundleIdentifier') != sys.argv[2]:
    raise SystemExit('Refusing to replace a different application')
PY
fi
STAGE="$OUT/Copyline.app"
rm -rf "$STAGE"
mkdir -p "$STAGE/Contents/MacOS" "$STAGE/Contents/Resources" "$STAGE/Contents/Frameworks"
cp "$OUT/Copyline" "$STAGE/Contents/MacOS/Copyline"
ditto "$FRAMEWORK" "$STAGE/Contents/Frameworks/Sparkle.framework"
cp "$ROOT/.build/artifacts/sparkle/Sparkle/LICENSE" "$STAGE/Contents/Resources/LICENSE-Sparkle.txt"
cp "$ROOT/LICENSE" "$STAGE/Contents/Resources/LICENSE.txt"
for document in THIRD_PARTY_NOTICES.md PRIVACY.md SECURITY.md; do
  if [ -f "$ROOT/$document" ]; then cp "$ROOT/$document" "$STAGE/Contents/Resources/$document"; fi
done

swiftc -sdk "$SDK" -file-prefix-map "$ROOT=." scripts/make-copyline-icon.swift -o "$OUT/make-icon"
"$OUT/make-icon" "$OUT/icon.png"
sips -z 512 512 "$OUT/icon.png" --out "$OUT/icon512.png" >/dev/null
VERSION="$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['version'])" "$ROOT/release-version.json")"
BUILD="$(git -C "$ROOT" rev-list --count HEAD 2>/dev/null || echo 1)"
python3 - "$ROOT" "$OUT" "$STAGE" "$BUNDLE_ID" "$VERSION" "$BUILD" <<'PY'
import pathlib, plistlib, struct, sys
root, out, app = map(pathlib.Path, sys.argv[1:4])
bundle_id, version, build = sys.argv[4:7]
records = []
for kind, path in [(b'ic09', out / 'icon512.png'), (b'ic10', out / 'icon.png')]:
    data = path.read_bytes()
    records.append(kind + struct.pack('>I', len(data) + 8) + data)
body = b''.join(records)
(app / 'Contents/Resources/Copyline.icns').write_bytes(b'icns' + struct.pack('>I', len(body) + 8) + body)
languages = []
for folder in sorted((root / 'Sources/Tendedero/Resources').glob('*.lproj')):
    languages.append(folder.stem)
    destination = app / 'Contents/Resources' / folder.name
    destination.mkdir()
    strings = (folder / 'Localizable.strings').read_text()
    (destination / 'Localizable.strings').write_text(strings.replace('Tendedero', 'Copyline').replace('ClipBoardLine', 'Copyline'))
info = {
    'CFBundleName': 'Copyline', 'CFBundleDisplayName': 'Copyline',
    'CFBundleIdentifier': bundle_id, 'CFBundleExecutable': 'Copyline',
    'CFBundleIconFile': 'Copyline', 'CFBundlePackageType': 'APPL',
    'CFBundleShortVersionString': version, 'CFBundleVersion': build,
    'CFBundleDevelopmentRegion': 'en', 'CFBundleLocalizations': languages,
    'LSMinimumSystemVersion': '14.0', 'LSUIElement': True, 'NSHighResolutionCapable': True,
    # No update feed: this fork is built from source. Upstream's updater
    # paths reject a bundle identifier that is not theirs.
    'SUEnableAutomaticChecks': False, 'SUAutomaticallyUpdate': False, 'SUAllowsAutomaticUpdates': False,
    'UTExportedTypeDeclarations': [{'UTTypeIdentifier': 'local.clipboardline.library-id',
        'UTTypeConformsTo': ['public.data'], 'UTTypeDescription': 'Library item identifier'}],
    'NSDesktopFolderUsageDescription': 'Copyline watches the screenshot folder you choose.',
    'NSDocumentsFolderUsageDescription': 'Copyline watches only image folders you choose.',
    'NSDownloadsFolderUsageDescription': 'Copyline watches only image folders you choose.'
}
(app / 'Contents/Info.plist').write_bytes(plistlib.dumps(info))
PY

EMBEDDED="$STAGE/Contents/Frameworks/Sparkle.framework/Versions/B"
sign() { codesign --force --sign "$IDENTITY" --options 0 --timestamp=none "$@"; }
sign "$EMBEDDED/XPCServices/Installer.xpc"
sign --preserve-metadata=entitlements "$EMBEDDED/XPCServices/Downloader.xpc"
sign "$EMBEDDED/Autoupdate"
sign "$EMBEDDED/Updater.app"
sign "$STAGE/Contents/Frameworks/Sparkle.framework"
sign --identifier "$BUNDLE_ID" "$STAGE"
codesign --verify --deep --strict "$STAGE"
if [ -d "$APP" ]; then rm -rf "$APP"; fi
ditto "$STAGE" "$APP"
codesign --verify --deep --strict "$APP"
echo "Built: $APP"
echo "Copyline $VERSION ($BUILD), $BUNDLE_ID. Not installed or launched."
