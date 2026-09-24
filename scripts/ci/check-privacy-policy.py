#!/usr/bin/env python3
"""Keep the public privacy page's policy text aligned with its Markdown source."""

from html.parser import HTMLParser
from pathlib import Path
import re
import sys


def normalized(text):
    return " ".join(text.split())


def markdown_blocks(path):
    blocks = []
    paragraph = []

    def finish_paragraph():
        if paragraph:
            text = " ".join(paragraph)
            text = re.sub(r"\[([^]]+)\]\([^)]+\)", r"\1", text)
            blocks.append(normalized(text))
            paragraph.clear()

    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line:
            finish_paragraph()
        elif line.startswith("# "):
            finish_paragraph()
        elif line.startswith("## "):
            finish_paragraph()
            blocks.append(line[3:])
        else:
            paragraph.append(line)
    finish_paragraph()
    return blocks


class PolicyPage(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.in_main = False
        self.active_tag = None
        self.parts = []
        self.blocks = []

    def handle_starttag(self, tag, attributes):
        if tag == "main":
            self.in_main = True
        if self.in_main and tag in ("h2", "p"):
            classes = dict(attributes).get("class", "").split()
            if "document-kicker" not in classes:
                self.active_tag = tag
                self.parts = []

    def handle_data(self, data):
        if self.active_tag:
            self.parts.append(data)

    def handle_endtag(self, tag):
        if tag == self.active_tag:
            self.blocks.append(normalized("".join(self.parts)))
            self.active_tag = None
        if tag == "main":
            self.in_main = False


root = Path(__file__).resolve().parents[2]
source = markdown_blocks(root / "docs/privacy-policy.md")
page = PolicyPage()
page.feed((root / "site/privacy/index.html").read_text(encoding="utf-8"))

if source != page.blocks:
    for index, (expected, actual) in enumerate(zip(source, page.blocks), 1):
        if expected != actual:
            print(f"Privacy copy differs at block {index}:\n  docs: {expected}\n  site: {actual}", file=sys.stderr)
            break
    else:
        print(f"Privacy copy has {len(source)} documentation blocks and {len(page.blocks)} site blocks.", file=sys.stderr)
    raise SystemExit(1)

print("Privacy policy matches the public page.")
