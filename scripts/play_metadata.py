#!/usr/bin/env python3
"""Derive Play track and names; versionCode is numeric, never a Git hash."""
from datetime import datetime, timezone
import os
import re

EPOCH = 1577836800  # 2020-01-01 UTC; fits Play's 2100000000 limit until 2086.


def metadata(ref, sha, release_tag='', now=None):
    if not re.fullmatch(r'[0-9a-fA-F]{40}', sha):
        raise ValueError('Expected a full Git commit SHA')
    tag = release_tag or (ref.removeprefix('refs/tags/') if ref.startswith('refs/tags/') else '')
    if tag:
        if not re.fullmatch(r'v[A-Za-z0-9][A-Za-z0-9._+-]{0,49}', tag):
            raise ValueError('Release tag must start with v and contain a valid Android version name')
        name, track, release_name = tag[1:], 'production', tag
    else:
        if ref != 'refs/heads/main':
            raise ValueError('Only main commits and v* tags can publish to Play')
        name, track, release_name = sha[-6:].lower(), 'beta', sha[-6:].lower()
    timestamp = now if now is not None else datetime.now(timezone.utc).timestamp()
    code = int(timestamp) - EPOCH
    if not 1 <= code <= 2100000000:
        raise ValueError('Generated versionCode is outside Google Play limits')
    return dict(version_code=str(code), version_name=name, track=track, release_name=release_name)


if __name__ == '__main__':
    try:
        result = metadata(os.environ['GITHUB_REF'], os.environ['GITHUB_SHA'], os.environ.get('RELEASE_TAG', ''))
    except ValueError as error:
        raise SystemExit(str(error)) from None
    with open(os.environ['GITHUB_OUTPUT'], 'a') as output:
        for key, value in result.items():
            output.write(f'{key}={value}\n')
    print(f"Play track={result['track']}, versionName={result['version_name']}, versionCode={result['version_code']}")
