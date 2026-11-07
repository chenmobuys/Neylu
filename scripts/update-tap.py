#!/usr/bin/env python3
"""Apply a verified published release to the independent tap, without downgrades."""
import argparse
from pathlib import Path
import importlib.util
import json
import re

spec = importlib.util.spec_from_file_location('release', Path(__file__).with_name('release.py'))
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)
REPOSITORY = 'chenmobuys/Neylu'


def version_key(version):
    match = re.fullmatch(r'(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(?:-(alpha|beta|rc)\.([1-9][0-9]*))?', version)
    if not match:
        raise ValueError('Invalid release version')
    major, minor, patch, stage, number = match.groups()
    return (int(major), int(minor), int(patch), {'alpha': 0, 'beta': 1, 'rc': 2, None: 3}[stage], int(number or 0))


def candidate(tag, assets, metadata, minimum_system="12.0.0"):
    version = tag.removeprefix('v')
    release.validate_tag(tag, version)
    version_key(version)
    if not metadata.get('published_at'):
        raise ValueError('Release must be published before updating the tap')
    release.verify_github_assets(assets, version, release.ARCHITECTURES, metadata)
    for arch in release.ARCHITECTURES:
        name = release.asset_name(version, arch)
        asset = next(a for a in metadata['assets'] if a['name'] == name)
        expected = f'https://github.com/{REPOSITORY}/releases/download/{tag}/{name}'
        if asset.get('browser_download_url') != expected:
            raise ValueError('Installer must belong to the expected repository and tag')
    digests = {arch: release.sha256_file(assets / release.asset_name(version, arch)) for arch in release.ARCHITECTURES}
    return release.cask_text(REPOSITORY, version, digests, allow_prerelease=True, minimum_system=minimum_system)


def apply(cask, content):
    new_version = re.search(r'^  version "([^"]+)"$', content, re.M)[1]
    if cask.is_symlink():
        raise ValueError('Cask must not be a symlink')
    if cask.exists():
        previous = cask.read_text()
        matches = re.findall(r'^  version "([^"]+)"$', previous, re.M)
        if len(matches) != 1:
            raise ValueError('Cannot safely read the current cask version')
        old_key, new_key = version_key(matches[0]), version_key(new_version)
        if new_key < old_key:
            print('Skipping older release; tap remains unchanged')
            return False
        if new_key == old_key:
            old_sha = re.findall(r'"([a-f0-9]{64})"', previous)
            new_sha = re.findall(r'"([a-f0-9]{64})"', content)
            if len(old_sha) != 2 or old_sha != new_sha:
                raise ValueError('Published same-version checksums changed; refusing replacement')
            old_min = re.findall(r'^  depends_on macos: (.+)$', previous, re.M)
            new_min = re.findall(r'^  depends_on macos: (.+)$', content, re.M)
            if old_min != new_min:
                raise ValueError('Published same-version system requirement changed')
            if previous == content:
                print('Cask is already up to date')
                return False
    cask.parent.mkdir(parents=True, exist_ok=True)
    cask.write_text(content)
    return True


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--tag', required=True)
    parser.add_argument('--assets', type=Path, required=True)
    parser.add_argument('--metadata', type=Path, required=True)
    parser.add_argument('--tap', type=Path, required=True)
    parser.add_argument('--build-script', type=Path)
    args = parser.parse_args()
    minimum = release.minimum_from_build_script(args.build_script.read_text()) if args.build_script else '12.0.0'
    content = candidate(args.tag, args.assets, json.loads(args.metadata.read_text()), minimum)
    if apply(args.tap / 'Casks/neylu.rb', content):
        print('Updated Casks/neylu.rb')


if __name__ == '__main__':
    main()
