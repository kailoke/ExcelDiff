#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Scan files for UTF-8 BOM state (worktree, optionally HEAD blobs too).

Usage:
  python scan_bom.py <dir> [--ext md,json,ps1] [--git]

Walks <dir> (skips .git/node_modules/Library/Temp/obj/Logs/.venv).
For each file with a matching extension prints:
  worktree BOM state, HEAD blob BOM state (with --git, needs a git repo).
Violations flagged per the two-directional encoding standard:
  VIOL-MD-BOM      .md/.json carrying a BOM (docs must be BOM-free)
  VIOL-PS1-NOBOM   .ps1 containing non-ASCII without BOM (PowerShell 5.1 reads it as ANSI)
Also reports: NOT-UTF8 (content corruption) and MID-BOM (U+FEFF outside position 0).
Exit code: 0 = no violations, 1 = violations found, 2 = bad arguments.
"""
import argparse
import os
import subprocess
import sys

BOM = b'\xef\xbb\xbf'
SKIP_DIRS = {'.git', 'node_modules', 'Library', 'Temp', 'obj', 'Logs', '.venv', '__pycache__'}


def head_blob(root, rel):
    """Return HEAD blob bytes for rel, or None (not tracked / no repo / error)."""
    try:
        r = subprocess.run(['git', '-C', root, 'show', 'HEAD:' + rel],
                           capture_output=True)
        return r.stdout if r.returncode == 0 else None
    except OSError:
        return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('dir')
    ap.add_argument('--ext', default='md,json,ps1')
    ap.add_argument('--git', action='store_true', help='also inspect HEAD blobs')
    args = ap.parse_args()

    try:
        sys.stdout.reconfigure(encoding='utf-8', errors='replace')
    except Exception:
        pass

    root = os.path.abspath(args.dir)
    if not os.path.isdir(root):
        print('not a directory: %s' % root)
        return 2
    exts = set()
    for e in args.ext.split(','):
        e = e.strip().lstrip('.').lower()
        if e:
            exts.add(e)

    total = 0
    violations = 0
    for dp, dns, fns in os.walk(root):
        dns[:] = [d for d in dns if d not in SKIP_DIRS]
        for fn in sorted(fns):
            ext = os.path.splitext(fn)[1].lower().lstrip('.')
            if ext not in exts:
                continue
            p = os.path.join(dp, fn)
            total += 1
            try:
                with open(p, 'rb') as f:
                    data = f.read()
            except OSError as e:
                print('READ-ERROR %s (%s)' % (p, e))
                continue
            rel = os.path.relpath(p, root).replace(os.sep, '/')
            has_bom = data.startswith(BOM)
            body = data[3:] if has_bom else data
            hd = ''
            if args.git:
                blob = head_blob(root, rel)
                if blob is None:
                    hd = '  head=untracked/no-repo'
                else:
                    hd = '  head=' + ('BOM' if blob.startswith(BOM) else 'none')
            msgs = []
            text = None
            try:
                text = body.decode('utf-8')
            except UnicodeDecodeError as e:
                msgs.append('NOT-UTF8(%s)' % e)
            if text is not None:
                mid = text.count('\ufeff')
                if mid:
                    msgs.append('MID-BOM x%d' % mid)
                if ext == 'ps1' and any(ord(c) > 127 for c in text) and not has_bom:
                    msgs.append('VIOL-PS1-NOBOM')
            if ext in ('md', 'json') and has_bom:
                msgs.append('VIOL-MD-BOM')
            if any(m.startswith('VIOL') for m in msgs):
                violations += 1
            flag = ('  << ' + '; '.join(msgs)) if msgs else ''
            print('%-4s %s%s%s' % ('BOM' if has_bom else 'none', rel, hd, flag))
    print('--- %d file(s) scanned, %d violation(s)' % (total, violations))
    return 1 if violations else 0


if __name__ == '__main__':
    sys.exit(main())
