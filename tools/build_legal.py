#!/usr/bin/env python3
"""Render docs/legal/*.md + the backend creator terms into <pages>/legal/*.html.

    tools/build_legal.py [--push]

Tiny markdown subset (headings, paragraphs, lists, links, **bold**, _italic_,
`code`), so it needs no dependencies. The takedown contact comes from
TAKEDOWN_CONTACT (same env var as the backend; defaults to the issues page).
"""
import html
import os
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "docs" / "legal"
OUT = pathlib.Path(os.getenv("CARTRIDGE_HOSTING_DIR", str(pathlib.Path.home() / "cartridge-games"))) / "legal"
CONTACT = os.getenv("TAKEDOWN_CONTACT", "https://github.com/4gus71n/cartridge-games/issues")

CSS = """
:root{color-scheme:dark}body{margin:0;background:#0B0E18;color:#E6E8F2;
font:16px/1.6 -apple-system,system-ui,Segoe UI,Roboto,sans-serif}
main{max-width:720px;margin:0 auto;padding:28px 20px 60px}
h1{font-size:28px;margin:8px 0 4px}h2{font-size:19px;margin:28px 0 6px;color:#B9C3FF}
a{color:#7CB8FF}code{background:#1B2140;padding:1px 5px;border-radius:4px}
em{color:#9AA3C0}nav{font-size:14px;margin-bottom:12px}nav a{margin-right:14px}
li{margin:4px 0}
"""
NAV = ('<nav><a href="index.html">Legal</a><a href="terms.html">Terms</a>'
       '<a href="privacy.html">Privacy</a><a href="creator-terms.html">Creators</a>'
       '<a href="takedown.html">Contact</a></nav>')


def inline(text: str) -> str:
    text = html.escape(text, quote=False)
    text = re.sub(r"`([^`]+)`", r"<code>\1</code>", text)
    text = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", text)
    text = re.sub(r"(?<!\w)_([^_]+)_(?!\w)", r"<em>\1</em>", text)
    text = re.sub(r"\[([^\]]+)\]\(([^)]+)\)", r'<a href="\2">\1</a>', text)
    return text


def render(md: str) -> str:
    out, para, lst = [], [], None

    def flush(keep_list: bool = False):
        nonlocal para, lst
        if para:
            out.append(f"<p>{inline(' '.join(para))}</p>")
            para = []
        if lst and not keep_list:
            tag, items = lst
            out.append(f"<{tag}>" + "".join(f"<li>{inline(i)}</li>" for i in items) + f"</{tag}>")
            lst = None

    for line in md.splitlines():
        s = line.strip()
        m_ul, m_ol = re.match(r"^- (.*)", s), re.match(r"^\d+\. (.*)", s)
        if not s:
            flush(keep_list=True)  # blank lines between items keep one numbered list
        elif s.startswith("#"):
            flush()
            level = len(s) - len(s.lstrip("#"))
            out.append(f"<h{level}>{inline(s[level:].strip())}</h{level}>")
        elif m_ul or m_ol:
            if para:
                flush()
            tag = "ul" if m_ul else "ol"
            if not lst or lst[0] != tag:
                flush()
                lst = (tag, [])
            lst[1].append((m_ul or m_ol).group(1))
        elif lst and line.startswith("  "):
            lst[1][-1] += " " + s
        else:
            if lst:
                flush()
            para.append(s)
    flush()
    return "\n".join(out)


def page(title: str, body: str) -> str:
    return (f'<!doctype html><html lang="en"><head><meta charset="utf-8">'
            f'<meta name="viewport" content="width=device-width,initial-scale=1">'
            f"<title>{html.escape(title)} · Cartridge</title><style>{CSS}</style></head>"
            f"<body><main>{NAV}{body}</main></body></html>\n")


def creator_terms_md() -> str:
    sys.path.insert(0, str(ROOT / "backend"))
    os.environ.setdefault("TAKEDOWN_CONTACT", CONTACT)
    from app.creator_terms import CREATOR_TERMS  # noqa: E402

    lines = CREATOR_TERMS.strip().splitlines()
    body = "\n".join(lines[1:])
    body = re.sub(r"^(\d+)\. ", r"\1. ", body, flags=re.M)
    return (f"# Creator terms\n\n_{lines[0]}_\n\n{body}\n\n"
            "Submit games in the creator portal. See the hosting guide there for a free setup "
            "(GitHub Pages plus a zip on a GitHub Release).\n")


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    contact = (f"Open an issue at [{CONTACT}]({CONTACT})" if CONTACT.startswith("http")
               else f"Email [{CONTACT}](mailto:{CONTACT})")
    docs = {p.stem: p.read_text().replace("__CONTACT__", contact) for p in SRC.glob("*.md")}
    docs["creator-terms"] = creator_terms_md()
    for name, md in sorted(docs.items()):
        title = md.splitlines()[0].lstrip("# ").strip()
        (OUT / f"{name}.html").write_text(page(title, render(md)))
        print(f"wrote {OUT / (name + '.html')}")
    if "--push" in sys.argv:
        repo = OUT.parent
        subprocess.run(["git", "add", "legal"], cwd=repo, check=True)
        if subprocess.run(["git", "diff", "--cached", "--quiet"], cwd=repo).returncode:
            subprocess.run(["git", "commit", "-qm", "legal: update pages"], cwd=repo, check=True)
            subprocess.run(["git", "push", "-q"], cwd=repo, check=True)
            print("pushed")


if __name__ == "__main__":
    main()
