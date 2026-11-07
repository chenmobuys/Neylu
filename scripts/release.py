#!/usr/bin/env python3
"""Native DMG packaging, GitHub digest verification, release notes and Homebrew Casks."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
BASE_VERSION = r"[0-9]+\.[0-9]+\.[0-9]+"
VERSION_PATTERN = rf"{BASE_VERSION}(?:-(?:alpha|beta|rc)\.[1-9][0-9]*)?"
ARCHITECTURES = ("arm64", "x86_64")


def validate_tag(tag, version):
    if not re.fullmatch(VERSION_PATTERN, version) or tag != f"v{version}":
        raise ValueError(f"Tag must match VERSION exactly: v{version}")
    return "-" in version


def release_notes(changelog, version):
    match = re.search(rf"^## \[{re.escape(version)}\][^\n]*\n(.*?)(?=^## |\Z)", changelog, re.M | re.S)
    if not match or not match[1].strip():
        raise ValueError(f"Missing changelog entry for {version}")
    notes = match[1].strip() + "\n"
    if "-" in version:
        notes = "> 早期测试版：仅 ad-hoc 签名，未经 Apple 公证；首次打开请参阅 README。\n\n" + notes
    return notes


def asset_name(version, arch):
    if arch not in ARCHITECTURES or not re.fullmatch(VERSION_PATTERN, version):
        raise ValueError("Invalid version or architecture")
    return f"Neylu-{version}-{arch}.dmg"


def sha256_file(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def verify_assets(output, version, architectures):
    entries = list(output.iterdir())
    if any(p.is_symlink() or not p.is_file() for p in entries):
        raise ValueError("Release assets must be regular files, without links or directories")
    allowed = set()
    for arch in architectures:
        image = output / asset_name(version, arch)
        if image.stat().st_size == 0:
            raise ValueError(f"Empty installer: {image.name}")
        allowed.add(image.name)
    actual = {p.name for p in entries}
    if actual != allowed:
        raise ValueError(f"Unexpected or missing release files: {actual ^ allowed}")
    print("Verified DMG installers")


def verify_github_assets(output, version, architectures, metadata):
    verify_assets(output, version, architectures)
    if metadata.get("tag_name") != "v" + version or metadata.get("draft"):
        raise ValueError("GitHub release tag or publication state mismatch")
    assets = metadata.get("assets", [])
    for arch in architectures:
        image = output / asset_name(version, arch)
        matches = [asset for asset in assets if asset.get("name") == image.name]
        if len(matches) != 1:
            raise ValueError(f"Missing or duplicated GitHub installer: {image.name}")
        asset = matches[0]
        if (asset.get("state") != "uploaded" or asset.get("size") != image.stat().st_size
                or asset.get("digest") != "sha256:" + sha256_file(image)):
            raise ValueError(f"GitHub SHA-256 or size mismatch: {image.name}")
    print("Verified GitHub-generated SHA-256 against local installers")


def normalize_minimum(value):
    if not re.fullmatch(r'[0-9]+(?:\.[0-9]+){0,2}', value):
        raise ValueError('Invalid minimum macOS version')
    parts = [int(part) for part in value.split('.')]
    if parts[0] < 12:
        raise ValueError('Neylu requires macOS 12 or later')
    return '.'.join(str(part) for part in (parts + [0, 0])[:3])


def minimum_from_build_script(text):
    matches = re.findall(r'<key>LSMinimumSystemVersion</key>\s*<string>([0-9.]+)</string>', text)
    if not matches:
        raise ValueError('Cannot determine minimum macOS from release build script')
    values = {normalize_minimum(value) for value in matches}
    if len(values) != 1:
        raise ValueError('App and helper minimum macOS versions differ')
    return values.pop()


def cask_text(repository, version, digests, allow_prerelease=False, minimum_system="12.0.0"):
    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repository):
        raise ValueError("Invalid GitHub repository")
    pattern = VERSION_PATTERN if allow_prerelease else BASE_VERSION
    if not re.fullmatch(pattern, version) or set(digests) != set(ARCHITECTURES):
        raise ValueError("Valid version and both architecture checksums required; previews need explicit opt-in")
    if not all(re.fullmatch(r"[a-f0-9]{64}", d) for d in digests.values()):
        raise ValueError("Invalid SHA-256")
    minimum_system = normalize_minimum(minimum_system)
    names = {12: 'monterey', 13: 'ventura', 14: 'sonoma', 15: 'sequoia', 26: 'tahoe'}
    major, minor, patch = map(int, minimum_system.split('.'))
    if major not in names or minor != 0 or patch != 0:
        raise ValueError('Unsupported Homebrew minimum macOS requirement')
    macos = names[major]
    caveats = f'''

  caveats <<~EOS
    Neylu 尚未经 Apple 公证 / Neylu is not notarized by Apple.
    如果首次启动被拦截，确认信任此版本后执行：
    If macOS blocks the first launch and you trust this release, run:
      xattr -dr com.apple.quarantine "#{{appdir}}/Neylu.app"
    然后重新打开 Neylu / Then reopen Neylu.

    也可在“系统设置 → 隐私与安全性”选择“仍要打开”。
    Alternatively, choose Open Anyway in System Settings > Privacy & Security.
    此命令不会自动执行 / This command is not run automatically.
    https://github.com/{repository}#readme
  EOS''' if "-" in version else ""
    return f'''# Generated by Neylu release automation; do not edit manually.
cask "neylu" do
  arch arm: "arm64", intel: "x86_64"

  version "{version}"
  sha256 arm:   "{digests['arm64']}",
         intel: "{digests['x86_64']}"

  url "https://github.com/{repository}/releases/download/v#{{version}}/Neylu-#{{version}}-#{{arch}}.dmg"
  name "Neylu"
  desc "Minimal native menu bar system monitor"
  homepage "https://github.com/{repository}"

  auto_updates true
  depends_on macos: :{macos}

  app "Neylu.app"

  uninstall quit: "io.github.chenmobuys.Neylu"

  zap trash: [
    "~/Library/Application Support/Neylu",
    "~/Library/Preferences/io.github.chenmobuys.Neylu.plist",
  ]{caveats}
end
'''


def check(app, version, arch, require_notarization=True):
    with (app / "Contents/Info.plist").open("rb") as stream:
        info = plistlib.load(stream)
    if info.get("CFBundleShortVersionString") != version.split("-", 1)[0]:
        raise ValueError("Bundle version differs from VERSION")
    if info.get("NeyluReleaseVersion") != version:
        raise ValueError("Bundle release channel differs from VERSION")
    if str(info.get("CFBundleVersion")) != (ROOT / "BUILD_NUMBER").read_text().strip():
        raise ValueError("Bundle build differs from BUILD_NUMBER")
    if info.get("CFBundleIdentifier") != "io.github.chenmobuys.Neylu":
        raise ValueError("Bundle identifier changed unexpectedly")
    subprocess.run(["codesign", "--verify", "--strict", "--deep", str(app)], check=True)
    actual = subprocess.check_output(["lipo", "-archs", str(app / "Contents/MacOS/Neylu")], text=True).strip()
    if actual != arch:
        raise ValueError(f"Unexpected architecture: {actual}; expected {arch}")
    helper = app / "Contents/Helpers/NeyluUpdater"
    if not helper.is_file() or helper.is_symlink():
        raise ValueError("Missing updater helper")
    helper_arch = subprocess.check_output(["lipo", "-archs", str(helper)], text=True).strip()
    if helper_arch != arch:
        raise ValueError(f"Unexpected updater architecture: {helper_arch}; expected {arch}")
    login = app / "Contents/Library/LoginItems/NeyluLoginHelper.app"
    login_info = plistlib.loads((login / "Contents/Info.plist").read_bytes())
    if (login_info.get("CFBundleIdentifier") != "io.github.chenmobuys.Neylu.LoginHelper"
            or login_info.get("LSMinimumSystemVersion") != info.get("LSMinimumSystemVersion")):
        raise ValueError("Invalid login helper identity or minimum macOS")
    login_arch = subprocess.check_output(["lipo", "-archs", str(login / "Contents/MacOS/NeyluLoginHelper")], text=True).strip()
    if login_arch != arch:
        raise ValueError("Unexpected login helper architecture")
    for name in ["AppIcon.icns", "LICENSE", "THIRD_PARTY_NOTICES.md", "ReleaseNotes.md"]:
        if not (app / "Contents/Resources" / name).is_file():
            raise ValueError(f"Missing resource: {name}")
    for language in ["en", "zh-Hans"]:
        catalog = app / f"Contents/Resources/{language}.lproj/Localizable.strings"
        if not catalog.is_file() or catalog.stat().st_size == 0:
            raise ValueError(f"Missing localization resource: {language}")
    if require_notarization and "-" not in version:
        signature = subprocess.run(["codesign", "-d", "--verbose=4", str(app)], capture_output=True, text=True, check=True)
        if "Authority=Developer ID Application:" not in signature.stderr:
            raise ValueError("Stable releases require Developer ID signing and notarization")
        subprocess.run(["xcrun", "stapler", "validate", str(app)], check=True)
        subprocess.run(["spctl", "--assess", "--type", "execute", str(app)], check=True)


def detach_image(mount):
    # Spotlight/Finder can briefly hold our freshly written temporary volume.
    # Retry only EBUSY, never force-eject, and stop after a bounded backoff.
    command = ["hdiutil", "detach", str(mount)]
    for attempt in range(6):
        result = subprocess.run(command, capture_output=True, text=True)
        if result.returncode == 0:
            return
        if result.returncode != 16 or attempt == 5:
            raise subprocess.CalledProcessError(result.returncode, command, output=result.stdout, stderr=result.stderr)
        time.sleep(0.25 * 2**attempt)


def verify_volume_icon(image):
    with tempfile.TemporaryDirectory(prefix="neylu-icon-check-") as temporary:
        mount = Path(temporary) / "mounted"
        mount.mkdir()
        subprocess.run(["hdiutil", "attach", "-readonly", "-nobrowse", "-noautoopen",
                        "-mountpoint", str(mount), str(image)], check=True)
        try:
            icon = mount / ".VolumeIcon.icns"
            if not icon.is_file() or icon.read_bytes() != (mount / "Neylu.app/Contents/Resources/AppIcon.icns").read_bytes():
                raise ValueError("Missing or mismatched DMG volume icon")
            if not icon.samefile(mount / "Neylu.app/Contents/Resources/AppIcon.icns"):
                raise ValueError("DMG icon must share storage with the application icon")
            finder_info = bytes.fromhex(subprocess.check_output(
                ["xattr", "-px", "com.apple.FinderInfo", str(mount)], text=True))
            if len(finder_info) != 32 or not int.from_bytes(finder_info[8:10], "big") & 0x0400:
                raise ValueError("DMG volume is missing its Finder custom-icon flag")
        finally:
            detach_image(mount)
    print("Verified mounted volume icon and Finder custom-icon flag")


def package(app, output, version, arch, require_notarization=True):
    check(app, version, arch, require_notarization=require_notarization)
    output.mkdir(parents=True, exist_ok=True)
    image = output / asset_name(version, arch)
    if image.exists():
        raise ValueError(f"Refusing to overwrite installer: {image}")
    with tempfile.TemporaryDirectory(prefix="neylu-dmg-") as temporary:
        staging = Path(temporary) / "Neylu"
        staging.mkdir()
        subprocess.run(["ditto", str(app), str(staging / "Neylu.app")], check=True)
        (staging / "Applications").symlink_to("/Applications", target_is_directory=True)
        # Finder needs a root-level name; a hard link reuses the App icon storage.
        # Set its metadata while writable, then preserve it in the final read-only DMG.
        writable = Path(temporary) / "installer.dmg"
        mount = Path(temporary) / "mounted"
        mount.mkdir()
        subprocess.run(["hdiutil", "create", "-volname", "Neylu", "-srcfolder", str(staging),
                        "-fs", "HFS+", "-format", "UDRW", str(writable)], check=True)
        subprocess.run(["hdiutil", "attach", "-readwrite", "-nobrowse", "-noautoopen",
                        "-mountpoint", str(mount), str(writable)], check=True)
        try:
            os.link(mount / "Neylu.app/Contents/Resources/AppIcon.icns", mount / ".VolumeIcon.icns")
            subprocess.run(["xcrun", "SetFile", "-a", "C", str(mount)], check=True)
        finally:
            detach_image(mount)
        # Native LZMA DMGs work on macOS 10.15+, below our macOS 12 minimum.
        subprocess.run(["hdiutil", "convert", str(writable), "-format", "ULMO",
                        "-o", str(image)], check=True)
    subprocess.run(["hdiutil", "verify", str(image)], check=True)
    verify_volume_icon(image)
    print(f"Created installer: {image}")


def main():
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="command", required=True)
    for command in ["validate", "notes", "package", "verify-assets", "verify-github-assets", "cask"]:
        child = sub.add_parser(command)
        child.add_argument("--tag", required=True)
        if command in ["package", "verify-assets", "verify-github-assets", "cask"]:
            child.add_argument("--output", type=Path, required=True)
        if command == "notes":
            child.add_argument("--file", type=Path, required=True)
        if command == "package":
            child.add_argument("--app", type=Path, required=True)
            child.add_argument("--ci-build", action="store_true", help="Internal CI artifact; skip distribution notarization requirements")
            child.add_argument("--arch", choices=ARCHITECTURES, required=True)
        if command in ["verify-assets", "verify-github-assets"]:
            child.add_argument("--arch", choices=ARCHITECTURES, action="append")
        if command == "verify-github-assets":
            child.add_argument("--metadata", type=Path, required=True)
        if command == "cask":
            child.add_argument("--repository", required=True)
            child.add_argument("--allow-prerelease", action="store_true", help="Opt into previews in the project-owned tap")
            child.add_argument("--file", type=Path, required=True)
    args = parser.parse_args()
    version = (ROOT / "VERSION").read_text().strip()
    preview = validate_tag(args.tag, version)
    notes = release_notes((ROOT / "CHANGELOG.md").read_text(), version)
    if args.command == "validate":
        print("preview" if preview else "stable")
    elif args.command == "notes":
        args.file.parent.mkdir(parents=True, exist_ok=True)
        args.file.write_text(notes)
    elif args.command == "package":
        package(args.app.resolve(), args.output.resolve(), version, args.arch, require_notarization=not args.ci_build)
    elif args.command == "verify-assets":
        verify_assets(args.output.resolve(), version, args.arch or ARCHITECTURES)
    elif args.command == "verify-github-assets":
        verify_github_assets(args.output.resolve(), version, args.arch or ARCHITECTURES, json.loads(args.metadata.read_text()))
    elif args.command == "cask":
        if preview and not args.allow_prerelease:
            raise ValueError("Use --allow-prerelease for previews in the project-owned tap")
        verify_assets(args.output.resolve(), version, ARCHITECTURES)
        digests = {arch: sha256_file(args.output / asset_name(version, arch)) for arch in ARCHITECTURES}
        args.file.parent.mkdir(parents=True, exist_ok=True)
        args.file.write_text(cask_text(args.repository, version, digests, allow_prerelease=args.allow_prerelease))


if __name__ == "__main__":
    main()
