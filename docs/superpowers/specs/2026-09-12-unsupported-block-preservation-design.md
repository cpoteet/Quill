# Unsupported block preservation and the data-loss alarm

_Design, 2026-09-12. Follows the Gutenberg block model work (`2026-09-11-gutenberg-block-model-design.md`)._

## Problem

Quill recognises a Gutenberg block by a `wp-block-*` class on its rendered element. Blocks whose saved markup carries no such class are not preserved. Verified by probing the live editor in jsdom, driving the real `window.setContent` / `window.getContent` path, with an edit in between:

| Input | Result after an edit elsewhere in the post |
|---|---|
| `<!-- wp:html --><div class="promo">…</div><!-- /wp:html -->` | Flattened to `<p><strong>Hi</strong></p>`. Wrapper, class and block identity lost. |
| `<!-- wp:shortcode -->[gallery ids="1,2"]<!-- /wp:shortcode -->` | Shortcode text survives as a plain paragraph; the block is gone. |
| `<!-- wp:calendar /-->`, `<!-- wp:navigation {"ref":9} /-->` | Deleted silently. No element exists to attach to. |
| `<!-- wp:block {"ref":1234} /-->` (synced pattern) | Deleted silently. |
| `<!-- wp:nextpage --><!--nextpage--><!-- /wp:nextpage -->` | Deleted silently. Same for `wp:more`. |
| `<!-- wp:acme/widget --><div class="acme-widget">…</div><!-- /wp:acme/widget -->` | Flattened. Any third-party block not following the class convention. |

Blocks that *do* carry the class are unaffected and already round-trip verbatim: Cover, Media & Text, File, Group, Spacer, Social Links, Verse, Audio, Video, Playlist, Search, and Query Loop including its nested dynamic inner blocks.

The existing raw-HTML safety net means an unedited post always saves back byte-identically, so none of the above can happen from opening a post. It requires an edit.

## Goals

1. Preserve every block Quill does not model, regardless of whether its markup carries a `wp-block-*` class or any markup at all.
2. Detect and report any residual loss, independently of the mechanism in goal 1.

Non-goals: making Custom HTML or Shortcode editable in the visual editor (code view remains the editing path), and any change to how modeled blocks behave.

## Part 1: Preservation

### Mechanism

On load, run the incoming `post_content` through the bundled WordPress block parser (`block-parser-bundle.js`) to enumerate top-level blocks. For each block Quill's own nodes will not claim, wrap it in a synthetic element that the existing `gutenbergPassthrough` node already knows how to hold, carrying that block's exact source text in an attribute. On save, replace the wrapper with the stored text.

Using the real parser rather than a regex over comment markers is the load-bearing decision. The parser is what correctly reads a `wp:query` containing three nested blocks as one top-level block rather than four. Hand-rolled delimiter matching over nested blocks is precisely the bug class that produced the three shipped comment-stripping incidents. The parser is also already proven against real content: the existing fixture round-trip tests show it reproducing captures from the live site byte-identically.

### Getting the stored text exactly right

The parser exposes no byte offsets (its blocks carry only `blockName`, `attrs`, `innerBlocks`, `innerHTML`, `innerContent`), so the block's text has to come from `serializeBlock`. That is a reconstruction, and reconstruction is not always byte-exact. Measured on 2026-09-12, five of eight non-canonical inputs come back changed:

| Input | Returned as |
|---|---|
| `<!-- wp:heading  {"level":2}  -->` (extra spaces) | spaces normalised to one |
| `{"summary":"caf\u00e9"}` | `{"summary":"café"}` |
| `{"width":33.0}` | `{"width":33}` |
| `{"height":1e3}` | `{"height":1000}` |
| `wp:core/separator` | `wp:separator` |

Canonical WordPress output round-trips exactly, which is why all four real fixtures pass. The exposure is content WordPress's own serialiser did not write: hand-edited markup, older WordPress versions, another tool.

**The resolution is a cursor walk.** Iterate the parsed blocks in order, holding a cursor into the original string. For each block, serialise it and test whether the original continues with exactly those bytes at the cursor. If it does, store `src.slice(cursor, cursor + text.length)`, a literal copy of the original, and advance the cursor. If it does not, fall back to the serialised text for that block alone.

