#!/usr/bin/env python3
"""Publish appcasts to the updates branch without changing source or release assets."""
import argparse
import base64
import json
import os
from pathlib import Path
import urllib.error
import urllib.request

import appcast

REPOSITORY = 'chenmobuys/Neylu'


class GitHub:
    def __init__(self, token):
        if not token:
            raise ValueError('GH_TOKEN is required')
        self.token = token

    def __call__(self, method, path, payload=None):
        request = urllib.request.Request('https://api.github.com/repos/' + REPOSITORY + '/' + path,
            data=json.dumps(payload).encode() if payload is not None else None, method=method,
            headers={'Authorization': 'Bearer ' + self.token, 'Accept': 'application/vnd.github+json',
                     'X-GitHub-Api-Version': '2022-11-28', 'User-Agent': 'Neylu-Appcast-Publisher', 'Content-Type': 'application/json'})
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                return json.load(response)
        except urllib.error.HTTPError as error:
            if method == 'GET' and error.code == 404:
                return None
            raise RuntimeError(f'GitHub appcast publication failed: HTTP {error.code}') from None


def publish(api, items):
    ref = api('GET', 'git/ref/heads/updates')
    parent = ref['object']['sha'] if ref else None
    base_tree = api('GET', 'git/commits/' + parent)['tree']['sha'] if parent else None
    files = {}
    changed = False
    for arch, item in items.items():
        name = f'appcast-{arch}.xml'
        previous = api('GET', 'contents/' + name + '?ref=' + parent) if parent else None
        if parent and not previous:
            raise ValueError('Existing update branch is missing an architecture feed')
        if previous:
            if previous.get('type') != 'file' or previous.get('size', appcast.LIMIT + 1) > appcast.LIMIT:
                raise ValueError('Invalid existing feed file')
            old = base64.b64decode(previous['content'])
        else:
            old = None
        files[name] = appcast.merge(old, item, arch)
        changed = changed or files[name] != old
    if not changed:
        print('Appcast is already up to date')
        return parent
    tree_payload = {'tree': [{'path': name, 'mode': '100644', 'type': 'blob', 'content': data.decode('utf-8')}
                             for name, data in files.items()]}
    if base_tree:
        tree_payload['base_tree'] = base_tree
    tree = api('POST', 'git/trees', tree_payload)
    commit = api('POST', 'git/commits', {'message': 'chore: 更新 Neylu 静态 appcast', 'tree': tree['sha'],
                                       'parents': [parent] if parent else []})
    if parent:
        api('PATCH', 'git/refs/heads/updates', {'sha': commit['sha'], 'force': False})
    else:
        api('POST', 'git/refs', {'ref': 'refs/heads/updates', 'sha': commit['sha']})
    print('Published static appcasts: ' + commit['sha'])
    return commit['sha']


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--metadata', type=Path, required=True)
    parser.add_argument('--assets', type=Path)
    parser.add_argument('--build')
    parser.add_argument('--build-script', type=Path)
    parser.add_argument('--fetch-tag')
    parser.add_argument('--allow-missing', action='store_true')
    args = parser.parse_args()
    api = GitHub(os.environ.get('GH_TOKEN', ''))
    if args.fetch_tag:
        if not args.fetch_tag.startswith('v'):
            raise ValueError('Invalid tag')
        appcast.version_key(args.fetch_tag[1:])
        metadata = api('GET', 'releases/tags/' + args.fetch_tag)
        if not metadata or metadata.get('draft'):
            if args.allow_missing:
                print('No published release available; static feeds remain unchanged.')
                return
            raise ValueError('Release is not published')
        args.metadata.parent.mkdir(parents=True, exist_ok=True)
        args.metadata.write_text(json.dumps(metadata))
        return
    if args.assets is None or args.build is None:
        raise ValueError('--assets and --build are required for publication')
    minimum = appcast.release.minimum_from_build_script(args.build_script.read_text()) if args.build_script else '12.0.0'
    items = appcast.candidate(json.loads(args.metadata.read_text()), args.assets, args.build, minimum)
    publish(api, items)


if __name__ == '__main__':
    main()
