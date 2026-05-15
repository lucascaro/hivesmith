#!/usr/bin/env python3
"""Render a plan manifest (JSON) + frozen template (HTML) into a self-contained plan HTML.

The LLM authors only the per-section plan content as HTML fragments — the
chrome (CSS, JS, savebar, theme switching, mermaid+hl.js wiring) comes from
the packaged template, unchanged. This keeps token use small and the CSS/JS
contracts pinned.

Manifest schema (JSON):
{
  "title": "Plain title text",                 # required, used in <title> and <h1>
  "title_html": "...optional inline HTML...",  # optional override for <h1> only
  "lede": "...optional HTML for .lede paragraph...",
  "toc": [                                     # optional; when present, renders the contents box
    {"id": "context", "label": "Context"},
    ...
  ],
  "sections": [                                # required, at least one entry
    {
      "id": "context",
      "heading": "Context",                    # H2 heading text
      "html": "<p>...body html...</p>",       # body content
      "changed": false,                        # optional; wraps body in <div class="changed">
      "feedback": {                            # default-on; pass `false` to suppress
        "slug": "context",                     # data-section value (defaults to section id)
        "label": "feedback - context",         # defaults to "feedback — <heading>"
        "placeholder": "..."                   # optional textarea placeholder
      }
    },
    ...
  ],
  "global_feedback": {                         # default-on; pass `false` to suppress
    "slug": "global",                          # defaults to "global"
    "label": "feedback - global / open questions",
    "placeholder": "..."
  }
}

Strict tag allowlist is enforced on body html. Unknown tags raise SystemExit(3)
so model drift surfaces immediately rather than silently shipping a broken UI.

Usage:
  render_plan.py --manifest <path.json> --template <template.html> --out <plan.html>
  render_plan.py --self-test          # render fixture to /tmp; assert placeholders gone
"""
from __future__ import annotations

import argparse
import html
import json
import re
import sys
import tempfile
from html.parser import HTMLParser
from pathlib import Path

# Tag allowlist for section body HTML. The chrome (CSS, JS, html, head, body,
# div.wrap, savebar, etc.) lives in template.html and is not subject to this
# allowlist — only model-authored section content is checked.
ALLOWED_TAGS: dict[str, set[str]] = {
    # Block + inline content
    "p": {"class"},
    "div": {"class", "id"},
    "span": {"class"},
    "h2": {"id", "class"},
    "h3": {"id", "class"},
    "h4": {"id", "class"},
    "ul": {"class"},
    "ol": {"class", "start"},
    "li": {"class", "id"},
    "strong": set(),
    "em": set(),
    "b": set(),
    "i": set(),
    "br": set(),
    "hr": set(),
    "blockquote": {"class"},
    "a": {"href", "title", "class"},
    # Code
    "pre": {"class"},
    "code": {"class"},  # class is used by hljs language hints (e.g. "language-python")
    # Tables
    "table": {"class"},
    "thead": set(),
    "tbody": set(),
    "tr": set(),
    "th": {"colspan", "rowspan", "class"},
    "td": {"colspan", "rowspan", "class"},
    # Plan-specific affordances
    "aside": {"class", "data-section"},
    "label": {"for"},
    "textarea": {"id", "data-section", "placeholder"},
    "button": {"type", "class", "id", "title"},
    "img": {"src", "alt", "title", "width", "height"},
}

# Class values are not parsed semantically, but we forbid javascript-like
# attribute values defensively even though no event-handler attrs are allowed.
_FORBIDDEN_ATTR_VALUE = re.compile(r"javascript:", re.IGNORECASE)


