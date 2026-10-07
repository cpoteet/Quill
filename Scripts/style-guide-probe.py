#!/usr/bin/env python3
import base64, html, json, os, re, sys, urllib.error, urllib.request
from html.parser import HTMLParser

SUPPORT = os.path.expanduser("~/Library/Application Support/Quill")
KEEP = {"h1", "h2", "h3", "h4", "h5", "h6", "p", "ul", "ol", "li", "blockquote",
        "a", "em", "strong", "i", "b", "sup", "figcaption", "table", "tr", "th", "td"}
BLOCK = {"h1", "h2", "h3", "h4", "h5", "h6", "p", "ul", "ol", "li", "blockquote", "figcaption", "table", "tr"}
BREAK = {"br", "hr", "div", "figure", "section", "pre", "details", "summary", "dt", "dd"}

# Keep in sync with AIPromptBuilder.styleGuideGenerationPrompt.
PROMPT = """Analyze these blog post samples and write a style guide that another writer can follow to write new posts in this author's style. The guide will be used both to write new posts and to judge whether a draft sounds like this author.

Each sample is one post's title, word count and body. The HTML has been reduced to its structure: headings, paragraphs, lists, tables, block quotes, links, emphasis and footnotes. Images appear as [image], followed by their caption if they have one.

Rules:
- Write each point as an instruction to the writer ("Open with…", "Use…"), not as a description of the author.
- Describe how the author writes, not what they write about. Leave out topics, products, hobbies and projects from the samples unless they show a habit that would carry over to any subject.
- State a pattern only if it appears in at least two samples. Leave out generic writing advice.
- Describe habits as tendencies ("often", "now and then"), not as rules to apply every time.
- You may illustrate a habit with a word or short phrase in quotation marks, copied exactly from the samples. Never quote a whole sentence, and don't name products or technologies.

Use exactly these labels, in this order, with nothing added to them. Under each label, write a short paragraph or a few bullets:

Voice and tone:
Sentence rhythm:
Vocabulary:
Humor and personality:
Openings and closings:
Structure and length:
Formatting:
Avoid:

Formatting covers headings, lists, tables, footnotes, links, images and captions. Avoid covers things a generic writer would do that this author doesn't, and only where the samples make it clear.

Aim for about 500 words. Start your response with "Voice and tone:" and end it after the Avoid section.

"""


class Reducer(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.out = []

    def handle_starttag(self, tag, attrs):
        if tag == "img":
            self.out.append("\n[image] ")
        elif tag in KEEP:
            self.out.append(("\n" if tag in BLOCK else "") + f"<{tag}>")
        elif tag in BREAK:
            self.out.append("\n")

    def handle_endtag(self, tag):
        if tag in KEEP:
            self.out.append(f"</{tag}>")
        elif tag in BREAK:
            self.out.append("\n")

    def handle_data(self, data):
        self.out.append(html.escape(re.sub(r"\s+", " ", data), quote=False))


def reduce_html(s):
    r = Reducer()
    r.feed(s)
    text = re.sub(r"<(\w+)>\s*</\1>", "", "".join(r.out))
    return "\n".join(line.strip() for line in text.splitlines() if line.strip())


def plain(s):
    return " ".join(html.unescape(re.sub(r"<[^>]+>", " ", s)).split())


def fetch(url, headers):
    with urllib.request.urlopen(urllib.request.Request(url, headers=headers)) as r:
        return json.load(r)


def load_samples(creds, ids):
    auth = base64.b64encode(f"{creds['username']}:{creds['appPassword']}".encode()).decode()
    headers = {"Authorization": f"Basic {auth}"}
    base = creds["siteURL"].rstrip("/") + "/wp-json/wp/v2"
    samples = []
    for pid in ids:
        try:
            post = fetch(f"{base}/posts/{pid}", headers)
        except urllib.error.HTTPError:
            post = fetch(f"{base}/pages/{pid}", headers)
        samples.append((html.unescape(post["title"]["rendered"]), reduce_html(post["content"]["rendered"])))
    return samples


def complete(api_key, model, prompt, effort):
    request = {
        "model": model,
        "max_tokens": 16000,
        "system": [{"type": "text", "text": "Return only the requested style guide with no preamble."}],
        "messages": [{"role": "user", "content": prompt}],
    }
    if effort:
        request["thinking"] = {"type": "adaptive"}
        request["output_config"] = {"effort": effort}
    body = json.dumps(request).encode()
    req = urllib.request.Request("https://api.anthropic.com/v1/messages", data=body, headers={
        "x-api-key": api_key, "anthropic-version": "2023-06-01", "content-type": "application/json"})
    with urllib.request.urlopen(req) as r:
        return json.load(r)


def quote_report(guide, bodies):
    texts = [plain(b).replace("’", "'").lower() for b in bodies]
    quotes = re.findall(r'"([^"]+)"', guide.replace("“", '"').replace("”", '"'))
    counts = {"2+": 0, "1": 0, "0": 0}
    for q in quotes:
        key = q.replace("…", "").rstrip(".,").strip().lower().replace("’", "'")
        pattern = re.compile(r"(?<!\w)" + re.escape(" ".join(key.split())) + r"(?!\w)")
        n = sum(bool(pattern.search(t)) for t in texts)
        counts["2+" if n >= 2 else str(n)] += 1
        if n == 0 or len(q.split()) >= 6:
            print(f"  {'not found' if n == 0 else 'long quote'}: \"{q}\"", file=sys.stderr)
    return len(quotes), counts


def main():
    if len(sys.argv) not in (2, 3):
        sys.exit("usage: Scripts/style-guide-probe.py <model-id> [effort]")
    model = sys.argv[1]
    effort = sys.argv[2] if len(sys.argv) == 3 else None
    creds = json.load(open(f"{SUPPORT}/credentials.json"))
    ai = json.load(open(f"{SUPPORT}/ai_settings.json"))

    samples = load_samples(creds, ai["samplePostIDs"])
    prompt = PROMPT + "\n\n".join(
        f"--- Sample {i}: {title} ({len(plain(body).split()):,} words) ---\n{body}"
        for i, (title, body) in enumerate(samples, 1))

    resp = complete(ai["apiKey"], model, prompt, effort)
    if resp["stop_reason"] == "refusal":
        sys.exit(f"{model} refused the request")
    guide = "".join(b["text"] for b in resp["content"] if b["type"] == "text")
    print(guide)

    total, counts = quote_report(guide, [b for _, b in samples])
    u = resp["usage"]
    print(f"\n{model} ({effort or 'default effort'}): {len(guide.split())} words, stop {resp['stop_reason']}, "
          f"{u['input_tokens']} in / {u['output_tokens']} out", file=sys.stderr)
    print(f"{total} quotes: {counts['2+']} in 2+ samples, {counts['1']} in one, "
          f"{counts['0']} not found", file=sys.stderr)


if __name__ == "__main__":
    main()
