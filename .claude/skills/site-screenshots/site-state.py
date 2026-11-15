#!/usr/bin/env python3
"""Print, read-only, what a screenshot run must leave untouched on the connected site.

    python3 site-state.py > before.txt   ...   python3 site-state.py | diff before.txt -

Lines: the Codex post's id, status and modified_gmt; the media-view image's id and
modified_gmt; and the total number of posts and pages in any status (an accidental "Save to
WordPress" from a local draft would add one). Reads Quill's credentials.json inside the script
and never prints it.
"""
import base64
import json
import os
import sys
import urllib.parse
import urllib.request

POST_TITLE = "Learning to Build with Codex"
MEDIA_TITLE = "The Five Stages of AI Reckoning"

creds = json.load(open(os.path.expanduser("~/Library/Application Support/Quill/credentials.json")))
token = base64.b64encode(f'{creds["username"]}:{creds["appPassword"]}'.encode()).decode()


def get(route, **params):
    url = creds["siteURL"].rstrip("/") + "/wp-json/wp/v2/" + route + "?" + urllib.parse.urlencode(params)
    request = urllib.request.Request(url, headers={"Authorization": f"Basic {token}", "User-Agent": "Quill-screenshots"})
    with urllib.request.urlopen(request) as response:
        return json.load(response), response.headers.get("X-WP-Total")


def find(route, title, fields):
    items, _ = get(route, search=title, context="edit", _fields="id,title," + fields)
    for item in items:
        if item["title"]["raw"] == title:
            return item
    sys.exit(f"No {route} titled {title!r}")


post = find("posts", POST_TITLE, "status,modified_gmt")
print("post", post["id"], post["status"], post["modified_gmt"])
media = find("media", MEDIA_TITLE, "modified_gmt")
print("media", media["id"], media["modified_gmt"])
for route in ("posts", "pages"):
    _, total = get(route, status="publish,future,draft,pending,private", per_page=1, _fields="id")
    print(route, "total", total)
