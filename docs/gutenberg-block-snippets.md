# Gutenberg block snippets

Reference markup for WordPress core blocks that don't have a toolbar button in Quill. Paste any of these into Quill's code view (the `</>` toolbar button) to use the block in a post — you're pasting the same HTML WordPress itself would save.

Source: [WordPress Block Editor Handbook — Core Blocks Reference](https://developer.wordpress.org/block-editor/reference-guides/core-blocks/), current as of WordPress 7.0.1.

## How these behave in Quill

None of these have a dedicated toolbar button or visual editing UI in Quill. Once pasted via code view and saved, most will fall through to the `gutenbergPassthrough` node — Quill shows a "Not editable in the visual editor" card and preserves the block byte-for-byte on every save, so it round-trips safely to WordPress even though you can't visually tweak it. To change the content, edit it in code view.

Exceptions worth knowing about:
- **Separator** already has full native support (`withClassAttr(HorizontalRule)`) — it's a real editable node, just with no toolbar button. Typing `---` then Enter also inserts one.
- **Media & Text** renders as a `<figure>` element, which the passthrough node explicitly skips (it only catches non-figure `wp-block-*` elements, to stay out of the way of `ResizableImage`'s own figure parsing) — confirmed working in testing anyway.
- **Pullquote** also renders as a `<figure>`, but this one confirmed *doesn't* survive: the passthrough skip means nothing claims the outer `<figure class="wp-block-pullquote">`, so Tiptap's parser recurses past it and the inner `<blockquote><cite>` matches Quill's own (unscoped) blockquote parse rule instead. The `wp-block-pullquote` wrapper and large-pulled-quote styling are lost — it loads and saves as a plain blockquote+citation. The quote text itself isn't lost, just the pullquote presentation. See `docs/future-architecture.md` (Approach G) for what real support would take.
- **Shortcode** serializes as bare text with no wrapping element at all (see below) — the passthrough node matches on an element's `wp-block-*` class, so there may be nothing for it to catch here either. Untested — treat with the same suspicion as Pullquote until verified.

---

## Pullquote (`core/pullquote`)

Large pulled-out quote, distinct from the blockquote+citation Quill already supports.

**Confirmed: does not round-trip as a pullquote.** It loads and saves as a plain blockquote+citation instead — the `wp-block-pullquote` figure wrapper and large-quote styling are lost. The text content survives, just not the presentation. See `docs/future-architecture.md` (Approach G) if this is ever worth fixing properly.

```html
<!-- wp:pullquote -->
<figure class="wp-block-pullquote">
    <blockquote>
    <p>Testing pullquote block...</p><cite>...with a caption</cite>
    </blockquote>
</figure>
<!-- /wp:pullquote -->
```

## Preformatted (`core/preformatted`)

Plain whitespace-preserving text, no syntax highlighting (unlike Quill's code block).

```html
<!-- wp:preformatted -->
<pre class="wp-block-preformatted">Some <em>preformatted</em> text...<br>And more!</pre>
<!-- /wp:preformatted -->
```

## Details (`core/details`)

Native collapsible disclosure/toggle.

```html
<!-- wp:details {"summary":"Details Summary"} -->
<details class="wp-block-details"><summary>Details Summary</summary>
    <!-- wp:paragraph {"placeholder":"Type / to add a hidden block"} -->
    <p>Details Content</p>
    <!-- /wp:paragraph -->
</details>
<!-- /wp:details -->
```

To have it expanded by default, add `"showContent":true` to the attrs and `open` to the `<details>` tag:

```html
<!-- wp:details {"summary":"Details Summary","showContent":true} -->
<details class="wp-block-details" open><summary>Details Summary</summary>
    <!-- wp:paragraph -->
    <p>Details Content</p>
    <!-- /wp:paragraph -->
</details>
<!-- /wp:details -->
```

## Media & Text (`core/media-text`)

Side-by-side image + text.

```html
<!-- wp:media-text {"mediaType":"image"} -->
<div class="wp-block-media-text is-stacked-on-mobile">
    <figure class="wp-block-media-text__media">
        <img src="https://example.com/image.jpg" alt=""/>
    </figure>
    <div class="wp-block-media-text__content">
        <!-- wp:paragraph {"placeholder":"Content…"} -->
        <p>My Content</p>
        <!-- /wp:paragraph -->
    </div>
</div>
<!-- /wp:media-text -->
```

## Button / Buttons (`core/button`, `core/buttons`)

`core/button` is only ever used inside a `core/buttons` wrapper.

```html
<!-- wp:buttons -->
<div class="wp-block-buttons">
    <!-- wp:button -->
    <div class="wp-block-button"><a class="wp-block-button__link wp-element-button" href="#">My button 1</a></div>
    <!-- /wp:button -->

    <!-- wp:button -->
    <div class="wp-block-button"><a class="wp-block-button__link wp-element-button" href="#">My button 2</a></div>
    <!-- /wp:button -->
</div>
<!-- /wp:buttons -->
```

To center the group and space the buttons, add layout/align attrs:

```html
<!-- wp:buttons {"align":"wide","layout":{"type":"flex","justifyContent":"center"}} -->
<div class="wp-block-buttons alignwide">
```

## Separator (`core/separator`)

Already fully supported by Quill — type `---` then Enter, or paste directly.

```html
<!-- wp:separator -->
<hr class="wp-block-separator has-alpha-channel-opacity"/>
<!-- /wp:separator -->
```

Style variations (`wide` = thicker full-width line, `dots` = "•••"):

```html
<!-- wp:separator {"className":"is-style-wide"} -->
<hr class="wp-block-separator has-alpha-channel-opacity is-style-wide"/>
<!-- /wp:separator -->

<!-- wp:separator {"className":"is-style-dots"} -->
<hr class="wp-block-separator has-alpha-channel-opacity is-style-dots"/>
<!-- /wp:separator -->
```

## Column / Columns (`core/column`, `core/columns`)

```html
<!-- wp:columns -->
<div class="wp-block-columns">
    <!-- wp:column -->
    <div class="wp-block-column">
        <!-- wp:paragraph -->
        <p>Column One</p>
        <!-- /wp:paragraph -->
    </div>
    <!-- /wp:column -->

    <!-- wp:column -->
    <div class="wp-block-column">
        <!-- wp:paragraph -->
        <p>Column Two</p>
        <!-- /wp:paragraph -->
    </div>
    <!-- /wp:column -->
</div>
<!-- /wp:columns -->
```

## Accordion (`core/accordion`, `-item`, `-heading`, `-panel`)

```html
<!-- wp:accordion -->
<div role="group" class="wp-block-accordion">
    <!-- wp:accordion-item -->
    <div class="wp-block-accordion-item">
        <!-- wp:accordion-heading -->
        <h3 class="wp-block-accordion-heading has-icon has-icon-right">
            <button type="button" class="wp-block-accordion-heading__toggle">
                <span class="wp-block-accordion-heading__toggle-title">First Question</span>
                <span class="wp-block-accordion-heading__toggle-icon" aria-hidden="true">+</span>
            </button>
        </h3>
        <!-- /wp:accordion-heading -->
        <!-- wp:accordion-panel -->
        <div role="region" class="wp-block-accordion-panel">
            <!-- wp:paragraph -->
            <p>First answer.</p>
            <!-- /wp:paragraph -->
        </div>
        <!-- /wp:accordion-panel -->
    </div>
    <!-- /wp:accordion-item -->

    <!-- wp:accordion-item -->
    <div class="wp-block-accordion-item">
        <!-- wp:accordion-heading -->
        <h3 class="wp-block-accordion-heading has-icon has-icon-right">
            <button type="button" class="wp-block-accordion-heading__toggle">
                <span class="wp-block-accordion-heading__toggle-title">Second Question</span>
                <span class="wp-block-accordion-heading__toggle-icon" aria-hidden="true">+</span>
            </button>
        </h3>
        <!-- /wp:accordion-heading -->
        <!-- wp:accordion-panel -->
        <div role="region" class="wp-block-accordion-panel">
            <!-- wp:paragraph -->
            <p>Second answer.</p>
            <!-- /wp:paragraph -->
        </div>
        <!-- /wp:accordion-panel -->
    </div>
    <!-- /wp:accordion-item -->
</div>
<!-- /wp:accordion -->
```

## Shortcode (`core/shortcode`)

Bare text between the comment delimiters — no wrapping element.

```html
<!-- wp:shortcode -->
[gallery ids="1,2,3"]
<!-- /wp:shortcode -->
```