This yields a true byte-for-byte copy in every case where one is obtainable, which on real WordPress content is every case. Attribute values escape `&`, `<`, `>` and `"`, and `getAttribute` returns the original, so storing and reading the text back is lossless with no custom encoding.

**A fallback is not an alarm.** All five divergences above are semantically identical and accepted by WordPress; the `core/` case normalises toward what WordPress itself writes, and Gutenberg validates a block's HTML rather than the formatting of its attribute JSON. Refusing a save over `33.0` becoming `33` would be friction with no safety payoff, and would train the author to click through the alarm, destroying its value for the case that matters. So the fallback is silent, and the five known normalisations are pinned as tests rather than surfaced at runtime.

That gives three distinct outcomes, in decreasing order of how often they occur:

| Outcome | Meaning | Author sees |
|---|---|---|
| Exact slice stored | Perfect preservation | Nothing |
| Serialised fallback stored | Preserved, markup normalised, semantics unchanged | Nothing |
| Block not represented at all | Real loss | The red alarm |

Only top-level blocks need wrapping. Content nested inside a block Quill does not model is already preserved verbatim as part of that block, so the recursion stops at depth one.

This re-hooks **both** `block-parser-bundle.js` and `block-serializer.js`, which were removed from `editor.html` and `build.sh` earlier on 2026-09-12 as unused. The parser enumerates the blocks and the serialiser produces each one's stored text, so both `<script>` tags and both `cp` lines come back. Nothing in the block-model work is test-only after this.

### Where the wrap applies

Four places set editor content. They split on whether the content is `post_content` or the editor's own internal HTML. Getting this wrong is silent, so each gets a test.

| Call site | Content shape | Wrap? |
|---|---|---|
| `window.setContent` (from Swift, on post load) | `post_content` | Yes |
| `_exitCodeView` when the user edited the source | `post_content` | Yes |
| AI reject path, `_aiOriginalHTML` restore (two sites) | `editor.getHTML()`, already wrapped | No |

Missing the code-view case would mean a user's hand-edited Custom HTML block is shredded by their next visual edit.

### Unwrapping

`toWordPressHTML` gains a pass that replaces each wrapper element with its stored source. This runs on the typing debounce, so it must stay cheap: one selector lookup, plus a string substitution per wrapper. On a post with no unsupported blocks the selector matches nothing.

Code view is unaffected and remains the escape hatch. It is built from either the untouched original content or from `toWordPressHTML` output, and the unwrap lives in the latter, so the user sees real `post_content` and never Quill's wrapper.

### How it appears in the editor

The existing `.passthrough-card`, plus a monospace peek at the block's content, truncated. A bare "Custom HTML" or "Shortcode" label cannot be told apart from another of the same type in the same post, and a shortcode's identity is its text. The existing hint line is unchanged: `Not editable in the visual editor; use Code View (</>)`.

## Part 2: The data-loss alarm

### Detection

After load, compare the list of top-level blocks the parser found against the blocks the resulting ProseMirror document can account for. A document accounts for a block in one of two ways: a passthrough node carries the block name on it directly, or a modeled node maps to one through the descriptor registry. Anything in the parser's list with no representative is at risk.

This check is deliberately independent of part 1. It verifies the outcome rather than assuming the wrap worked, so a bug in the wrapper shows up as a red banner instead of silent loss. A check sharing the fix's assumptions would go green in exactly the case it exists to catch.

The alarm fires only on the third outcome in the table above, a block with no representative in the document. It never fires on the serialised fallback, which is preservation, not loss.

Once part 1 is in, this should never fire. It is a tripwire, not a routine notice, and when it fires it is reporting a Quill bug rather than an authoring mistake. The copy says so.

### Reporting and gating

JS posts the at-risk block names to Swift through a new message handler, following the eight that already exist. Swift then:

- Shows the banner in the existing slot under `editorHeader`, where `errorBanner` already appears.
- Refuses to save, as a sibling to the existing `contentLoadFailed` guard in `save(status:force:)`, with the difference that this one can be overridden.
- Suspends autosave while an unacknowledged alarm stands. `performAutosave` writes editor content to the local draft and autosave stores every 30 seconds; left ungated, the squashed version silently becomes the local copy and a later ordinary save publishes it having never warned anyone.

### Banner states

