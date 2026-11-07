#!/usr/bin/env python3
"""Generate small, architecture-specific RSS appcasts from verified release assets."""
import argparse
import datetime
import email.utils
import json
from pathlib import Path
import re
import xml.etree.ElementTree as ET

import release

REPOSITORY = 'https://github.com/chenmobuys/Neylu'
SPARKLE = 'http://www.andymatuschak.org/xml-namespaces/sparkle'
NEYLU = REPOSITORY + '/appcast'
ET.register_namespace('sparkle', SPARKLE)
ET.register_namespace('neylu', NEYLU)
LIMIT = 2 * 1024 * 1024


def version_key(value):
    match = re.fullmatch(r'(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(?:-(alpha|beta|rc)\.([1-9][0-9]*))?', value)
    if not match:
        raise ValueError('Invalid appcast version')
    major, minor, patch, channel, number = match.groups()
    return (int(major), int(minor), int(patch), {'alpha': 0, 'beta': 1, 'rc': 2, None: 3}[channel], int(number or 0))


def tag(namespace, name):
    return '{' + namespace + '}' + name


def field(item, name, optional=False):
    matches = item.findall(name)
    if optional and not matches:
        return ''
    if len(matches) != 1 or list(matches[0]):
        raise ValueError('Missing, nested or duplicate appcast field: ' + name)
    return (matches[0].text or '').strip()


def validate_item(item, architecture):
    version = field(item, tag(SPARKLE, 'shortVersionString'))
    key = version_key(version)
    build = field(item, tag(SPARKLE, 'version'))
    if not re.fullmatch(r'[1-9][0-9]*', build) or int(build) > 2**64 - 1:
        raise ValueError('Invalid appcast build counter')
    expected_channel = ('alpha', 'beta', 'rc', '')[key[3]]
    if field(item, tag(SPARKLE, 'channel'), optional=True) != expected_channel:
        raise ValueError('Version/channel mismatch')
    if field(item, tag(SPARKLE, 'minimumSystemVersion')) != '13.0.0':
        raise ValueError('Unexpected minimum macOS version')
    digest = field(item, tag(NEYLU, 'sha256'))
    if not re.fullmatch(r'[a-f0-9]{64}', digest):
        raise ValueError('Invalid SHA-256')
    enclosures = item.findall('enclosure')
    filename = release.asset_name(version, architecture)
    url = f'{REPOSITORY}/releases/download/v{version}/{filename}'
    page = f'{REPOSITORY}/releases/tag/v{version}'
    if len(enclosures) != 1 or field(item, 'link') != page:
        raise ValueError('Invalid appcast enclosure/page')
    enclosure = enclosures[0]
    size = enclosure.get('length', '')
    if (enclosure.get('url') != url or enclosure.get('type') != 'application/x-apple-diskimage'
            or not re.fullmatch(r'[1-9][0-9]*', size) or int(size) > 512 * 1024 * 1024):
        raise ValueError('Invalid installer URL, type or size')
    if len(field(item, 'description').encode('utf-8')) > 65536:
        raise ValueError('Release notes are too large')
    return version, int(build), digest, int(size)


def read_items(data, architecture):
    if not data or len(data) > LIMIT:
        raise ValueError('Empty or oversized appcast')
    xml = data.decode('utf-8')
    if '<!DOCTYPE' in xml.upper() or '<!ENTITY' in xml.upper():
        raise ValueError('Appcast cannot contain a DTD or entities')
    root = ET.fromstring(data)
    channels = root.findall('channel')
    if root.tag != 'rss' or root.get('version') != '2.0' or len(channels) != 1:
        raise ValueError('Invalid RSS appcast')
    items = channels[0].findall('item')
    if not items or len(items) > 128:
        raise ValueError('Invalid appcast item count')
    result = {}
    for item in items:
        version, _, _, _ = validate_item(item, architecture)
        if version in result:
            raise ValueError('Duplicate release in appcast')
        result[version] = item
    return result