class _AllowlistValidator(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=False)
        self.errors: list[str] = []

    def _check(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        tag = tag.lower()
        if tag not in ALLOWED_TAGS:
            self.errors.append(f"disallowed tag <{tag}>")
            return
        allowed_attrs = ALLOWED_TAGS[tag]
        for name, value in attrs:
            name_l = name.lower()
            if name_l.startswith("on"):
                self.errors.append(f"event handler attribute <{tag} {name}=...> not allowed")
                continue
            if name_l not in allowed_attrs:
                self.errors.append(f"<{tag}> disallowed attr '{name}'")
                continue
            if value and _FORBIDDEN_ATTR_VALUE.search(value):
                self.errors.append(f"<{tag} {name}=...> disallowed value")

    def handle_starttag(self, tag: str, attrs):  # noqa: D401
        self._check(tag, attrs)

    def handle_startendtag(self, tag: str, attrs):
        self._check(tag, attrs)


def validate_section_html(name: str, body: str) -> None:
    validator = _AllowlistValidator()
    validator.feed(body)
    validator.close()
    if validator.errors:
        joined = "\n  - ".join(validator.errors)
        sys.stderr.write(
            f"render_plan: section '{name}' failed allowlist check:\n  - {joined}\n"
        )
        sys.exit(3)


def _render_toc(toc: list[dict]) -> str:
    if not toc:
        return ""
    items = "\n".join(
        f'    <li><a href="#{html.escape(e["id"])}">{html.escape(e["label"])}</a></li>'
        for e in toc
    )
    return (
        '<div class="toc">\n'
        '  <strong>Contents</strong>\n'
        '  <ol>\n'
        f'{items}\n'
        '  </ol>\n'
        '</div>'
    )


def _render_feedback(fb: dict | None) -> str:
    if not fb:
        return ""
    slug = html.escape(fb["slug"])
    label = html.escape(fb.get("label", f"feedback — {slug}"))
    placeholder = html.escape(fb.get("placeholder", ""))
    return (
        f'<aside class="feedback" data-section="{slug}">\n'
        f'  <label for="fb-{slug}">✎ {label}</label>\n'
        f'  <textarea id="fb-{slug}" data-section="{slug}" placeholder="{placeholder}"></textarea>\n'
        '</aside>'
    )


def _resolve_feedback(raw, default_slug: str, default_label: str) -> dict | None:
    if raw is False:
        return None
    if raw is None:
        return {"slug": default_slug, "label": default_label}
    if isinstance(raw, dict):
        return raw
    return {"slug": default_slug, "label": default_label}


def _render_section(section: dict) -> str:
    sid = html.escape(section["id"])
    heading_text = section["heading"]
    heading = html.escape(heading_text)
    body = section.get("html", "")
    validate_section_html(section["id"], body)
    if section.get("changed"):
        body_block = f'<div class="changed">\n{body}\n</div>'
    else:
        body_block = body
    parts = [f'<h2 id="{sid}">{heading}</h2>', body_block]
    fb_spec = _resolve_feedback(
        section.get("feedback", None),
        default_slug=section["id"],
        default_label=f"feedback — {heading_text}",
    )
    fb = _render_feedback(fb_spec)
    if fb:
        parts.append(fb)
    return "\n".join(parts)


def render(manifest: dict, template: str) -> str:
    title = manifest.get("title")
    if not title:
        sys.stderr.write("render_plan: manifest missing 'title'\n")
        sys.exit(4)
    sections = manifest.get("sections") or []
    if not sections:
        sys.stderr.write("render_plan: manifest must have at least one section\n")
        sys.exit(4)

    title_text = html.escape(title)
    title_html = manifest.get("title_html") or title_text
    lede = manifest.get("lede", "")
    # title_html and lede are injected as raw HTML into the template, so they
    # must clear the same allowlist applied to section bodies. Empty strings
    # are no-ops; title_text is HTML-escaped and safe by construction.
    if manifest.get("title_html"):
        validate_section_html("title_html", title_html)
    if lede:
        validate_section_html("lede", lede)
    toc_html = _render_toc(manifest.get("toc") or [])

    body_blocks = [_render_section(s) for s in sections]
    global_fb_spec = _resolve_feedback(
        manifest.get("global_feedback", None),
        default_slug="global",
        default_label="feedback — global / open questions",
    )
    global_fb = _render_feedback(global_fb_spec)
    if global_fb:
        body_blocks.append("<hr>")
        body_blocks.append(global_fb)
    body_html = "\n\n".join(body_blocks)

    out = template
    out = out.replace("<!-- PLAN_TITLE -->", title_text)
    out = out.replace("<!-- PLAN_TITLE_HTML -->", title_html)
    out = out.replace("<!-- PLAN_LEDE -->", lede)
    out = out.replace("<!-- PLAN_TOC -->", toc_html)
    out = out.replace("<!-- PLAN_BODY -->", body_html)
    return out


def _self_test() -> int:
    here = Path(__file__).parent
    template = (here / "template.html").read_text()
    manifest = {
        "title": "Smoke test plan",
        "lede": '<p>Smoke test rendering — checks placeholders are filled and JS contracts intact.</p>',
        "toc": [
            {"id": "context", "label": "Context"},
            {"id": "approach", "label": "Approach"},
        ],
        "sections": [
            {
                "id": "context",
                "heading": "Context",
                "html": '<p>Render test body. <code>inline code</code> works.</p>',
                "feedback": {"slug": "context", "label": "feedback — context"},
            },
            {
                "id": "approach",
                "heading": "Approach",
                "html": '<div class="changed"><p>Revised section, should render with the .changed banner.</p></div>',
                "feedback": {"slug": "approach", "label": "feedback — approach"},
            },
        ],
        "global_feedback": {"slug": "global", "label": "feedback — global"},
    }
    out = render(manifest, template)
    # Assertions
    failures = []
    for placeholder in ("<!-- PLAN_TITLE -->", "<!-- PLAN_TITLE_HTML -->",
                        "<!-- PLAN_LEDE -->", "<!-- PLAN_TOC -->", "<!-- PLAN_BODY -->"):
        if placeholder in out:
            failures.append(f"placeholder still present: {placeholder}")
    if "Smoke test plan" not in out:
        failures.append("title not rendered")
    if 'data-section="context"' not in out:
        failures.append("feedback aside for section not rendered")
    if 'class="changed"' not in out:
        failures.append("changed wrapper missing")
    if "<script>" not in out or "fetch(u('/save')" not in out:
        failures.append("template chrome (JS) missing")
    if failures:
        for f in failures:
            sys.stderr.write(f"self-test FAIL: {f}\n")
        return 1
    # Write the output for visual inspection
    tmp = Path(tempfile.gettempdir()) / "hs-plan-html-selftest.html"
    tmp.write_text(out, encoding="utf-8")
    sys.stderr.write(f"self-test OK -> {tmp}\n")

    # Default-on feedback: when a section omits `feedback`, the renderer
    # synthesizes one; when `feedback: false`, it suppresses; missing
    # `global_feedback` defaults to the global aside being present.
    default_fb_manifest = {
        "title": "Feedback default test",
        "sections": [
            {"id": "alpha", "heading": "Alpha", "html": "<p>no feedback key</p>"},
            {"id": "beta", "heading": "Beta", "html": "<p>opted out</p>", "feedback": False},
        ],
    }
    out2 = render(default_fb_manifest, template)
    fb_failures = []
    if 'data-section="alpha"' not in out2:
        fb_failures.append("default per-section feedback missing for 'alpha'")
    if 'data-section="beta"' in out2:
        fb_failures.append("section 'beta' with feedback=false still rendered an aside")
    if 'data-section="global"' not in out2:
        fb_failures.append("default global feedback aside missing")
    if fb_failures:
        for f in fb_failures:
            sys.stderr.write(f"self-test FAIL: {f}\n")
        return 1
    sys.stderr.write("self-test OK (feedback defaults)\n")

    # Negative tests: disallowed tags must reject in every raw-HTML input
    # (section bodies, title_html, and lede all share the allowlist).
    bad_inputs = [
        ("section body", {
            "title": "bad",
            "sections": [{"id": "x", "heading": "X", "html": "<script>alert(1)</script>"}],
        }),
        ("title_html", {
            "title": "bad",
            "title_html": "<script>alert(1)</script>",
            "sections": [{"id": "x", "heading": "X", "html": "<p>ok</p>"}],
        }),
        ("lede", {
            "title": "bad",
            "lede": "<script>alert(1)</script>",
            "sections": [{"id": "x", "heading": "X", "html": "<p>ok</p>"}],
        }),
    ]
    for label, bad in bad_inputs:
        try:
            render(bad, template)
        except SystemExit as exc:
            if exc.code == 3:
                sys.stderr.write(f"self-test OK (allowlist rejected <script> in {label})\n")
                continue
            sys.stderr.write(f"self-test FAIL: {label} allowlist exited {exc.code}, expected 3\n")
            return 1
        else:
            sys.stderr.write(f"self-test FAIL: allowlist did not reject <script> in {label}\n")
            return 1
    # Sanity check: only one <title> element survives substitution
    if out.count("<title>") != 1:
        sys.stderr.write(
            f"self-test FAIL: expected exactly one <title>, got {out.count('<title>')}\n"
        )
        return 1
    sys.stderr.write("self-test OK (single <title> after render)\n")
    return 0


def main(argv: list[str]) -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--manifest", type=Path)
    p.add_argument("--template", type=Path)
    p.add_argument("--out", type=Path)
    p.add_argument("--self-test", action="store_true")
    args = p.parse_args(argv)

    if args.self_test:
        return _self_test()

    if not (args.manifest and args.template and args.out):
        p.error("--manifest, --template, and --out are all required (or --self-test)")
        return 2

    manifest = json.loads(args.manifest.read_text(encoding="utf-8"))
    template = args.template.read_text(encoding="utf-8")
    out = render(manifest, template)
    args.out.write_text(out, encoding="utf-8")
    sys.stderr.write(f"rendered -> {args.out}\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
