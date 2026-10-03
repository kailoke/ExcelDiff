#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Add or strip a leading UTF-8 BOM with byte-exact assertions.

Usage:
  python bom_surgery.py --mode strip <file>... [--dry-run]
  python bom_surgery.py --mode add   <file>... [--dry-run]

strip : remove the leading EF BB BF if present (docs md/json -> BOM-free).
add   : prepend EF BB BF if absent (for .ps1 containing non-ASCII).

Safety, enforced per file; any failure refuses the write:
  - body (file minus leading BOM) must decode as strict UTF-8;
  - expected result bytes computed in memory and asserted equal to
    old[3:] (strip) or BOM+old (add) before writing;
  - file is re-read after write and compared; on mismatch the original
    bytes are restored.
Use only on files you can still verify afterwards (git-tracked => git show).
For gitignored files with any damage already present, rewrite the whole
file in the target encoding instead of slicing bytes.
Exit code: 0 = all ok/skipped, 1 = any refusal or failure.
"""
import argparse
import os
import sys

BOM = b'\xef\xbb\xbf'


def process(path, mode, dry_run):
    try:
        with open(path, 'rb') as f:
            data = f.read()
    except OSError as e:
        return 'REFUSED  %s : %s' % (path, e)
    has_bom = data.startswith(BOM)
    body = data[3:] if has_bom else data
    try:
        body.decode('utf-8')
    except UnicodeDecodeError as e:
        return 'REFUSED  %s : body not strict UTF-8 (%s) -> rewrite whole file instead' % (path, e)
    if mode == 'strip':
        if not has_bom:
            return 'SKIP     %s : no BOM' % path
        new = data[3:]
        ok_explicit = (new == body)
    else:
        if has_bom:
            return 'SKIP     %s : already has BOM' % path
        new = BOM + data
        ok_explicit = (new[3:] == data)
    if not ok_explicit:
        return 'REFUSED  %s : tail assertion broke in memory' % path
    if dry_run:
        return 'DRY      %s : %s %d -> %d bytes' % (path, mode, len(data), len(new))
    try:
        with open(path, 'wb') as f:
            f.write(new)
        with open(path, 'rb') as f:
            check = f.read()
    except OSError as e:
        try:
            with open(path, 'wb') as f:
                f.write(data)
        except OSError:
            pass
        return 'FAILED   %s : %s' % (path, e)
    if check != new:
        try:
            with open(path, 'wb') as f:
                f.write(data)
        except OSError:
            pass
        return 'FAILED   %s : re-read mismatch, original restored' % path
    return 'OK       %s : %s %d -> %d bytes, tail-identical=True' % (path, mode, len(data), len(new))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('files', nargs='+')
    ap.add_argument('--mode', required=True, choices=['strip', 'add'])
    ap.add_argument('--dry-run', action='store_true')
    args = ap.parse_args()

    try:
        sys.stdout.reconfigure(encoding='utf-8', errors='replace')
    except Exception:
        pass

    bad = 0
    for p in args.files:
        if not os.path.isfile(p):
            print('REFUSED  %s : not a file' % p)
            bad += 1
            continue
        line = process(p, args.mode, args.dry_run)
        print(line)
        if line.startswith(('REFUSED', 'FAILED')):
            bad += 1
    print('--- %d file(s), %d refused/failed' % (len(args.files), bad))
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main())