Distinct danger styling, not the amber used for save errors: amber is the weight of "couldn't reach the server," which is recoverable, and this is not. Affected block names are bold. No em dashes in any string.

**1. On open.** Red. Save buttons disabled, autosave suspended.

> **Saving this post would delete content**
> A **Calendar** block didn't survive loading into Quill, so saving from here would remove it from the published post. This is a Quill limitation, not a problem with your post.
> `[Save anyway, I understand]`

**2. After override.** Still red, because still true. Saving unlocked, autosave resumes.

> **Saving will delete a Calendar block**
> You chose to save anyway. Quill won't ask again for this post.

**3. After the save completes.** Grey. The danger has passed; this is now information, and revision history is the one thing that can undo it. Dismissable.

> A **Calendar** block was removed from this post. You can restore it from the post's revision history in WordPress.

**4. Next time the post opens.** No banner. The block is gone from the content, so the check finds nothing missing. The warning ends by becoming untrue rather than by being cleared, so there is no flag to persist and no way for a stale warning to linger.

Two string variants per state, singular and plural, rather than one string with a count interpolated: "it" and "them" differ, and a single-block message reading "1 blocks" is the kind of detail that makes an alarm look untrustworthy at the moment it most needs to be believed.

## Performance

Measured on `fixtures/post-17780.html` (23KB, the real published post), averaged over 200 runs:

| Work | When | Cost |
|---|---|---|
| `BlockParser.parse` | once per post open | 0.032 ms |
| `serializeBlocks` | once per post open | 0.020 ms |
| `toWordPressHTML` (existing) | every debounced edit | 6.368 ms |

The new load-time work is roughly 1/200th of one existing save transform. Parsing is linear and stays negligible at scale: 0.090 ms at 224KB, 0.349 ms at 1.1MB, 1.422 ms at 4.5MB (1201 blocks).

The unwrap added to `toWordPressHTML` cannot be measured before it exists. It is bounded by one selector lookup plus a per-wrapper string substitution, against a transform that already does that shape of work repeatedly. If it measures worse than that, it gets reported rather than shipped quietly.

## Testing

**Round-trip corpus (highest value).** Each block shape from the Problem table becomes a fixture asserted byte-identical through load, edit elsewhere, save. These are the seven cases that currently fail; they are the regression suite for this work.

**Per-block serialisation identity.** Extend the existing fixture suite to assert that each top-level block re-serialises to a substring of its source and that the concatenation equals the file. The whole-file assertion alone would pass even if a single block's text drifted in a way that another block's compensated for, and per-block exactness is what the cursor walk depends on.

**The cursor walk on both paths.** For canonical content, assert every block's stored text is a literal slice of the input. For each of the five non-canonical forms in the table above, assert the fallback engages, the stored text is the serialised form, the result is still semantically equivalent, and no alarm fires. These five cases are the documented normalisations; if a sixth appears later, this is where it gets recorded.

**Entry points.** One test per content-entry site confirming the wrap applies where it should and not where it shouldn't, including the code-view path and both AI restore paths.

**Detection.** The comparison is pure and testable alongside the serializer tests: a post whose blocks all survive reports nothing; a deliberately broken wrap reports the missing block.

**Swift.** The banner strings get unit tests the way the dropped-image upload messages already do (singular vs plural, block names present). The save guard and autosave suspension are testable as view-model logic.

**Manual.** One pass in the real app against a post containing a Custom HTML block, a shortcode and a synced pattern, since jsdom is weaker evidence than WKWebView for anything touching the bridge.

## Risks

**The wrapper fails to unwrap.** Would corrupt content on save. Mitigated by storing a literal slice of the original wherever possible, by the byte-identity corpus, and by the independent detection check, which turns a silent failure into a visible one.

**The serialised fallback engages on content where it is not harmless.** The five known normalisations are safe. A sixth, unknown one might not be. The cursor walk narrows this to blocks whose source is not canonical WordPress output, which on a site's own content should be none, and the fallback is per block rather than per post, so one unusual block cannot pull the rest of the document onto the reconstruction path.

**A block shape nobody anticipated.** The alarm exists for exactly this, which is why it does not share the fix's assumptions.

**Scope of the alarm's authority.** It refuses saves. A false positive therefore blocks legitimate work, which is why it is overridable and why the override is remembered for the session.
