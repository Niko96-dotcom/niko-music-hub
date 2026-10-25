#!/usr/bin/env python3
"""Fail on a broken relative link or #anchor in the repository's Markdown files.

Checks [text](target), ![alt](target) and HTML href/src attributes outside code. A target
must exist relative to the file; a #fragment into a Markdown file must match one of its
headings (GitHub's slugs). External links are not fetched. docs/history/ is skipped except
its README: those records keep the links they had before they moved there. In a Git checkout
the files are Git's (tracked, plus untracked ones .gitignore does not exclude), so other
worktrees and ignored folders are never read; without Git (the buyer export) it walks the folder.
Usage: script/check-doc-links.py [repo-root]   (default: the current directory)
"""

import os
import re
import subprocess
import sys
from urllib.parse import unquote

ROOT = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else os.getcwd())
SKIP_DIRS = {".build", ".git", ".deslop", ".cursor", ".planning", ".ai", ".codex", "dist", "DerivedData", "node_modules"}
LINK = re.compile(r"!?\[(?:[^\[\]]|\[[^\]]*\])*\]\(\s*<?([^)\s>]+)>?(?:\s+\"[^\"]*\")?\s*\)")
HTML = re.compile(r"""\b(?:href|src)=["']([^"']+)["']""")
FENCE = re.compile(r"^\s*(```|~~~)")


def repository_files():
    """Every file a link may point to, relative to ROOT, and every folder that holds one."""
    if os.path.exists(os.path.join(ROOT, ".git")):
        listed = subprocess.run(["git", "-C", ROOT, "ls-files", "-z", "--cached", "--others", "--exclude-standard"],
                                capture_output=True, text=True, check=True).stdout.split("\0")
        files = {path for path in listed if path and os.path.exists(os.path.join(ROOT, path))}
    else:
        files = set()
        for directory, subdirs, names in os.walk(ROOT):
            subdirs[:] = [d for d in subdirs if d not in SKIP_DIRS]
            files |= {os.path.relpath(os.path.join(directory, name), ROOT) for name in names}
    parts = [path.split("/")[:-1] for path in files]
    return files, {"/".join(folder[:depth]) for folder in parts for depth in range(1, len(folder) + 1)}


FILES, FOLDERS = repository_files()


def markdown_files():
    for path in sorted(FILES):
        if path.endswith(".md") and (not path.startswith("docs/history/") or path == "docs/history/README.md"):
            yield path


def prose_lines(path, keep_code=False):
    """(line number, text) outside fenced code blocks; inline code spans blanked unless keep_code."""
    in_fence = False
    with open(os.path.join(ROOT, path), encoding="utf-8") as handle:
        for number, line in enumerate(handle, 1):
            if FENCE.match(line):
                in_fence = not in_fence
            elif not in_fence:
                yield number, line if keep_code else re.sub(r"`[^`]*`", "", line)


def anchors(path, cache={}):
    if path not in cache:
        slugs, seen = set(), {}
        for _, line in prose_lines(path, keep_code=True):
            heading = re.match(r"^#{1,6}\s+(.*?)\s*#*\s*$", line)
            if heading:
                text = re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", heading.group(1))
                slug = re.sub(r"[^\w\- ]", "", text.lower()).replace(" ", "-")
                count = seen.get(slug, 0)
                seen[slug] = count + 1
                slugs.add(slug if count == 0 else f"{slug}-{count}")
        cache[path] = slugs
    return cache[path]


def problems(path):
    for number, line in prose_lines(path):
        for target in LINK.findall(line) + HTML.findall(line):
            if re.match(r"^[a-z][a-z0-9+.-]*:", target, re.IGNORECASE):
                continue  # https:, mailto: and other external links
            file_part, _, fragment = target.partition("#")
            resolved = os.path.normpath(os.path.join(os.path.dirname(path), unquote(file_part))) if file_part else path
            if resolved not in FILES and resolved not in FOLDERS:
                yield f"{path}:{number}: {target}: {resolved} does not exist"
            elif fragment and resolved.endswith(".md") and unquote(fragment).lower() not in anchors(resolved):
                yield f"{path}:{number}: {target}: no heading #{fragment} in {resolved}"


if __name__ == "__main__":
    found = [problem for path in markdown_files() for problem in problems(path)]
    for problem in found:
        print(problem, file=sys.stderr)
    if found:
        print(f"check-doc-links: {len(found)} broken link(s). Fix the link or the heading it points to.", file=sys.stderr)
        sys.exit(1)
    print("check-doc-links: every relative link and anchor resolves")
