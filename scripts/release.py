#!/usr/bin/env python3
"""Release metadata, packaging and Homebrew generation (standard library only)."""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import re
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parents[1]
VERSION_PATTERN = r"[0-9]+\.[0-9]+\.[0-9]+"
TAG_PATTERN = rf"v({VERSION_PATTERN})(-preview\.[1-9][0-9]*)?"


def validate_tag(tag, version):
    match = re.fullmatch(TAG_PATTERN, tag)
    if not match or match[1] != version:
        raise ValueError(f"Tag must be v{version} or v{version}-preview.N")
    return bool(match[2])


def cask_text(repository, version, digest):
    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repository):
        raise ValueError("Invalid GitHub repository")
    if not re.fullmatch(VERSION_PATTERN, version) or not re.fullmatch(r"[a-f0-9]{64}", digest):
        raise ValueError("Invalid version or SHA-256")
    return f'''cask "neylu" do
  version "{version}"
  sha256 "{digest}"

  url "https://github.com/{repository}/releases/download/v#{{version}}/Neylu-#{{version}}-arm64.zip"
  name "Neylu"
  desc "Minimal native menu bar system monitor"
  homepage "https://github.com/{repository}"

  depends_on arch: :arm64
  depends_on macos: ">= :ventura"

  app "Neylu.app"

  uninstall quit: "local.QuietBar"

  zap trash: [
    "~/Library/Application Support/Neylu",
    "~/Library/Preferences/local.QuietBar.plist",
  ]
end
'''


def release_notes(changelog, version):
    match = re.search(rf"^## \[{re.escape(version)}\][^\n]*\n(.*?)(?=^## |\Z)", changelog, re.M | re.S)
    if not match or not match[1].strip():
        raise ValueError(f"Missing changelog entry for {version}")
    return match[1].strip() + "\n"


def check(app, version):
    with (app / "Contents/Info.plist").open("rb") as stream:
        info = plistlib.load(stream)
    if info.get("CFBundleShortVersionString") != version:
        raise ValueError("Bundle version differs from VERSION")
    if str(info.get("CFBundleVersion")) != (ROOT / "BUILD_NUMBER").read_text().strip():
        raise ValueError("Bundle build differs from BUILD_NUMBER")
    if info.get("CFBundleIdentifier") != "local.QuietBar":
        raise ValueError("Bundle identifier changed unexpectedly")
    subprocess.run(["codesign", "--verify", "--strict", str(app)], check=True)
    arch = subprocess.check_output(["lipo", "-archs", str(app / "Contents/MacOS/Neylu")], text=True).strip()
    if arch != "arm64":
        raise ValueError(f"Unexpected architecture: {arch}")
    for name in ["AppIcon.icns", "LICENSE", "THIRD_PARTY_NOTICES.md"]:
        if not (app / "Contents/Resources" / name).is_file():
            raise ValueError(f"Missing resource: {name}")


def package(app, output, repository, tag):
    version = (ROOT / "VERSION").read_text().strip()
    preview = validate_tag(tag, version)
    check(app, version)
    if not preview:
        signature = subprocess.run(["codesign", "-d", "--verbose=4", str(app)],
                                   capture_output=True, text=True, check=True)
        if "Authority=Developer ID Application:" not in signature.stderr:
            raise ValueError("Stable releases require Developer ID signing and notarization")
        subprocess.run(["xcrun", "stapler", "validate", str(app)], check=True)
        subprocess.run(["spctl", "--assess", "--type", "execute", str(app)], check=True)
    output.mkdir(parents=True, exist_ok=True)
    archive = output / f"Neylu-{tag[1:]}-arm64.zip"
    if archive.exists():
        raise ValueError(f"Refusing to overwrite release archive: {archive}")
    subprocess.run(["ditto", "-c", "-k", "--keepParent", "--norsrc", str(app), str(archive)], check=True)
    with zipfile.ZipFile(archive) as stream:
        if stream.testzip() is not None or not all(n.startswith("Neylu.app/") for n in stream.namelist()):
            raise ValueError("Invalid release archive layout")
    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    (output / "SHA256SUMS").write_text(f"{digest}  {archive.name}\n")
    notes = release_notes((ROOT / "CHANGELOG.md").read_text(), version)
    if preview:
        notes = "> 测试构建：仅 ad-hoc 签名，未经 Apple 公证；不用于稳定 Homebrew 渠道。\n\n" + notes
    (output / "release-notes.md").write_text(notes)
    if not preview:
        (output / "neylu.rb").write_text(cask_text(repository, version, digest))
    manifest = {"version": version, "tag": tag, "preview": preview,
                "repository": repository, "asset": archive.name, "sha256": digest}
    (output / "release.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(json.dumps(manifest))


def verify_assets(output, repository, tag):
    version = (ROOT / "VERSION").read_text().strip()
    preview = validate_tag(tag, version)
    manifest = json.loads((output / "release.json").read_text())
    expected = f"Neylu-{tag[1:]}-arm64.zip"
    if (manifest.get("tag"), manifest.get("version"), manifest.get("repository"), manifest.get("preview"), manifest.get("asset")) != (tag, version, repository, preview, expected):
        raise ValueError("Published release metadata does not match requested source")
    digest = hashlib.sha256((output / expected).read_bytes()).hexdigest()
    if manifest.get("sha256") != digest or (output / "SHA256SUMS").read_text() != f"{digest}  {expected}\n":
        raise ValueError("Published archive checksum mismatch")
    if not preview:
        expected_cask = cask_text(repository, version, digest)
        if (output / "neylu.rb").read_text() != expected_cask:
            raise ValueError("Published Cask differs from verified release")
    print("Verified immutable published release assets")


def main():
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="command", required=True)
    validate = sub.add_parser("validate")
    validate.add_argument("--tag", required=True)
    pack = sub.add_parser("package")
    pack.add_argument("--app", type=Path, required=True)
    pack.add_argument("--output", type=Path, required=True)
    pack.add_argument("--repository", required=True)
    pack.add_argument("--tag", required=True)
    verify = sub.add_parser("verify-assets")
    verify.add_argument("--output", type=Path, required=True)
    verify.add_argument("--repository", required=True)
    verify.add_argument("--tag", required=True)
    args = parser.parse_args()
    if args.command == "validate":
        version = (ROOT / "VERSION").read_text().strip()
        print("preview" if validate_tag(args.tag, version) else "stable")
        release_notes((ROOT / "CHANGELOG.md").read_text(), version)
    elif args.command == "verify-assets":
        verify_assets(args.output.resolve(), args.repository, args.tag)
    else:
        package(args.app.resolve(), args.output.resolve(), args.repository, args.tag)


if __name__ == "__main__":
    main()