def candidate(metadata, assets, build):
    version = metadata.get('tag_name', '')[1:]
    version_key(version)
    if metadata.get('tag_name') != 'v' + version or metadata.get('html_url') != f'{REPOSITORY}/releases/tag/v{version}':
        raise ValueError('Foreign release metadata')
    if metadata.get('draft') or metadata.get('prerelease') != ('-' in version):
        raise ValueError('Release publication/channel mismatch')
    if not re.fullmatch(r'[1-9][0-9]*', build) or int(build) > 2**64 - 1:
        raise ValueError('Invalid build counter')
    release.verify_github_assets(assets, version, release.ARCHITECTURES, metadata)
    result = {}
    for arch in release.ARCHITECTURES:
        name = release.asset_name(version, arch)
        asset = next(a for a in metadata['assets'] if a.get('name') == name)
        url = f'{REPOSITORY}/releases/download/v{version}/{name}'
        if asset.get('browser_download_url') != url:
            raise ValueError('Foreign installer URL')
        item = ET.Element('item')
        ET.SubElement(item, 'title').text = 'Neylu ' + version
        ET.SubElement(item, 'link').text = metadata['html_url']
        ET.SubElement(item, tag(SPARKLE, 'version')).text = build
        ET.SubElement(item, tag(SPARKLE, 'shortVersionString')).text = version
        if '-' in version:
            ET.SubElement(item, tag(SPARKLE, 'channel')).text = version.split('-')[1].split('.')[0]
        ET.SubElement(item, tag(SPARKLE, 'minimumSystemVersion')).text = '13.0.0'
        published = datetime.datetime.fromisoformat(metadata['published_at'].replace('Z', '+00:00'))
        ET.SubElement(item, 'pubDate').text = email.utils.format_datetime(published.astimezone(datetime.timezone.utc), usegmt=True)
        ET.SubElement(item, 'description').text = (metadata.get('body') or '')[:12000]
        ET.SubElement(item, tag(NEYLU, 'sha256')).text = asset['digest'][7:].lower()
        ET.SubElement(item, 'enclosure', url=url, length=str(asset['size']), type='application/x-apple-diskimage')
        validate_item(item, arch)
        result[arch] = item
    return result


def merge(existing, item, architecture):
    entries = read_items(existing, architecture) if existing else {}
    version, build, digest, size = validate_item(item, architecture)
    if version in entries:
        _, old_build, old_digest, old_size = validate_item(entries[version], architecture)
        if (build, digest, size) != (old_build, old_digest, old_size):
            raise ValueError('Refusing same-version installer replacement')
    entries[version] = item
    ordered = sorted(entries, key=version_key, reverse=True)
    # Keep both channels reachable, even after many previews are published.
    keep = set([v for v in ordered if '-' not in v][:10] + [v for v in ordered if '-' in v][:10])
    root = ET.Element('rss', version='2.0')
    channel = ET.SubElement(root, 'channel')
    ET.SubElement(channel, 'title').text = f'Neylu Updates ({architecture})'
    ET.SubElement(channel, 'link').text = REPOSITORY
    ET.SubElement(channel, 'description').text = 'Neylu stable and preview releases'
    for value in ordered:
        if value in keep:
            channel.append(entries[value])
    ET.indent(root, space='  ')
    output = ET.tostring(root, encoding='utf-8', xml_declaration=True) + b'\n'
    read_items(output, architecture)
    return output


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--metadata', type=Path, required=True)
    parser.add_argument('--assets', type=Path, required=True)
    parser.add_argument('--build', required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    items = candidate(json.loads(args.metadata.read_text()), args.assets, args.build)
    args.output.mkdir(parents=True, exist_ok=True)
    for arch, item in items.items():
        path = args.output / f'appcast-{arch}.xml'
        path.write_bytes(merge(path.read_bytes() if path.exists() else None, item, arch))


if __name__ == '__main__':
    main()
