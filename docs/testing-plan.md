# Quill — Test Suite Reference

_Last updated: 2026-09-25 — 470 Swift tests + 1,238 JS tests (1,237 pass, 1 skipped), no failures._

This document is the authoritative reference for Quill's automated test suite and manual testing checklists. It covers how to run every test, what each test covers, and which manual checks to run before a release.

---

## Running the tests

### Full suite (recommended after every code change)

```bash
./test.sh
```

`test.sh` runs both test layers in sequence and prints a pass/fail summary:

1. **Swift tests** — `swift test` (470 tests)
2. **JS block serializer tests** — `node --test Scripts/test-block-serializer.js` (110 tests — pure Node, no DOM)
3. **JS preservation tests** — `node --test Scripts/test-editor-preservation.js` (48 tests — live Tiptap editor in jsdom)
4. **JS editor tests** — `node --test Scripts/test-editor.js` (259 tests via Node's built-in runner + jsdom)
5. **JS editor keyboard tests** — `node --test Scripts/test-editor-keyboard.js` (76 tests — live Tiptap editor in jsdom)
6. **JS gallery tests** — `node --test Scripts/test-editor-gallery.js` (36 tests — live Tiptap editor in jsdom)
7. **JS container tests** — `node --test Scripts/test-editor-containers.js` (275 tests — live Tiptap editor in jsdom)
8. **JS passthrough tests** — `node --test Scripts/test-editor-passthrough.js` (36 tests — live Tiptap editor in jsdom)
9. **JS footnote tests** — `node --test Scripts/test-editor-footnotes.js` (36 tests — live Tiptap editor in jsdom)
10. **JS paste tests** — `node --test Scripts/test-editor-paste.js` (19 tests — live Tiptap editor in jsdom)
11. **JS inline format tests** — `node --test Scripts/test-editor-inline-formats.js` (20 tests — live Tiptap editor in jsdom)
12. **JS settings registry tests** — `node --test Scripts/test-block-settings-registry.js` (13 tests — pure Node)
13. **JS block settings tests** — `node --test Scripts/test-editor-block-settings.js` (227 tests — live Tiptap editor in jsdom)
14. **JS AI output validity tests** — `node --test Scripts/test-ai-output-validity.js` (44 tests — checked by WordPress's own block validator)
15. **JS fixture validity sweep** — `node --test Scripts/test-fixture-validity.js` (30 tests — same validator, over every fixture)

`test.sh` runs them in that order and stops nothing early — every suite runs, and the summary line reports how many of the fifteen passed.

If either layer fails, `test.sh` exits non-zero and reports which suite failed.

### The fixture corpus in real WebKit

```bash
./build.sh
./Quill.app/Contents/MacOS/Quill --check-fixtures "$PWD/Scripts/fixtures"
```

Loads the real `editor.html` in an offscreen WKWebView and runs every
`Scripts/fixtures/settings-*.html` through load → save-untouched → save-after-edit →
save-again, printing a per-fixture report and the first byte of any difference. It
exits non-zero on a mismatch.

**This is the only test that runs in WebKit, and it must be green before a release.**
Every jsdom suite can pass while WebKit does something else: the inline-style
re-serialization bug (hex colours becoming `rgb()`, invalidating every coloured block
in Gutenberg) was green in jsdom the whole time it was shipping, and the attribute
ordering that hid it is WebKit-only. Two earlier WebKit-only failures — the
widget-decoration keystroke drop and the empty-caret `<br>` — have the same shape.

### Run Swift tests only

```bash
swift test
```

### Run one Swift suite

```bash
swift test --filter WordPressClientTests
swift test --filter AIPromptBuilderTests
# etc. — filter matches the @Suite struct name
```

### Run JS editor tests only

```bash
node --test Scripts/test-editor.js
```

`Scripts/test-ai-output-validity.js` additionally needs the pinned `@wordpress/*` dev dependencies (`npm install` in `Scripts/`).

Requires `node` and the `jsdom` package, installed in **`Scripts/`** (`Scripts/package.json` + `Scripts/node_modules/`), not the repo root — the root has no `package.json` at all.

---

## Swift test suite (470 tests, 32 suites)

Two files hold more than one suite: `AIPromptBuilderTests.swift` holds three (`AIPromptBuilderTests`, `EvaluationParserTests`, `EvaluatePostPromptTests`) that the table below groups into one row, and `EditorCoordinatorTests.swift` holds two (`EditorCoordinatorTests`, `EditorPushDecisionTests`), which get a row each.

Framework: `swift-testing`. Target: `Tests/QuillTests/`. Support files: `Tests/QuillTests/Support/`.

### Suite summary

| # | Suite | File | Tests | What it covers |
|---|---|---|---|---|
| 1 | `WPPostDecodingTests` | `WPPostDecodingTests.swift` | 41 | `WPPost` JSON decoding, optional-field defaults, `editorHTML` fallback, wpautop for classic content, HTML entity decoding, `excerptText` plain-text extraction, empty content from `_fields` list fetch, `meta.footnotes` decoding incl. null, non-string and empty-array payloads |
| 2 | `WPMediaDecodingTests` | `WPMediaDecodingTests.swift` | 19 | `WPMedia`/`MediaDetails`/`MediaSize` float-dimensions gotcha, `thumbnailURL` fallback, `sizedURL(for:)` size resolution incl. "full" slug and blank-URL fallback, `caption`/`captionText` plain-text decoding |
| 3 | `PostPayloadTests` | `PostPayloadTests.swift` | 15 | `PostPayload` encoding, scheduling key names, nil omission, footnotes sent under `meta` (and an empty array still sent, so deleting the last note clears it) |
| 4 | `CredentialsTests` | `CredentialsTests.swift` | 4 | `Credentials.basicAuthHeader` base64 encoding |
| 5 | `WordPressClientTests` | `WordPressClientTests.swift` | 58 | URL construction (incl. literal `+` escaped to `%2B` in query values), `_fields` filter, HTTP error mapping (incl. a PHP warning ahead of the JSON explained as a plugin or theme problem), `searchLinks`, auth headers, Content-Disposition escaping, media fetch/upload/delete/alt-text (incl. the `page`/`per_page`/`offset` paging parameters), streaming uploads |
| 6 | `JSONFileStoreTests` | `JSONFileStoreTests.swift` | 8 | Round-trip, chmod 600, atomic write, nil-on-absent |
| 7 | `CredentialsStoreTests` | `CredentialsStoreTests.swift` | 10 | Credentials persistence, `AppSupportDirectory`, `AISettingsStore` |
| 8 | `DraftStoreTests` | `DraftStoreTests.swift` | 19 | Local draft CRUD, ordering, unicode, non-existent ID safety, the `footnotes` column round-trip and erasure |
| 9 | `AutosaveStoreTests` | `AutosaveStoreTests.swift` | 13 | Autosave CRUD, one-per-post, `serverModified`, `savedAt` ordering, footnotes stashed and replaced in step with title and content |
| 10 | `TaxonomyCacheTests` | `TaxonomyCacheTests.swift` | 12 | Category/tag cache, TTL boundary, replace semantics, collision guard |
| 11 | `AppDatabaseTests` | `AppDatabaseTests.swift` | 5 | Migration idempotency, old-schema `type` column backfill, `footnotes` column added to existing drafts and autosaves tables, drafts and autosaves independent |
| 12 | `AIPromptBuilderTests` | `AIPromptBuilderTests.swift` | 86 | `parseGenerateResponse` edge cases (incl. `<cite>` wrapper stripped while inner citation text is preserved, even across a nested inline tag), system prompt, all prompt builders (incl. list/table context with correct `<ul>`/`<ol>` tags, and Make Longer/Shorter word targets tiered at 40 and 150 words), evaluation ANCHOR parsing, style guide injection, typographic entity decoding, content exclusion filters, phantom punctuation-spacing suppression, `cleanOperationResult` fence stripping, and `normalizeAITables` — inline styles stripped from every table tag, core's fixed-layout class added, and the tag match stopping at a word boundary so `<table-of-contents>` is left alone |
| 13 | `AnthropicClientTests` | `AnthropicClientTests.swift` | 21 | Request headers, web search, multi-block joining, error handling (incl. optional `stop_reason` decoding and `AnthropicError.networkError` wrapping with friendly offline messaging) |
| 14 | `PostItemTests` | `AppStateTests.swift` | 11 | `PostItem.id`, `.title`, `.statusBadge`, `.isRemote` computed properties |
| 15 | `SidebarSectionTests` | `AppStateTests.swift` | 8 | `SidebarSection.icon` and `.shortTitle` for all cases |
| 16 | `AppStateLoadingTests` | `AppStateTests.swift` | 2 | `AppState` initial loading flags (`isLoadingList`, `hasLoadedList`, `isLoadingMedia`, `hasLoadedMedia`) |
| 17 | `AppStateFilteredItemsTests` | `AppStateTests.swift` | 10 | `AppState.filteredItems` per section, search filtering |
| 18 | `SectionIsEmptyTests` | `AppStateTests.swift` | 5 | `AppState.sectionIsEmpty` per section |
| 19 | `EditorCoordinatorTests` | `EditorCoordinatorTests.swift` | 12 | `isAllowedExternalURL` URL scheme allowlist; `mediaSizesDict(for:)` size-dict construction incl. "full"-entry fallback; `misspelledWords(in:completion:)` returning on the main actor |
| 20 | `PostEditorHelpersTests` | `PostEditorHelpersTests.swift` | 24 | `previewURL` query/fragment handling; status helpers (`publishButtonTitle`, `toastMessage`, `statusDidChange` for future/private/pending); `PostStats` reading time; dropped-image upload progress/summary message builders |
| 21 | `UpdateCheckerTests` | `UpdateCheckerTests.swift` | 12 | `isNewer` semantic version comparison: major/minor/patch, equal, older, different segment counts, large numbers; `normalizeVersion` tag-prefix stripping |
| 22 | `MimeTypeTests` | `MimeTypeTests.swift` | 12 | `MimeType.forExtension`/`forFile` UTType-backed lookups, case-insensitivity, unknown/empty extension fallback to `application/octet-stream` |
| 23 | `ImageConversionTests` | `ImageConversionTests.swift` | 17 | `ImageConversion.prepareForUpload`/`cleanup`: HEIC/HEIF→JPEG conversion, EXIF orientation and pixel dimensions preserved, per-upload temp directory and its cleanup, pass-through for JPEG/PNG/PDF, fallback to the original when ImageIO cannot decode |
| 24 | `BlockRiskAlarmTests` | `BlockRiskAlarmTests.swift` | 15 | `BlockRiskAlarm`'s three banner stages: title and body copy per stage, singular vs. plural wording, human-readable block display names (incl. Synced Pattern, Page Break, Read More, Custom HTML, and a namespaced third-party block), an em-dash guard across every string in every stage, that only the unacknowledged stage blocks saving, and `PostEditorView.nextAlarm(from:names:)`'s banner lifecycle |
| 25 | `EditorPushDecisionTests` | `EditorCoordinatorTests.swift` | 8 | `EditorPushState`: when a `setContent` push is worth making, keyed on the HTML **and** the footnotes together, and the two half-recording entry points (`recordHTML`, `recordFootnotes`) leaving the other half intact |
| 26 | `AIOutputFixtureTests` | `AIOutputFixtureTests.swift` | 2 | Each `Scripts/fixtures/ai/` sample's `.html` equals what `parseGenerateResponse`/`cleanOperationResult` make of its `.raw.txt` — the Swift half of the AI output validity suite |
| 27 | `MediaFilterTests` | `MediaFilterTests.swift` | 4 | `MediaFilter` → WordPress `media_type` parameter mapping, `matches(_:)` accepting the same set that mapping asks the server for, and that every filter has a title and an icon |
| 28 | `TaxonomyOrderingTests` | `AppStateTests.swift` | 5 | `AppState.categories`/`tags` sort on assignment and stay sorted after `append`; `sortedByName()` is case-insensitive and locale-aware. This is what keeps `PostSettingsPanel` from sorting per render — see `docs/gotchas.md` |
| 29 | `StatusBadgeTests` | `StatusBadgeTests.swift` | 5 | `statusSymbol(_:)` and `Color.statusColor(_:)` cover the same badge set, `local-post`/`local-page` share one pair, and an unknown status falls back rather than crashing |
| 30 | `PostListRowSubtitleTests` | `PostListRowTests.swift` | 7 | `PostListRow.subtitle`/`statusLabel`/`formattedDate`: date·status for posts, bare status for pages, type-named local drafts, unknown statuses capitalised, unparseable dates truncated |

---

### 1. Model decoding — `WPPostDecodingTests` (41 tests)

File: `Tests/QuillTests/WPPostDecodingTests.swift`

Guards the `WPPost` decoding path, which contains `decodeIfPresent` defaults that have caused production bugs. Also covers `editorHTML` wpautop for classic content and `decodingHTMLEntities()` for title display.

| Test | What it checks |
|---|---|
| `fullPostDecodesAllFields` | All standard fields decode from a complete JSON fixture |
| `pageOmittingCategoriesAndTagsDefaultsToEmpty` | Pages endpoint omits `categories`/`tags` → both default to `[]` without throwing |
| `missingTypeDefaultsToPost` | `type` absent → `"post"` |
| `missingFeaturedMediaDefaultsToZero` | `featured_media` absent → `0` |
| `missingDateGmtDefaultsToEmptyString` | `date_gmt` absent → `""` |
| `missingParentDefaultsToZero` | `parent` absent → `0` |
| `missingCommentStatusDefaultsToOpen` | `comment_status` absent → `"open"` |
| `contentRawPreferredOverRendered` | `content.raw` decoded when present; `editorHTML` returns `raw` |
| `emptyContentRawFallsBackToRenderedForEditorHTML` | `raw == ""` → `editorHTML` returns `rendered` |
| `whitespaceContentRawFallsBackToRenderedForEditorHTML` | `raw == "\n  "` → `editorHTML` returns `rendered` |
| `missingRequiredFieldThrows` | Omitting `id` → decoding throws (required field guard) |
| `futureStatusDecodes` | `status: "future"` decodes without error |
| `classicContentGetsWpautop` | Double-newline classic content → `<p>` wrapped paragraphs |
| `classicContentSingleNewlineBecomesBr` | Single newline → `<br />` within paragraph |
| `classicContentWithInlineHTML` | Inline HTML (`<a>`, `<strong>`) preserved inside `<p>` wrapping |
| `classicContentBlockElementNotWrapped` | Block elements (`<blockquote>`) not double-wrapped in `<p>` |
| `gutenbergContentUnchanged` | Content with `<!-- wp:` comments passed through unchanged |
| `classOnlyGutenbergBlockContentUnchanged` | Content consisting entirely of an unmodeled Gutenberg block (`wp-block-*` class, no `<!-- wp:` comment, no `<p>` tag — `gutenbergPassthrough`'s target case) is not misclassified as classic content and run through `wpautop()`, which would corrupt it before the JS-side parser ever sees it |
| `contentWithParagraphTagsUnchanged` | Content already containing `<p>` tags not re-wrapped |
| `classicContentShortcodePreserved` | WordPress shortcodes preserved inside `<p>` wrapping |
| `classicContentListNotCorrupted` | `<ul>/<li>` not wrapped in `<p>` or injected with `<br>` |
| `classicContentListWithAttributes` | `<ol start="3">` attributes preserved through wpautop |
| `classicExcerptGetsWpautop` | Classic excerpt (no `<p>`, no block comments) gets wpautop |
| `decodesNumericEntities` | `&#8217;` → `'` (right single quotation mark) |
| `decodesHexEntities` | `&#x26;` → `&` |
| `decodesNamedEntities` | `&ldquo;`, `&rdquo;`, `&amp;`, `&lt;`, `&gt;` decode correctly |
| `noEntitiesPassthrough` | Plain text without entities passes through unchanged |
| `decodesMultipleMixed` | Multiple numeric and named entities in one string |
| `excerptTextReturnsRawStrippingHTML` | `excerptText` strips HTML from `raw`, ignores `rendered` |
| `excerptTextReturnsEmptyWhenRawEmpty` | `raw == ""` → `excerptText` returns `""` (no fallback to auto-generated `rendered`) |
| `excerptTextReturnsEmptyWhenRawNil` | `raw == nil` → `excerptText` returns `""` |
| `excerptTextDecodesEntities` | `excerptText` decodes HTML entities (e.g. `&#8217;` → `'`) |
| `missingContentAndExcerptDefaultToEmpty` | No `content`/`excerpt` keys (list fetch with `_fields`) → both default to empty `RenderedString` without throwing |
| `blockGalleryContentSurvivesEditorHTML` | `raw` content containing real `<!-- wp:gallery -->`/`<!-- wp:image -->` block comments survives `editorHTML` unchanged (regression guard — `wpautop`'s classic-content detection must never touch content that already has `<!-- wp:` comments) |
| `footnotesMetaDecodes` | `meta.footnotes` (the JSON string WordPress stores footnote bodies in) decodes onto `WPPost.footnotes` |
| `absentMetaLeavesFootnotesEmpty` | No `meta` key at all → `footnotes` is `""`, not a decode failure |
| `metaWithoutFootnotesKeyLeavesFootnotesEmpty` | A `meta` object with other keys but no `footnotes` → `""` |
| `metaAsAnEmptyArrayStillDecodesTheWholePost` | WordPress sends `meta: []` (an empty PHP array serializes as a JSON array, not an object) → the rest of the post still decodes |
| `nullFootnotesMetaDecodesAsEmpty` | `meta.footnotes: null` → `""` |
| `nonStringFootnotesMetaDoesNotFailTheDecode` | `meta.footnotes` of the wrong type → `""`, and the post still decodes |
| `footnotesJSONSurvivesDecodingByteForByte` | The footnotes JSON string is not re-encoded or re-escaped on the way through |

---

### 2. Model decoding — `WPMediaDecodingTests` (19 tests)

File: `Tests/QuillTests/WPMediaDecodingTests.swift`

Guards the float-dimensions gotcha: WordPress returns `width`/`height` as JSON floats (`2560.0`) which Swift's `Int` decoder rejects without the try-Int-then-Double fallback. Also covers `altText`, `thumbnailURL`, `sizedURL(for:)`, and `caption`/`captionText` (which seed the gallery sheet's per-image Alt text and Caption fields).

| Test | What it checks |
|---|---|
| `integerDimensionsDecode` | `"width": 2560` → `Int` |
| `floatDimensionsDecodeToInt` | `"width": 2560.0` → `Int` via the fallback path (regression guard) |
| `missingMediaDetailsIsNil` | `media_details` absent → `nil`, no throw |
| `missingTitleDefaultsToEmpty` | `title` absent → empty `RenderedString` |
| `sizesMapDecodes` | `sizes` dict with named sizes → `[String: MediaSize]` |
| `sizesDimensionsAsFloatsDecode` | Float `width`/`height` inside `sizes` entries also decode |
| `malformedSizesDoesNotCrash` | `sizes: []` (wrong type) → `try?` swallows it, whole `WPMedia` still decodes |
| `altTextDecodesFromAltText` | `alt_text` key → `altText` property |
| `missingAltTextDefaultsToEmpty` | `alt_text` absent → `""` |
| `thumbnailURLUsesThumbnailSizeWhenPresent` | `sizes["thumbnail"].source_url` present → `thumbnailURL` returns it, not `sourceURL` |
| `thumbnailURLFallsBackToSourceURLWhenNoThumbnailSize` | No `media_details` → `thumbnailURL` returns `sourceURL` |
| `sizedURLUsesMatchingSizeWhenPresent` | `sizedURL(for: "medium")` returns that size's `source_url` when present |
| `sizedURLFallsBackToSourceURLWhenSizeMissing` | Requested slug absent from `sizes` → falls back to `sourceURL` |
| `sizedURLFallsBackToSourceURLWhenMatchedSizeHasBlankURL` | Matched size entry exists but its `source_url` is `""` → falls back to `sourceURL` (regression: a bare `??` on the optional chain would not catch this, since `""` is non-nil) |
| `sizedURLAlwaysUsesSourceURLForFullSlugEvenWhenAFullSizeEntryExists` | `sizedURL(for: "full")` always returns `sourceURL`, ignoring any `sizes["full"]` entry |
| `captionDecodesPlainTextFromRaw` | `caption.raw` present → `captionText` returns the raw string, not the `<p>`-wrapped `rendered` one |
| `captionRawHasHTMLStrippedAndEntitiesDecoded` | `caption.raw` with markup/entities (`Bob &amp; <em>Alice</em>`) → `"Bob & Alice"` via `RenderedString.excerptText` |
| `captionWithOnlyRenderedYieldsEmptyText` | Rendered-only payload (no `raw`, the shape a non-`context=edit` fetch returns) → `caption != nil` but `captionText == ""`, so the sheet never prefills a field with HTML |
| `missingCaptionIsNilAndTextIsEmpty` | `caption` absent → `caption == nil`, `captionText == ""`, no throw |

---

### 3. Model encoding — `PostPayloadTests` (15 tests)

File: `Tests/QuillTests/PostPayloadTests.swift`

Guards `PostPayload` encoding — encoding bugs corrupt published content silently. Tests decode the emitted JSON back into a dictionary to assert key names and presence.

| Test | What it checks |
|---|---|
| `schedulingUsesDateGmtKeyNotDate` | Scheduling uses key `date_gmt`, never `date` (scheduling gotcha) |
| `nilDateGmtOmitsKeyFromJSON` | `dateGmt: nil` → key absent from JSON |
| `nilSlugOmitsKeyFromJSON` | `slug: nil` → key absent (preserves server value on update) |
| `nonEmptySlugIncludedInJSON` | Non-nil slug → key present |
| `nilFeaturedMediaOmitsKey` | `featuredMedia: nil` → `featured_media` absent |
| `featuredMediaIncludedWhenSet` | Non-nil `featuredMedia` → key present |
| `nilParentOmitsKey` | `parent: nil` → key absent (posts have no parent) |
| `parentIncludedForPages` | `parent: 5` → key present (pages can have parent) |
| `emptyCategoriesAndTagsEncodeAsEmptyArrays` | `[]` → still encodes as `[]`, not omitted |
| `categoriesAndTagsPopulated` | Non-empty arrays encode correctly |
| `codingKeyNamesAreCorrect` | `featured_media`, `comment_status`, `date_gmt` exact key names asserted |
| `footnotesAreSentUnderMeta` | Footnotes go out as `meta.footnotes`, where `core/footnotes` reads them |
| `nilFootnotesOmitsMetaEntirely` | `footnotes: nil` → no `meta` key at all, so a post with no notes does not touch the field |
| `emptyFootnotesStillSendsMetaSoDeletingTheLastOneClearsIt` | `[]` is sent rather than omitted — omitting it would leave the last deleted note on the server |
| `everyOtherFieldStillEncodesAlongsideMeta` | Adding `meta` does not displace any existing key |

---

### 4. Auth — `CredentialsTests` (4 tests)

File: `Tests/QuillTests/CredentialsTests.swift`

| Test | What it checks |
|---|---|
| `basicAuthHeaderKnownVector` | `user:pass` → exact base64 `"Basic dXNlcjpwYXNz"` |
| `appPasswordWithSpacesEncodedVerbatim` | Spaces in WordPress app passwords encoded as-is, not stripped |
| `basicAuthHeaderHasCorrectPrefix` | Header starts with `"Basic "` |
| `unicodeUsernameEncodedAsUTF8` | Non-ASCII username encoded via UTF-8 bytes |

---

### 5. Networking — `WordPressClientTests` (58 tests)

File: `Tests/QuillTests/WordPressClientTests.swift`
Support: `Tests/QuillTests/Support/MockURLProtocol.swift`

`@Suite(.serialized)` — runs sequentially because `MockURLProtocol.requestHandler` is a shared static. Uses `URLSessionConfiguration.ephemeral` with `MockURLProtocol` as the protocol class.

#### URL & request construction (15 tests)

| Test | What it checks |
|---|---|
| `fetchPostsDecodesList` | `fetchPosts` decodes a list of posts |
| `fetchPostsIncludesRequiredQueryParams` | `per_page`, `page`, `context=edit`, `status=…` all present |
| `createPostUsesPostMethodWithJsonContentType` | `POST /posts`, `Content-Type: application/json` |
| `updatePostUsesPutMethodOnPostsId` | `PUT /posts/{id}` |
| `createPageUsesPostMethodOnPagesEndpoint` | `POST /pages` |
| `updatePageUsesPutMethodOnPagesId` | `PUT /pages/{id}` |
| `authorizationHeaderIncludedInRequests` | `Authorization: Basic …` on all requests |
| `requestsAcceptJSONSoWordPressHidesPHPWarnings` | `Accept: application/json` on GET and upload requests, so a site with `WP_DEBUG_DISPLAY` on keeps PHP warnings out of the body |
| `uploadMediaSetsContentTypeFromMimeType` | `Content-Type` matches passed mime type |
| `uploadMediaSetsContentDispositionWithFilename` | `Content-Disposition` includes `filename="…"` |
| `uploadMediaSpacesInFilenameArePercentEncoded` | Spaces in filenames percent-encoded in `filename*` part |
| `contentDispositionFallbackPassesThroughNormalFilename` | Plain filename unchanged in quoted fallback |
| `contentDispositionFallbackEscapesDoubleQuote` | `"` → `\"` in quoted fallback |
| `contentDispositionFallbackEscapesBackslash` | `\` → `\\` in quoted fallback |
| `contentDispositionFallbackStripsNewlines` | Newlines removed from quoted fallback |
| `contentDispositionFallbackStripsControlCharacters` | Control chars (< 32) removed from quoted fallback |
| `contentDispositionFallbackPreservesUnicode` | Unicode (e.g. `café.jpg`) passes through unchanged |
| `uploadMediaEscapesQuotesInContentDispositionFilename` | End-to-end: quoted filename with `"` produces valid `Content-Disposition` header |
| `uploadMediaStreamsFromFileNotHttpBody` | `uploadMedia(fileURL:)` uses `URLSession.upload(fromFile:)`, not `httpBody` (streaming regression guard) |
| `fetchMediaItemHitsCorrectEndpointWithEditContext` | `GET /media/{id}?context=edit`, returns decoded `WPMedia` |
| `fetchMediaSendsTheRequestedPageAndPageSize` | `page`, `per_page` and `media_type` parsed back out of the query with `URLComponents` — `GallerySheet.loadMoreMedia` loops until a page holds an image, so a dropped page parameter never terminates |
| `fetchMediaOmitsOffsetUnlessAsked` | no `offset` key unless one is passed; a passed offset reaches the query beside `per_page` — the paging mode `MediaLibraryView` depends on |
| `updateMediaAltTextSendsPostToMediaEndpoint` | `POST /media/{id}` with `application/json` |
| `updateMediaAltTextBodyContainsAltText` | Request body has `{"alt_text":"…"}` |
| `updateMediaAltTextReturnsDecodedMedia` | Response decoded into `WPMedia` |
| `deleteMediaSendsDeleteWithForceTrueQuery` | `DELETE /media/{id}?force=true` (permanent — vs trash's `force=false`) |
| `createAutosaveSendsToPostAutosavesEndpoint` | `POST /posts/{id}/autosaves` |
| `createPageAutosaveSendsToPageAutosavesEndpoint` | `POST /pages/{id}/autosaves` |
| `fetchAllPostsRequestIncludesFieldsFilter` | `fetchAllPosts` query includes `_fields=` (list fetch omits content body) |
| `fetchPostRequestOmitsFieldsFilter` | `fetchPost` has no `_fields=` (full content required for editor) |

#### Taxonomy (6 tests)

| Test | What it checks |
|---|---|
| `fetchAllCategoriesHitsCategoriesEndpointWithPerPage100` | `per_page=100` |
| `fetchAllCategoriesPaginatesAcrossMultiplePages` | Follows `X-WP-TotalPages` to page 2 |
| `fetchAllTagsHitsTagsEndpointWithPerPage100` | `/tags` endpoint |
| `fetchAllTagsPaginatesAcrossMultiplePages` | Tags pagination |
| `createCategoryUsesPostMethodOnCategoriesEndpoint` | `POST /categories` with `{"name":…}` |
| `createTagUsesPostMethodOnTagsEndpoint` | `POST /tags` with `{"name":…}` |

#### Error mapping (8 tests)

| Test | What it checks |
|---|---|
| `fetchPostsThrowsOnHTTPError` | Non-2xx → `APIError.httpError` |
| `trashPostThrowsOnHTTPError` | DELETE non-2xx → error |
| `httpErrorPreservesStatusCode` | Status code in `APIError.httpError(statusCode:body:)` |
| `httpErrorPreservesBodyString` | Body string preserved in error |
| `nonUtf8ResponseBodyBecomesEmptyString` | Non-UTF8 body → `body = ""`, no crash |
| `successWithMalformedJsonThrowsDecodingError` | 200 + garbage JSON → `APIError.decodingError` (not `httpError`) |
| `phpWarningAheadOfJSONExplainsThePluginCause` | 200 + a PHP `Deprecated:` line ahead of the JSON → `APIError.decodingError` whose message says a plugin or theme may be adding text to the reply |
| `networkFailureThrowsNetworkError` | `URLError` from mock → `APIError.networkError` |

#### Cancellation (1 test)

| Test | What it checks |
|---|---|
| `urlErrorCancelledRethrowsAsCancellationError` | `URLError(.cancelled)` → `CancellationError`, not wrapped in `APIError.networkError` |

#### Trash (2 tests)

| Test | What it checks |
|---|---|
| `trashPostSendsDeleteRequest` | `DELETE /posts/{id}?force=false` (recoverable) |
| `trashPageSendsDeleteRequest` | `DELETE /pages/{id}?force=false` |

#### `searchLinks` (8 tests)

| Test | What it checks |
|---|---|
| `searchLinksReturnsMergedResults` | All three sub-requests succeed → merged list |
| `searchLinksIgnoresSubrequestFailures` | Media/term failure → others still returned |
| `searchLinksAllSubrequestsFailReturnsEmptyArray` | All fail → `[]`, no throw |
| `searchLinksPostsFailWhileTermsSucceed` | Posts sub-request fails → terms/media still returned |
| `searchLinksPageSubtypeMapsToPageType` | `subtype == "page"` → `.page` result type |
| `searchLinksTagSubtypeMapsToTagType` | `subtype == "tag"` → `.tag` result type |
| `searchLinksUnknownTermSubtypeFallsToCategory` | Unknown term subtype → `.category` |
| `searchQueryPlusCharacterIsPercentEscaped` | A `+` in the search term is escaped to `%2B` in the query string (WordPress/PHP decodes a literal `+` as a space) |

---

### 6. Storage — `JSONFileStoreTests` (8 tests)

File: `Tests/QuillTests/JSONFileStoreTests.swift`

Tests use an `in: baseDirectory` parameter pointing to a per-test temp dir — fully isolated, no global state.

| Test | What it checks |
|---|---|
| `roundTrip` | `save` → `load` returns equal value |
| `loadReturnsNilWhenAbsent` | No file → `nil`, no throw |
| `deleteRemovesFile` | File gone after `delete()` |
| `deleteWhenAbsentDoesNotThrow` | `delete()` on missing file is a no-op |
| `overwriteKeepsLatestValue` | Save twice → one file with the latest value |
| `savedFileHasChmod600` | Posix permissions after save are `0o600` (security regression guard) |
| `decodeFailureThrows` | Malformed JSON on disk → `load()` throws |
| `distinctFilenamesDontCollide` | Two stores with different names are independent |

---

### 7. Storage — `CredentialsStoreTests` (10 tests)

File: `Tests/QuillTests/CredentialsStoreTests.swift`

`@Suite(.serialized)` — uses `AppSupportDirectory.override` (a global) so only one test at a time writes to the temp dir. Override is set in `init` and cleared in `deinit`.

#### `CredentialsStore` / credentials (3 tests)

| Test | What it checks |
|---|---|
| `saveAndLoad` | Credentials round-trip through `CredentialsStore` |
| `loadReturnsNilWhenEmpty` | No stored creds → `nil` |
| `deleteRemovesCredentials` | Credentials gone after delete |

#### `AppSupportDirectory` (4 tests)

| Test | What it checks |
|---|---|
| `appSupportDirectoryCreatesDir` | `directory()` creates the dir and returns it |
| `appSupportDirectoryIsIdempotent` | Calling `directory()` twice doesn't error |
| `appSupportFileURLJoinsCorrectly` | `fileURL(name:)` appends the name to the dir path |
| `appSupportOverrideKeepsFilesInTempDir` | With override set, no files created under real `~/Library/Application Support/Quill` |

#### `AISettingsStore` (3 tests)

| Test | What it checks |
|---|---|
| `aiSettingsRoundTrip` | Full `AISettings` (apiKey, styleGuide, samplePostIDs, siteURL) round-trips |
| `aiSettingsLoadReturnsNilWhenAbsent` | No file → `nil` |
| `aiSettingsDeleteRemovesSettings` | File gone after delete |

---

### 8. Storage — `DraftStoreTests` (19 tests)

File: `Tests/QuillTests/DraftStoreTests.swift`

Uses `AppDatabase.inMemory()` — each test gets an isolated DB.

| Test | What it checks |
|---|---|
| `createAndFetch` | Create → `fetchAll` returns it |
| `createPageDraft` | `type: "page"` stored correctly |
| `fetchAllPreservesType` | Multiple types returned with correct type field |
| `update` | Updated title/content reflected on next fetch |
| `delete` | Draft gone after delete |
| `loadByIdReturnsNilForUnknownId` | Unknown id → `nil` |
| `loadByIdReturnsCorrectDraft` | Correct draft by id |
| `loadByIdReflectsUpdates` | Load after update returns new content |
| `emptyTitleAndContentRoundTrip` | Blank strings store and load correctly |
| `updateNonExistentIdDoesNotThrow` | Update on missing id → no-op |
| `deleteNonExistentIdDoesNotThrow` | Delete on missing id → no-op |
| `fetchAllOrderedByUpdatedAtDesc` | Most recently updated sorts first |
| `unicodeAndEmojiRoundTrip` | Non-ASCII text, emoji, curly quotes preserved byte-exact |
| `footnotesSurviveCreateAndLoad` | The `footnotes` column round-trips on create → load |
| `updateReplacesFootnotes` | An update writes the new footnotes, not a merge of old and new |
| `draftCreatedWithoutFootnotesReadsBackEmpty` | A draft saved with no notes reads back `""`, never `nil`-shaped garbage |
| `fetchAllCarriesFootnotes` | The list fetch carries footnotes too, so switching posts does not drop them |
| `updateWithoutFootnotesErasesThem` | Saving a draft whose notes were all deleted clears the column |
| `footnotesSurviveAnEditThatOnlyChangesTheContent` | Editing only the body leaves the stored notes intact |

---

### 9. Storage — `AutosaveStoreTests` (13 tests)

File: `Tests/QuillTests/AutosaveStoreTests.swift`

Uses `AppDatabase.inMemory()`.

| Test | What it checks |
|---|---|
| `saveAndLoad` | Autosave round-trip |
| `loadReturnsNilForUnknownPost` | Unknown post id → `nil` |
| `saveOverwritesExisting` | Second save for same post replaces first (one row per post) |
| `deleteRemovesAutosave` | Gone after delete |
| `deleteOnMissingPostIDDoesNotThrow` | Delete on unknown id → no-op |
| `oneSavePerPostID` | Save twice for same id → exactly one row |
| `serverModifiedPreservedExactly` | `serverModified` timestamp stored and returned intact |
| `laterSaveHasNewerSavedAt` | `savedAt` on second save is ≥ first |
| `footnotesSurviveTheStash` | Footnotes round-trip through an autosave |
| `omittedFootnotesDefaultToEmpty` | An autosave written with no notes reads back `""` |
| `resavingWithoutFootnotesErasesThem` | A later autosave with no notes clears the stored ones |
| `replacingAnAutosaveKeepsTitleContentAndFootnotesInStep` | The three fields are replaced together, so a restore can never mix an old body with new notes |
| `deletingTheLastFootnoteStoresAnEmptyArrayNotAnEmptyString` | Deleting the last note stores `[]`, which is what clears the post meta on the next save |

---

### 10. Storage — `TaxonomyCacheTests` (12 tests)

File: `Tests/QuillTests/TaxonomyCacheTests.swift`

Uses `AppDatabase.inMemory()`.

| Test | What it checks |
|---|---|
| `saveAndLoadCategories` | Category list round-trip |
| `staleAfterTTL` | Cache is stale after 25h |
| `freshWithinTTL` | Cache is fresh within 24h |
| `saveAndLoadTags` | Tag list round-trip |
| `staleTagsAfterTTL` | Tags stale after TTL |
| `freshTagsWithinTTL` | Tags fresh within TTL |
| `staleJustAfterTTLBoundary` | Stale at exactly 24h01m |
| `freshJustBeforeTTLBoundary` | Fresh at exactly 23h59m |
| `saveCategoriesReplacesAll` | Save `[1,2]` then `[2,3]` → only `[2,3]` remain (full replace, not merge) |
| `categoryAndTagWithSameIDCoexist` | Category wp_id=1 and tag wp_id=1 don't collide (type is part of PK) |
| `saveEmptyCategoriesYieldsEmptyLoad` | `save([])` → `load()` returns `[]` |
| `isStaleWhenNoDataExists` | No data ever saved → `isStale` returns `true` |

---

### 11. Storage — `AppDatabaseTests` (5 tests)

File: `Tests/QuillTests/AppDatabaseTests.swift`

| Test | What it checks |
|---|---|
| `migrationIsIdempotent` | Running `migrate()` twice on same schema doesn't throw |
| `typeColumnMigratedFromOldSchema` | Old DB (without `type` column) → migrate adds it; existing rows default to `"post"` |
| `footnotesColumnMigratedOntoAnExistingDraftsTable` | A drafts table created before footnotes existed gains the column on migrate, with existing rows readable |
| `footnotesColumnMigratedOntoAnExistingAutosavesTable` | Same for the autosaves table |
| `draftAndAutosaveFootnotesAreIndependent` | The two tables' footnotes do not bleed into each other |

---

### 12. AI — `AIPromptBuilderTests` (86 tests)

File: `Tests/QuillTests/AIPromptBuilderTests.swift`

Pure function tests — no network, no async. `parseGenerateResponse` has been patched twice for real production bugs; these tests pin every edge case.

#### `parseGenerateResponse` (14 tests)

| Test | What it checks |
|---|---|
| `happyPathParsesCorrectly` | Standard `TITLE:…CONTENT:…` structure |
| `markdownFencesStripped` | ` ```html … ``` ` fences removed before parsing |
| `webSearchPreambleGluedDirectlyToTitle` | Preamble text joined to `TITLE:` without newline still parsed (uses `range(of:)`, not `hasPrefix`) |
| `caseInsensitiveMarkers` | `title:`/`content:` lowercase → still parsed |
| `missingTitleMarkerReturnsNil` | No `TITLE:` → `nil` |
| `missingContentMarkerReturnsNil` | No `CONTENT:` → `nil` |
| `emptyTitleReturnsNil` | `TITLE:` with no text → `nil` |
| `emptyContentReturnsNil` | `CONTENT:` with no text → `nil` |
| `titleIsTrimmed` | Leading/trailing whitespace stripped from title |
| `contentIsTrimmerd` | Content trimmed via `whitespacesAndNewlines` |
| `contentMarkerScopedAfterTitleMarker` | Stray `CONTENT:` before `TITLE:` doesn't fool parser |
| `citeTagWrapperStrippedButTextKept` | `<cite index="…">…</cite>` wrapper from web search citations is removed but the sentence inside it is kept in the generated HTML |
| `citeTagWithNestedInlineTagStillStripped` | A citation wrapping a nested inline tag (e.g. `<a>`) still has its `<cite>` wrapper stripped — regression guard for the `[^<]*` capture group that used to fail to match (and therefore fail to strip) any citation containing markup |
| `emptyCiteTagRemovedEntirely` | An empty `<cite>` tag is removed with no leftover text |

#### `systemPrompt` (3 tests)

| Test | What it checks |
|---|---|
| `systemPromptWithoutStyleGuide` | `nil` guide → no style block |
| `systemPromptWithEmptyStyleGuideExcludesStyleBlock` | Empty string guide → same as nil |
| `systemPromptWithStyleGuideIncludesIt` | Non-empty guide appended to prompt |

#### `generatePostPrompt` & `operationPrompt` (21 tests)

| Test | What it checks |
|---|---|
| `generatePostPromptNamesHTMLElements` | Prompt contains `<h2>`, `<h3>`, `<p>`, `<ul>`, `<li>` (prevents headings-only-p regression) |
| `generatePostPromptIncludesUserPrompt` | User's prompt string embedded |
| `operationPromptIncludesSelectedHTML` | Selected HTML embedded after "Content to transform:" |
| `makeLongerInstructionPresent` | "longer" in `makeLonger` operation prompt |
| `makeShorterInstructionPresent` | "shorter" in `makeShorter` operation prompt |
| `convertToTableMentionsTableTags` | Table-related tags in `convertToTable` prompt |
| `convertToListMentionsListTags` | List-related tags in `convertToList` prompt |
| `makeLongerWithBulletListContextUsesUlTag` | `context: "bulletList"` → list-specific expansion prompt with `<ul>` |
| `makeLongerWithOrderedListContextUsesOlTag` | `context: "orderedList"` → list-specific expansion prompt with `<ol>` (not `<ul>`) |
| `makeShorterWithOrderedListContextUsesOlTag` | `context: "orderedList"` → list-specific condensation prompt with `<ol>` |
| `makeShorterWithBulletListContextUsesUlTag` | `context: "bulletList"` → list-specific condensation prompt with `<ul>` |
| `makeLongerWithTableContextUsesTableInstruction` | `context: "table"` → table cell expansion prompt |
| `makeShorterWithTableContextUsesTableInstruction` | `context: "table"` → table cell condensation prompt |
| `operationPromptWithNilContextUsesDefaultInstruction` | `context: nil` → default "expand this content" (not list/table-specific) |
| `makeLongerStatesWordTargetFromSelection` | A 5-word selection gets "from 5 words to about 20 words", a ceiling of 25, and an instruction to keep the same number of paragraphs |
| `makeLongerScalesDownForLongerSelections` | 100 words → about 200 (ceiling 250); 200 words → about 300 (ceiling 400) |
| `makeShorterScalesUpForLongerSelections` | 10 words → about 7 (ceiling 8); 100 → about 50 (ceiling 60); 200 → about 80 (ceiling 100), keeping the paragraph count |
| `lengthTiersSwitchAtFortyAndAfterOneHundredFiftyWords` | Make Longer/Shorter word targets at 39, 40, 150 and 151 words: under 40 words longer is ×4 and shorter ×0.7; 40–150 is ×2 and ×0.5; over 150 is ×1.5 and ×0.4, each with a hard ceiling |
| `makeShorterNeverTargetsZeroWords` | A one-word selection gets a Make Shorter target of 1 word, not 0 |
| `wordTargetCountsWordsAcrossParagraphBreaks` | Words split by `\n` and `\n\n` are counted separately (4 words, not 2) |
| `listAndTableContextsGetNoWordTarget` | `bulletList`, `orderedList` and `table` contexts get no word target for either operation |

#### `styleGuideGenerationPrompt` (3 tests)

| Test | What it checks |
|---|---|
| `styleGuidePromptNumbersSamples` | `--- Sample 1 ---` / `--- Sample 2 ---` numbering |
| `styleGuidePromptWithEmptySamples` | 0 samples → no crash, empty content |
| `styleGuidePromptWordLimit` | 150-word limit mentioned in prompt |

#### `parseEvaluationResponse` (15 tests)

| Test | What it checks |
|---|---|
| `happyPathTwoFindings` | Standard format parsed to `EvaluationResult` with 2 findings |
| `emptyFindingsReturnsResultWithNoFindings` | Empty `FINDINGS:` block → result with 0 findings, not nil |
| `missingSummaryMarkerReturnsNil` | No `SUMMARY:` → `nil` |
| `missingFindingsMarkerReturnsNil` | No `FINDINGS:` → `nil` |
| `emptySummaryReturnsNil` | `SUMMARY:` with no text → `nil` |
| `caseInsensitiveMarkers` | `summary:` / `findings:` lowercase accepted |
| `findingWithoutSuggestionHasNilSuggestion` | Omitting `SUGGESTION` field → `finding.suggestion == nil` |
| `findingWithEmptySuggestionFieldHasNilSuggestion` | `SUGGESTION:` with no text → `nil` |
| `nonQuoteLinesBetweenFindingsAreSkipped` | Non-`QUOTE:` lines between findings ignored |
| `findingsMarkerScopedAfterSummaryMarker` | Stray `FINDINGS:` before `SUMMARY:` not used as real marker |
| `anchorFieldIsParsedIntoFinding` | Full `ANCHOR:` field parsed into `finding.anchor` |
| `anchorFieldIsNilWhenOmitted` | No `ANCHOR:` field → `finding.anchor == nil` |
| `anchorFieldStripsOuterQuotes` | Surrounding `"` stripped from ANCHOR value |
| `anchorFieldEmptyStringBecomesNil` | `ANCHOR: ""` → `nil` (not empty string) |
| `anchorFieldCaseInsensitivePrefix` | Lowercase `anchor:` accepted |

#### `evaluatePostPrompt` (15 tests)

| Test | What it checks |
|---|---|
| `promptIncludesTitle` | Post title embedded in prompt |
| `promptStripsHTMLTags` | HTML removed, text content preserved |
| `promptDecodesHTMLEntities` | `&amp;` / `&lt;` / `&gt;` decoded |
| `promptDecodesSmartQuoteEntities` | `&ldquo;` / `&rdquo;` / `&rsquo;` decoded to Unicode typography chars |
| `promptDecodesTypographicDashAndEllipsis` | `&ndash;` / `&mdash;` / `&hellip;` decoded |
| `promptNamesAllFiveCategories` | Grammar, Clarity, Readability, Wordiness, Tone all named |
| `promptIncludesSummaryAndFindingsFormatInstructions` | `SUMMARY:` / `FINDINGS:` / `QUOTE:` / `ISSUE:` format spec present |
| `promptIncludesAnchorFormatSpec` | `ANCHOR:` format instruction present |
| `promptIncludesStyleGuideWhenProvided` | Non-nil guide embedded with "established writing style" framing |
| `promptOmitsStyleGuideBlockWhenNil` | `nil` guide → no style block in prompt |
| `promptOmitsStyleGuideBlockWhenEmpty` | Empty string guide → no style block |
| `promptExcludesImageCaptionText` | Image caption text excluded from the content sent to Claude |
| `promptExcludesCodeBlockContent` | Code block content excluded from the content sent to Claude |
| `promptExcludesEmbedFigureContent` | Embed figure content excluded from the content sent to Claude |
| `promptExcludesFootnoteMarkersAndBackrefs` | Footnote markers and backref links excluded from content sent to Claude |
| `promptDoesNotInjectSpaceBeforePunctuationAfterInlineTags` | Inline tags (`<a>`) followed by commas don't leave phantom spaces in stripped text |
| `promptStripsSpaceBeforeClosingPunctuation` | Phantom spaces before `;`, `)`, `!`, etc. from inline tag stripping are removed |

#### `cleanOperationResult` & `normalizeAITables` (13 tests)

Claude writes tables with inline styles and no class; Gutenberg's `core/table` draws neither, so the block fails validation the moment it is saved. These pin the cleanup that runs on every AI result before it reaches the editor.

| Test | What it checks |
|---|---|
| `cleanOperationResultStripsFencesAndTrims` | ` ```html … ``` ` fences removed and the result trimmed |
| `cleanOperationResultStripsABareFence` | An unlabelled ` ``` ` fence removed too |
| `cleanOperationResultLeavesUnfencedHTMLAlone` | HTML with no fence passes through unchanged |
| `cleanOperationResultNormalizesTables` | A right-click rewrite goes through the same table cleanup a generated post does |
| `tableInlineStylesStripped` | `style` removed from `<table>` |
| `styleIsStrippedFromEveryTableTagIncludingCaptionAndFoot` | …and from `<thead>`, `<tbody>`, `<tfoot>`, `<tr>`, `<th>`, `<td>`, `<caption>` |
| `singleQuotedStylesAreStrippedToo` | `style='…'` stripped as well as `style="…"` |
| `strippingStyleLeavesTheOtherAttributesAndText` | Only the `style` attribute goes; everything else on the tag survives |
| `nonTableInlineStylesLeftAlone` | A `style` outside a table is untouched — this pass is not a general style stripper |
| `tableWithOwnClassKeepsIt` | A `<table>` that already has a class keeps it rather than being overwritten |
| `tableWithBothStyleAndClassKeepsOnlyTheClass` | Style stripped, existing class kept, no second class added |
| `multipleTablesEachGetTheDefaultLayoutClass` | Every classless table in the result gets `has-fixed-layout`, not just the first |
| `generatePromptForbidsInlineStyles` | The prompt itself tells Claude not to write inline styles, so the cleanup is a backstop rather than the only defence |

The tag match ends at a word boundary that excludes `-` and word characters (`(?![-\w])`). Without it, `table\b` matched the `table` in `<table-of-contents style="…">` and rewrote it into `<table class="has-fixed-layout"-of-contents>` — a custom element mangled into invalid markup.

---

### 13. AI — `AnthropicClientTests` (21 tests)

File: `Tests/QuillTests/AnthropicClientTests.swift`
Support: `Tests/QuillTests/Support/AnthropicMockURLProtocol.swift`

`@Suite(.serialized)` — uses its own `AnthropicMockURLProtocol` subclass with a separate `static var requestHandler` to avoid races with `WordPressClientTests`' `MockURLProtocol`. Body reconstruction: URLSession clears `httpBody` in URLProtocol; `AnthropicMockURLProtocol.startLoading()` reads the body from `httpBodyStream`.

#### Request headers (3 tests)

| Test | What it checks |
|---|---|
| `requestHasApiKeyHeader` | `x-api-key` header set |
| `requestHasVersionHeader` | `anthropic-version: 2023-06-01` |
| `requestHasContentTypeHeader` | `content-type: application/json` |

#### Beta headers & web search (3 tests)

| Test | What it checks |
|---|---|
| `noBetaHeaderSent` | No `anthropic-beta` header sent (prompt caching and web search are GA, no longer need beta header) |
| `toolsAbsentWhenWebSearchOff` | `tools` key absent from body |
| `toolsPresentWhenWebSearchOn` | `tools` array contains `web_search_20250305` |

#### Prompt caching (1 test)

| Test | What it checks |
|---|---|
| `systemBlockHasCacheControlEphemeral` | System block has `cache_control: {"type":"ephemeral"}` |

#### Response handling (8 tests)

| Test | What it checks |
|---|---|
| `singleTextBlockReturnsText` | Single `type:"text"` block → its text |
| `multipleTextBlocksAreJoinedInOrder` | Multiple text blocks → joined in order (web-search fragmentation gotcha) |
| `nonTextBlocksExcludedFromJoin` | `server_tool_use` and `web_search_tool_result` blocks excluded |
| `allNonTextBlocksThrowsNoTextContent` | All non-text blocks → `AnthropicError.noTextContent` |
| `truncatedTrueWhenStopReasonIsMaxTokens` | `stop_reason: "max_tokens"` → `truncated: true` |
| `truncatedFalseWhenStopReasonIsEndTurn` | `stop_reason: "end_turn"` → `truncated: false` |
| `missingStopReasonFieldDoesNotThrowAndIsNotTruncated` | Response JSON omitting `stop_reason` entirely still decodes (field is `Optional`) and reports `truncated: false` |
| `nonOkStatusThrowsHttpError` | Non-200 → `AnthropicError.httpError(code, body)` |

#### Error handling (6 tests)

| Test | What it checks |
|---|---|
| `httpErrorPreservesBodyString` | Error body string preserved |
| `malformedJsonThrows` | Garbage JSON → decoding throws |
| `networkFailureThrows` | `URLError` from mock → error surfaced |
| `networkFailureWrapsAsAnthropicNetworkError` | Any transport error from `session.data(for:)` is wrapped as `AnthropicError.networkError`, not left as a raw `URLError` |
| `networkErrorShowsFriendlyMessageWhenUnderlyingDescriptionMentionsOffline` | `errorDescription` returns the friendly "Couldn't reach the Anthropic API…" message when the underlying error's description mentions being offline/unable to connect (tested via a controlled fake error, since `URLError.localizedDescription` under `swift test` is a generic fallback string rather than CFNetwork's real text) |
| `networkErrorPassesThroughUnrecognizedMessage` | `errorDescription` passes through the underlying error's message verbatim when it doesn't match the offline/connectivity heuristic |

---

### 14. View-model — `PostItemTests` (11 tests)

File: `Tests/QuillTests/AppStateTests.swift`

| Test | What it checks |
|---|---|
| `remotePostIdFormatsAsRemoteDashId` | `PostItem.remote(post).id == "remote-5"` |
| `localDraftIdFormatsAsLocalDashId` | `PostItem.local(draft).id == "local-5"` |
| `remoteAndLocalWithSameNumericIdDoNotCollide` | `"remote-5" != "local-5"` (sidebar selection guard) |
| `remotePostTitleUsesRenderedTitle` | `post.title.rendered` used as display title |
| `remotePostWithEmptyTitleReturnsUntitled` | Empty rendered title → `"Untitled"` |
| `localDraftTitleUsesDraftTitle` | `draft.title` used as display title |
| `localDraftWithEmptyTitleReturnsUntitled` | Empty draft title → `"Untitled"` |
| `remoteStatusBadgeIsPostStatus` | `post.status` (e.g. `"draft"`) used directly |
| `localPostStatusBadgeIsLocalPost` | `type="post"` → `"local-post"` |
| `localPageStatusBadgeIsLocalPage` | `type="page"` → `"local-page"` |
| `onlyARemoteItemReportsItselfAsRemote` | `.isRemote` true for a remote post, false for a local draft — the sole gate on File → Revert to Saved… and Preview in Browser |

### 15. View-model — `SidebarSectionTests` (8 tests)

File: `Tests/QuillTests/AppStateTests.swift`

| Test | What it checks |
|---|---|
| `postsIcon` | `.posts.icon == "doc.text"` |
| `pagesIcon` | `.pages.icon == "doc.plaintext"` |
| `localDraftsIcon` | `.localDrafts.icon == "pencil"` |
| `mediaIcon` | `.media.icon == "photo"` |
| `postsShortTitle` | `.posts.shortTitle == "Posts"` |
| `pagesShortTitle` | `.pages.shortTitle == "Pages"` |
| `localDraftsShortTitle` | `.localDrafts.shortTitle == "Drafts"` |
| `mediaShortTitle` | `.media.shortTitle == "Media"` |

### 16. View-model — `AppStateLoadingTests` (2 tests)

File: `Tests/QuillTests/AppStateTests.swift`

Tests that `AppState` initializes with loading flags set correctly — `isLoadingList`/`isLoadingMedia` start `true` and `hasLoadedList`/`hasLoadedMedia` start `false`, so views show a spinner instead of flashing an empty state before the first fetch completes.

| Test | What it checks |
|---|---|
| `initialListStateWaitsForFirstLoad` | `isLoadingList == true`, `hasLoadedList == false` on fresh `AppState` |
| `initialMediaStateWaitsForFirstLoad` | `isLoadingMedia == true`, `hasLoadedMedia == false` on fresh `AppState` |

### 17. View-model — `AppStateFilteredItemsTests` (10 tests)

File: `Tests/QuillTests/AppStateTests.swift`

| Test | What it checks |
|---|---|
| `postsSectionMapsRemotePosts` | `.posts` section → `[.remote(…)]` items |
| `pagesSectionMapsRemotePages` | `.pages` section → `[.remote(…)]` items |
| `localDraftsSectionMapsLocalDrafts` | `.localDrafts` section → `[.local(…)]` items |
| `mediaSectionReturnsEmpty` | `.media` section → always `[]` |
| `emptySearchReturnsAllItems` | `searchText == ""` → guard exits early, all items returned |
| `searchFiltersCaseInsensitively` | `"hello"` matches title `"Hello World"` |
| `searchReturnsEmptyForNoMatch` | `"zzz"` matches nothing |
| `partialTitleMatchReturnsItem` | `"World"` matches `"Hello World"` |
| `whitespaceOnlySearchFiltersOutAllNormalTitles` | `"   "` is non-empty so filtering applies; normal titles have no 3-space run → empty result |
| `searchOnlyAppliesToActiveSection` | Search on `.posts` doesn't bleed into `.pages` data |

---

### 18. View-model — `SectionIsEmptyTests` (5 tests)

File: `Tests/QuillTests/AppStateTests.swift`

Tests the `sectionIsEmpty` computed property on `AppState`, used by `SectionEmptyState` and `EmptyEditorPlaceholder` to show contextual empty-state messages.

| Test | What it checks |
|---|---|
| `postsEmptyWhenNoPosts` | `.posts` section with no posts → `true` |
| `postsNotEmptyWhenPostsExist` | `.posts` section with posts → `false` |
| `pagesEmptyWhenNoPages` | `.pages` section with no pages → `true` |
| `localDraftsEmptyWhenNoDrafts` | `.localDrafts` section with no drafts → `true` |
| `mediaEmptyWhenNoMedia` | `.media` section with no media → `true` |

---

### 19. Security — `EditorCoordinatorTests` (12 tests)

File: `Tests/QuillTests/EditorCoordinatorTests.swift`

Guards the `isAllowedExternalURL` scheme allowlist (linked to the S2 security finding: clicked links in the editor must not be handed to `NSWorkspace.shared.open` with arbitrary schemes) and `mediaSizesDict(for:)`, the pure helper `handleRequestMediaSizes` uses to build the size dict sent to `setMediaSizes` in the JS editor.

| Test | What it checks |
|---|---|
| `httpURLIsAllowed` | `http://` → allowed |
| `httpsURLIsAllowed` | `https://` → allowed |
| `mailtoURLIsAllowed` | `mailto:` → allowed |
| `fileURLIsNotAllowed` | `file:///` → blocked |
| `javascriptURLIsNotAllowed` | `javascript:` → blocked |
| `ftpURLIsNotAllowed` | `ftp://` → blocked |
| `schemeCheckIsCaseInsensitive` | `HTTPS://` → allowed (lowercased before compare) |
| `mediaSizesDictAddsFullFallbackWhenSizesOmitsIt` | `media_details.sizes` missing a `"full"` entry gets one synthesized from `source_url`/top-level width/height |
| `mediaSizesDictPreservesExistingFullEntry` | A server-provided `"full"` entry in `sizes` is not overwritten |
| `misspelledWordsReturnsOnMainActorWithoutTrapping` | NSSpellChecker's callback, which arrives on its own queue, reaches a main-actor completion without Swift's isolation check trapping the process (the Check Spelling crash) |
| `mediaSizesDictFallsBackToSourceURLWhenNoSizesAtAll` | No `media_details.sizes` at all still yields a single `"full"` entry from `source_url` |
| `mediaSizesDictReturnsNilWhenSourceURLIsEmpty` | Empty `source_url` → `nil` (no usable size data) |

---

### 20. Editor helpers — `PostEditorHelpersTests` (24 tests)

File: `Tests/QuillTests/PostEditorHelpersTests.swift`

Tests `PostEditorView` static helpers that are pure functions and can be exercised without instantiating the SwiftUI view.

#### `previewURL` (5 tests)

| Test | What it checks |
|---|---|
| `previewURLAppendsFreshQueryToCleanURL` | Pretty permalink gets `?preview=true` appended |
| `previewURLAppendsPreviewAlongsideExistingQuery` | Plain permalink `/?p=123` becomes `/?p=123&preview=true` (not double `?`) |
| `previewURLReplacesExistingPreviewFalseParam` | Existing `preview=false` is replaced, not duplicated |
| `previewURLPreservesMultipleExistingParams` | Other query params survive the transformation |
| `previewURLPreservesFragment` | `#section` fragment is preserved alongside the new query |

#### `PostStats` (3 tests)

| Test | What it checks |
|---|---|
| `readingTimeZeroWordsIsZero` | Zero-word post → `readingMinutes == 0` |
| `readingTimeShortTextIsOneMinute` | Word count ≤ 238 → `readingMinutes == 1` |
| `readingTimeRoundsUp` | Word count that doesn't divide evenly → reading time rounds up (e.g. 239 words → 2 min) |

#### Status helpers (6 tests)

| Test | What it checks |
|---|---|
| `publishButtonTitlePerStatus` | Each status value maps to the correct button label (`"Publish Draft"`, `"Update"`, `"Schedule"`, `"Submit for Review"`, `"Publish Privately"`, etc.) |
| `toastMessagePerStatus` | Each status transition maps to the correct toast string |
| `statusChangeToFutureSetsDefaultDate` | Switching to `future` when no date exists → `publishDate` set to a non-nil default |
| `statusChangeToFuturePreservesExistingDate` | Switching to `future` when a date already exists → existing date preserved |
| `statusChangeToPrivateClearsScheduledDate` | Switching from `future` to `private` → `publishDate` cleared to `nil` |
| `statusChangeToPendingClearsScheduledDate` | Switching from `future` to `pending` → `publishDate` cleared to `nil` |

#### Dropped-image upload feedback (10 tests)

Static message builders behind the Finder-drop progress pill and its summary toast. The pill and toast themselves are SwiftUI view state and are covered manually (§7.4).

| Test | What it checks |
|---|---|
| `uploadStatusTextForSingleFile` | A one-file drop reads `"Uploading image…"` — no "1 of 1" counter |
| `uploadStatusTextForMultipleFiles` | A multi-file drop counts up: `"Uploading image 2 of 3…"` |
| `uploadSuccessMessageForSingleFile` | One file → `"Image inserted"`, or `"Converted to JPEG · Image inserted"` when HEIC conversion ran |
| `uploadSuccessMessageForTwoFilesUsesThePluralForm` | Two files → `"2 images inserted"` (one summary toast, not one per file) |
| `uploadSuccessMessageForMultipleFiles` | Three files → `"3 images inserted"`; the conversion note is dropped for batches |
| `uploadSuccessMessageWithNothingInsertedFallsThroughToPlural` | `inserted: 0` → `"0 images inserted"`. Unreachable from `handleDroppedImages`; pinned deliberately so the branch can't drift into a crash or a singular string |
| `uploadFailureMessageForSingleFileKeepsUnderlyingError` | One failed file → `"Upload failed: <error>"` with the underlying error text intact |
| `uploadFailureMessageForMultipleFilesSummarizes` | Two of three failed → `"2 of 3 images failed to upload"` |
| `uploadFailureMessageWhenEveryFileInAMultiDropFails` | All three failed → `"3 of 3 images failed to upload"` |
| `uploadFailureMessageForPartialMultiDropOmitsTheErrorText` | Partial batch failure summarizes as a count and deliberately drops the per-file error text |

### 21. App — `UpdateCheckerTests` (12 tests)

File: `Tests/QuillTests/UpdateCheckerTests.swift`

Tests the `isNewer(remote:local:)` semantic version comparison used by the update checker, and `normalizeVersion(_:)`, which strips the `v` prefix from a GitHub release tag before that comparison.

| Test | What it checks |
|---|---|
| `newerMajorVersion` | `2.0.0` > `1.0.0` → `true` |
| `newerMinorVersion` | `1.1.0` > `1.0.0` → `true` |
| `newerPatchVersion` | `1.0.1` > `1.0.0` → `true` |
| `sameVersionIsNotNewer` | `1.0.0` == `1.0.0` → `false` |
| `olderVersionIsNotNewer` | `1.0.0` < `2.0.0` → `false` |
| `differentSegmentCounts` | `1.0.1` > `1.0` → `true`; `1.0` < `1.0.1` → `false` |
| `largeVersionNumbers` | `10.20.30` > `10.20.29` → `true`; `10.20.30` == `10.20.30` → `false` |
| `stripsLeadingVFromTag` | `v2.0.0` → `2.0.0` |
| `leavesBareVersionUnchanged` | `2.0.0` → `2.0.0` |
| `stripsOnlyTheFirstCharacter` | `v1.11.0` → `1.11.0` |
| `normalizedTagIsNewerThanCurrentBuild` | normalized `v2.0.0` > `1.11.0` → `true` |
| `unnormalizedTagSilentlyFailsToCompare` | raw `v2.0.0` vs `1.11.0` → `false`, pinning the failure mode `normalizeVersion` exists to prevent |

### 22. API — `MimeTypeTests` (12 tests)

File: `Tests/QuillTests/MimeTypeTests.swift`

Tests the single shared `MimeType.forExtension`/`forFile` helper (backed by `UTType.preferredMIMEType`) that replaced three independently-drifted `mimeType(for:)` functions in `PostEditorView`, `MediaSidebarSection`, and `MediaPickerView`.

| Test | What it checks |
|---|---|
| `jpegExtension` | `jpg`/`jpeg` → `image/jpeg` |
| `pngExtension` | `png` → `image/png` |
| `gifExtension` | `gif` → `image/gif` |
| `webpExtension` | `webp` → `image/webp` |
| `pdfExtension` | `pdf` → `application/pdf` |
| `heicExtension` | `heic` → `image/heic` |
| `tiffExtension` | `tiff`/`tif` → `image/tiff` |
| `extensionIsCaseInsensitive` | `JPG`/`PNG` → same result as lowercase |
| `unknownExtensionFallsBackToOctetStream` | Unrecognized extension → `application/octet-stream` |
| `emptyExtensionFallsBackToOctetStream` | Empty string → `application/octet-stream` |
| `forFileUsesURLPathExtension` | `forFile(url:)` reads the extension from the URL's path |
| `forFileWithNoExtensionFallsBackToOctetStream` | File URL with no extension → `application/octet-stream` |

---

### 23. API — `ImageConversionTests` (17 tests)

File: `Tests/QuillTests/ImageConversionTests.swift`
Source: `Sources/QuillKit/API/ImageConversion.swift`

Tests `ImageConversion.prepareForUpload(_:)` and `Prepared.cleanup()`. WordPress 7.1 accepts HEIC over the REST API but cannot generate sub-sizes for it, so the attachment lands with no dimensions and no sizes; Quill converts HEIC/HEIF to JPEG locally before upload. Test images are written with ImageIO into a temp directory, so the suite exercises the real decode/re-encode path rather than a stub.

| Test | What it checks |
|---|---|
| `heicIsConvertedToJPEG` | A `.heic` input comes back as a JPEG (`public.jpeg` type) with `didConvert == true` |
| `heifExtensionIsConvertedToJPEG` | `.heif` is treated the same as `.heic` |
| `uppercaseHEICExtensionIsConverted` | `IMG_1234.HEIC` (the real camera-roll casing) still converts — extension match is case-insensitive |
| `convertedFilenameUsesJPGExtension` | Output filename swaps the extension to `.jpg` |
| `dotsInTheFilenameAreKeptAndOnlyTheExtensionIsReplaced` | `my.photo.v2.heic` → `my.photo.v2.jpg`; only the final extension is replaced |
| `conversionWritesToADifferentFileAndLeavesTheOriginalInPlace` | The source file is never mutated or moved |
| `conversionPreservesEXIFOrientation` | Orientation metadata survives the re-encode, so photos do not upload sideways |
| `conversionPreservesPixelDimensions` | Output pixel width/height match the input — guards against a silent downscale that an output-type-only assertion would miss |
| `twoFilesWithTheSameNameConvertToSeparateTempFiles` | Two different `photo.heic` files converted in one pass land in separate per-upload temp directories and do not clobber each other |
| `cleanupRemovesTheConvertedTempFile` | `cleanup()` deletes the converted file after upload |
| `cleanupRemovesTheWholeTempDirectoryNotJustTheFile` | `cleanup()` removes the per-upload UUID directory, leaving no empty dirs behind |
| `cleanupOnAPassedThroughFileDoesNotDeleteIt` | `cleanup()` is a no-op when nothing was converted — a user's own file on disk is never deleted |
| `jpegPassesThroughUntouched` | `.jpg` returns the original URL, `didConvert == false` |
| `pngPassesThroughUntouched` | `.png` passes through |
| `pdfPassesThroughUntouched` | `.pdf` passes through (media library uploads are not images only) |
| `unreadableHEICFallsBackToTheOriginalFile` | A file ImageIO cannot decode falls back to uploading the original — conversion never blocks an upload |
| `aFileWithNoExtensionPassesThroughWithoutCrashing` | Extensionless file passes through instead of trapping |

---

### 24. Editor — `BlockRiskAlarmTests` (15 tests)

File: `Tests/QuillTests/BlockRiskAlarmTests.swift`

Covers the banner Quill shows when its tripwire finds that content went missing between the post it loaded and the document it holds, plus the rule that decides whether the banner should still be on screen at all.

| Test | What it checks |
|---|---|
| `singleBlockUsesSingularWording` | One missing block → singular copy |
| `multipleBlocksUsePluralWording` | Two or more → plural copy |
| `bodyNamesEveryAffectedBlock` | Every affected block is named in the body, not just the first |
| `bodyExplainsItIsNotTheAuthorsFault` | The copy says this is Quill's limitation, not something the user did |
| `acknowledgedStageUnblocksSavingAndChangesCopy` | Acknowledging changes the wording and lets the save through |
| `savedStageIsPastTenseAndPointsAtRevisions` | After saving, the banner is past tense and points at WordPress revisions as the way back |
| `savedStagePluralisesCorrectly` | Plural wording holds in the saved stage too |
| `noStringContainsAnEmDash` | House-style guard across every string in every stage |
| `displayNamesAreHumanReadable` | Block names are shown as a person would say them (Synced Pattern, Page Break, Read More, Custom HTML), and a namespaced third-party block degrades sensibly |
| `onlyTheUnacknowledgedStageBlocksSaving` | Only the first stage blocks saving |
| `acknowledgingKeepsTheBlockNames` | Acknowledging does not lose the list |
| `anEmptyReportClearsTheAlarm` | An empty at-risk list clears the banner — this is how a post repaired in code view stops blocking saves without reopening it |
| `repeatingTheSameReportKeepsAnAcknowledgedStage` | The same list reported again keeps an `.acknowledged` or `.saved` stage rather than re-raising the banner the user already dismissed |
| `aDifferentReportRaisesTheAlarmAgain` | A different list raises the banner afresh, unacknowledged |
| `aFirstReportRaisesTheAlarm` | The first report on a clean state raises it |

---

### 25. Editor — `EditorPushDecisionTests` (8 tests)

File: `Tests/QuillTests/EditorCoordinatorTests.swift` (second suite in the file)

`EditorPushState` decides whether a `setContent` into the web view is worth making. Pushing needlessly resets the caret; not pushing when the content genuinely differs loads the wrong post. The dedupe key is the HTML **and** the footnotes together, because footnote bodies live in post meta rather than in the content.

| Test | What it checks |
|---|---|
| `identical content and footnotes is skipped` | Same pair → no push |
| `a footnote-only difference still pushes` | Same body, different notes → push |
| `nil and empty footnotes are the same absence` | `nil` and `""` are not treated as a change |
| `a content difference pushes whatever the footnotes say` | Body differs → push regardless of notes |
| `recording the HTML alone leaves the recorded footnotes intact` | `contentChanged` only knows the HTML; if it reset the notes half, the next update would re-push identical content and wipe the caret |
| `recording the footnotes alone leaves the recorded HTML intact` | The mirror image, for `footnotesChanged` |
| `switching between two posts with the same body still pushes each time` | A → B → A, where the two posts differ only in their notes, pushes all three times |
| `an empty post is skipped on a fresh state and pushed after any load` | A fresh state matches an editor that has loaded nothing, so an empty post is legitimately skipped once — but only the first time |

---

### 26. AI — `AIOutputFixtureTests` (2 tests)

File: `Tests/QuillTests/AIOutputFixtureTests.swift`

The Swift half of the AI output validity suite: keeps each `Scripts/fixtures/ai/` sample's `.html` equal to what `parseGenerateResponse`/`cleanOperationResult` make of its `.raw.txt`, so the JS suite is checking what the app would really hand the editor rather than a hand-written approximation.

---

## JS block serializer tests (110 tests)

File: `Scripts/test-block-serializer.js`
Under test: `Sources/QuillKit/Resources/block-parser-bundle.js`, `block-serializer.js`, `block-descriptors.js`

Pure Node — no DOM, no jsdom, no Tiptap — which makes this the cheapest suite in the project and the fastest guard against the round-trip regression class that produced the three shipped comment-stripping bugs. Each file is read off disk and evaluated in its own `new Function` sandbox, so the suite tests the shipped source rather than a copy.

**What is live:** all three files are loaded by `editor.html`. `block-descriptors.js` is read by `toWordPressHTML` — that is how saves get their `wp:` delimiters. `block-parser-bundle.js` (WordPress's own block parser, bundled by `Scripts/bundle-block-parser.sh`) and `block-serializer.js` (block tree → `post_content`) were re-hooked on 2026-09-12 for unsupported-block preservation: the parser enumerates a post's top-level blocks on load and the serializer produces each one's stored text. The ordinary save path is still `toWordPressHTML`, not the serializer.

### `block parser bundle` (2 tests)

| Test | What it checks |
|---|---|
| `parses a delimited paragraph` | `<!-- wp:paragraph -->` markup yields one block with `blockName: 'core/paragraph'` and its `innerHTML` intact |
| `parses undelimited HTML as a freeform block` | Classic content with no delimiters yields a single `blockName: null` freeform block |

### `block serializer` (5 tests)

| Test | What it checks |
|---|---|
| `round-trips a paragraph byte-identically` | parse → serialize returns the input unchanged |
| `round-trips attributes without reordering or re-spacing` | `{"level":3}` comes back with identical key order and spacing — the serializer re-emits attributes, so any drift here is silent data change |
| `round-trips nested blocks at their innerContent slots` | A `wp:paragraph` inside a `wp:group` is re-inserted at its `null` slot in the parent's `innerContent`, not appended |
| `passes freeform content through untouched` | A block with no `blockName` emits its content with no delimiters added |
| `strips the core/ prefix in delimiters` | `core/separator` is written as `wp:separator`, matching what WordPress writes |

### `fixture round-trips` (5 tests)

One test per `Scripts/fixtures/*.html`, globbed at load time — dropping a new capture in adds a test with no code change. Each asserts the file survives parse → serialize byte-identically. The corpus is real `post_content` from the live site: a two-item accordion, a captioned gallery, a tabs block, and one whole published post (classic prose, images, footnotes, two accordions), plus the hand-written `unsupported-blocks.html`.

See `Scripts/fixtures/README.md` before changing a fixture — they are recordings of what one WordPress version wrote, never a specification of what core emits now, and `accordion-block.html` deliberately holds the old heading shape.

### `block descriptors` (4 tests)

| Test | What it checks |
|---|---|
| `maps heading to core/heading with its level attribute` | `descriptorFor('heading')` returns `core/heading`, shape `text`, and `attrsFrom` reads `{ level: 3 }` off an `<h3>` |
| `maps paragraph to core/paragraph with no attributes` | The common case emits an empty attribute object, so no `{}` is written into the delimiter |
| `returns null for an unknown node` | An unregistered node name gets no descriptor, which is how `toWordPressHTML` knows to leave it alone |
| `level 2 headings emit level 2, not a default` | Guards against a hardcoded level slipping in behind the `<h3>` case |

### `blockSourceSlices` (9 tests)

The cursor walk that gives each top-level block a literal slice of the original `post_content`. The parser exposes no byte offsets, so the block's text has to come from `serializeBlock`, which is a reconstruction — the walk tests whether the original continues with exactly those bytes at the cursor and stores the real slice when it does.

| Test | What it checks |
|---|---|
| `a canonical block yields an exact slice of the original` | The common case is `exact: true` with `blockName` and `attrsJSON` populated |
| `slices concatenate back to the original` | The walk loses nothing between blocks |
| `inter-block whitespace is preserved as a freeform slice` | The `\n\n` WordPress writes between blocks comes back as a `blockName: null` slice, not dropped |
| `a self-closing block yields an exact slice` | `<!-- wp:calendar /-->` round-trips |
| `freeform content is reported with a null blockName` | Classic prose is not a block |
| `non-canonical attribute formatting falls back, marked inexact` | `{"width":33.0}` serialises to `{"width":33}`, so the slice is marked inexact and stores the serialisation |
| `an inexact block does not desynchronise the blocks after it` | The cursor recovers past the fallback, so the next block is still exact |
| `an inexact nested block still yields faithful sources for what follows` | The recovery heuristic mis-lands on a nested block's closing delimiter, so this pins the consequence: later blocks may go inexact, but an inexact block's source is always a faithful serialisation, never a wrong slice |
| `an inexact self-closing block still yields a faithful source for what follows` | Same guarantee where there is no closing delimiter to find at all |

### `blockSourceSlices over the real fixtures` (5 tests)

One test per fixture: every block comes back `exact: true` and the slices concatenate to the file byte-for-byte. This is the evidence that canonical WordPress output never takes the fallback path.

### `blockNeedsWrapping` (11 tests)

| Test | What it checks |
|---|---|
| `a block with a wp-block class root is left alone` | The existing `gutenbergPassthrough` catch-all already holds it |
| `a paragraph is left alone even though its markup carries no class` | `core/paragraph` saves bare `<p>`, so the class test alone would freeze every paragraph into a card |
| `a modeled block that saves no markup is wrapped` | A self-closing `<!-- wp:separator /-->` carries a name Quill models but no markup for any node to parse, so the modeled exemption must not reach it. Found by the alarm firing on a real draft |
| `a modeled block that does save markup is still left alone` | The separator WordPress actually writes stays an editable rule |
| `every block Quill models is left alone` | Paragraph, heading, list, quote, code and separator all stay editable |
| `core/html is wrapped, because its markup has no wp-block class` | |
| `core/shortcode is wrapped, because it has no element at all` | |
| `a self-closing dynamic block is wrapped` | Calendar and friends save no markup to attach to |
| `a page break is wrapped` | |
| `freeform prose is never wrapped` | |
| `a nested block inside a claimed block does not make the parent wrap` | A `wp:query` holding a `wp:post-title` is one top-level block, not two |

### `wrapUnsupportedBlocks` (6 tests)

| Test | What it checks |
|---|---|
| `leaves a fully supported post untouched` | Returns the input string identically when nothing needs wrapping |
| `leaves every real-site fixture untouched` | The four live-site captures are unaffected by the new pass |
| `wraps exactly the eight unsupported blocks in the corpus fixture` | The counter-example: eight wrappers, prose untouched |
| `replaces a shortcode block with a wrapper carrying its source` | The wrapper carries `data-quill-unsupported-source` and a readable label |
| `stores quotes and ampersands in the source without corruption` | Setting the attribute through the DOM escapes correctly and `getAttribute` returns the original |
| `keeps supported blocks in place around a wrapped one` | Document order survives |

### `unrepresentedBlockNames` (5 tests)

| Test | What it checks |
|---|---|
| `reports nothing when every block is accounted for` | |
| `reports a block the document does not hold` | |
| `ignores freeform blocks, which are prose not blocks` | |
| `strips the core prefix and de-duplicates` | |
| `keeps a third-party namespace intact` | `acme/widget` is reported whole, not truncated to `acme` |

---

## JS AI output validity tests (44 tests)

`Scripts/test-ai-output-validity.js` runs each `Scripts/fixtures/ai/*.html` sample through the editor exactly as the app does (`setContent` + `syncContentToSwift` for Generate Post; `beginAIOperation` / `showAIResult` / `acceptAIResult` for right-click rewrites), captures the bytes posted to Swift, and judges them with WordPress's own `@wordpress/blocks` validator (pinned versions; see `Scripts/fixtures/ai/README.md`). Its Swift half is `AIOutputFixtureTests` (2 tests, 7 cases), which keeps each `.html` equal to what Swift's cleanup makes of its `.raw.txt`. The replacement tests compare the whole document through `topLevelTexts()` (the text of each top-level block, in order), so a split, merged or emptied paragraph fails the test.

| Test | What it checks |
|------|----------------|
| `the validator itself` (4 tests) | Accepts core-authored markup; flags a heading/comment level mismatch, a styled table cell, and HTML outside any block — proof the checker is live, not vacuous |
| `a generated post saves as valid blocks` (5 tests) | No invalid, classic or unregistered block, and `serialize(parse(saved))` is byte-identical; heading levels 2–4 survive; no `style=` reaches the save; the table saves like a toolbar table; a second save is a no-op |
| `markup Claude sometimes writes saves as valid blocks` (8 tests) | Validity for the six shapes that used to fail, then one test each that the heading `id` becomes `anchor`, a custom class becomes `className`, `start` reaches the delimiter, a code language class moves to the `<pre>`, a table `<caption>` and a figure caption land in `<figcaption>`, plus idempotency |
| `everything else Claude might write saves as valid blocks` (3 tests) | Validity for h1–h6, legacy inline tags, entities, divs, bare text, mixed lists, three quote shapes, header-less / merged-cell / foot-section tables, `<pre>`, images, `<dl>`, `<details>`, sectioning tags; no listed phrase is lost; idempotency |
| `a right-click AI result saves as valid blocks` (3 tests) | The same validity check for a rewritten table, list, and pair of paragraphs |
| `a right-click AI result replaces only the selection` (21 tests) | This row covers twelve of them; the nine `↳` rows below cover the rest. A sentence selected at the start, middle or end of a paragraph is replaced in place and the paragraph is not split; a selection across bold text and one across two paragraphs keep the text outside them (exactly `Before one.` / `Merged.` / `After two.`); a two-paragraph result for the whole paragraph, or its start, middle or end, leaves no empty paragraph and no stray edge space, checked against the exact paragraph sequence; a second operation after a paragraph-splitting result still replaces the right text; Discard restores the original |
| ↳ `the highlighted result is exactly the inserted text, and accepting puts the caret after it` | After `showAIResult` the selection covers `Short.` and nothing else; after Accept the selection is an empty caret directly after it |
| ↳ `discarding keeps a space the author just typed at the end of a paragraph, and tells Swift` | Discard restores the ProseMirror doc exactly, trailing space included, and posts the restored HTML to Swift once |
| ↳ `a plain-text result holding an entity goes in as text, not markup` | `R&amp;D` is inserted as `R&D`, and the save holds no `&amp;amp;` |
| ↳ `a plain-text result holding a non-breaking space goes in as text, not markup` | `&nbsp;` is inserted as a U+00A0 character, not the literal entity |
| ↳ `a plain-text result holding a line break and indent goes in as text, not markup` | A newline plus indent inside the `<p>` collapses to one space |
| ↳ `a selection with a trailing space keeps the space` | Selecting `…wordy. ` (with the space) still leaves `Short. Last sentence stays.` with one space between |
| ↳ `a selection with a leading space keeps the space` | Selecting ` Middle…` (with the space) still leaves `stays. Short.` with one space between |
| ↳ `showAIResult reports whether it inserted anything` | A whitespace-only result returns `null` and Discard restores the text; a real result returns `true` |
| ↳ `a result that arrives after the post changed leaves the new post alone` | `setContent` between `beginAIOperation` and `showAIResult` makes `showAIResult` return `null` and leaves the new doc unchanged |

## JS fixture validity sweep (30 tests)

`Scripts/test-fixture-validity.js` loads each `Scripts/fixtures/*.html`, forces a save through Tiptap, and compares WordPress's validator findings on the save against those on the fixture.

| Test | What it checks |
|------|----------------|
| one test per fixture (27 tests) | Quill's save has no validator finding the fixture lacked; if the fixture re-saves byte-identically in WordPress, so does Quill's save |
| `the sweep can fail` (3 tests) | A heading level mismatch and invented classic HTML are reported as new; classic prose Quill converts to blocks is not |

---

## JS preservation tests (48 tests)

File: `Scripts/test-editor-preservation.js`
Editor file: `Sources/QuillKit/Resources/editor.html`

Loads the **real `editor.html`** in jsdom and drives `window.setContent` / `window.getContent`, the same approach as the container and gallery suites. The pure helpers above cannot reach this path: preservation crosses `setContent`'s wrap, the `gutenbergPassthrough` parse rule, the node view, and `toWordPressHTML`'s unwrap. It is also the only layer that catches the classic-script `const`-is-not-on-`window` class of bug (see the root `CLAUDE.md` gotcha) — the pure-Node suite `require`s the module and so cannot see it.

### `block parser and serializer are live in the editor` (2 tests)

| Test | What it checks |
|---|---|
| `window.BlockParser.parse is callable` | The re-hooked `<script>` tag is present and the bundle exposes its global |
| `window.serializeBlock is callable` | Same for the serializer, round-tripping a paragraph |

### `unsupported blocks become passthrough cards` (8 tests)

| Test | What it checks |
|---|---|
| `a wrapped shortcode parses into one gutenbergPassthrough node` | One node, with `unsupportedSource` holding the exact original and the right label |
| `the card shows the label and a peek at the content` | A bare "Shortcode" label cannot tell two shortcodes apart, so the card carries the text |
| `the peek is truncated for a long block` | Capped at 120 characters plus an ellipsis |
| `the peek renders markup as text, never as live DOM` | `textContent`, not `innerHTML` — a Custom HTML block must not execute in the editor |
| `the card keeps the existing hint line` | The Code View hint is unchanged |
| `an ordinary passthrough block still renders a card with no peek` | A classed block like `wp:spacer` takes the old path, no peek added |
| `an ordinary unmodeled block renders a labelled card with a peek` | The common case: a block Quill has no node for is shown as a named, non-editable card |
| `an unmodeled block nested in a modeled container still matches by class` | The class-based card is what is left of the old path, and it is the only thing covering a block nested inside a container Quill does model |

### `the wrap applies at post_content entry points only` (5 tests)

Four call sites set editor content; two receive `post_content` and must wrap, two restore `editor.getHTML()` and must not. Getting this wrong is silent, so each is pinned.

| Test | What it checks |
|---|---|
| `setContent wraps, so an edit elsewhere cannot destroy the block` | The shortcode survives a keystroke in another paragraph |
| `an unedited post still round-trips byte-identically` | The raw-HTML store keeps the unwrapped original |
| `code view shows the real source, not the wrapper` | The user never sees Quill's placeholder markup |
| `a block hand-edited in code view is re-wrapped on exit` | Missing this would mean a hand-edited Custom HTML block is shredded by the next visual edit |
| `the AI reject path does not double-wrap` | Restoring already-wrapped internal HTML adds no second wrapper |

### `the unsupported-block corpus survives an edit` (8 tests)

Runs `Scripts/fixtures/unsupported-blocks.html` — one of each shape that used to be destroyed — through load, edit elsewhere, save.

| Test | What it checks |
|---|---|
| `round-trips byte-identically with no edit` | |
| `every unsupported block survives an edit elsewhere` | All eight delimiters and all three inner-markup shapes intact |
| `the edit itself lands in the prose` | The test is actually editing the document, not silently no-opping |
| `every block comes back byte-for-byte, in order, but for the edit` | The markers above are substrings, so a delimiter that came back respaced, reordered or in the wrong place would still pass them. This compares the whole output. **The fixture is written with single newlines between blocks and Quill writes core's blank line, so that one gap difference is normalised away** — the save is not byte-identical to the fixture, and everything except the gaps has to match exactly |
| `and the blocks are separated the way core separates them` | Exactly one blank line per gap, never two |
| `saving twice is idempotent` | No growth or drift across repeated saves |
| `no wrapper markup reaches the saved output` | No `quill-unsupported` string in what goes to WordPress |
| `each unsupported block renders its own card` | Eight cards, so paragraphs are not being swallowed |

### `the alarm reports only genuine loss` (9 tests)

| Test | What it checks |
|---|---|
| `the transform helpers the editor needs are on window` | Guards the classic-script global-exposure boundary |
| `a fully preserved post posts nothing` | |
| `an ordinary post posts nothing` | |
| `every real fixture posts nothing` | No false alarm on any live-site capture |
| `every real fixture loaded twice in one post posts nothing` | A second copy of any block is accounted for; before the gallery fix, `gallery-block.html` and `post-17780.html` failed here and no other fixture did |
| `a post whose block the wrap missed is reported` | Stubs `wrapUnsupportedBlocks` to a no-op and asserts the exact eight names are posted — the only way to prove the tripwire does not share the wrap's assumptions |
| `the tripwire goes quiet again once the wrap is restored` | The stub did not leave state behind |
| `one of two blocks with the same name going missing is reported` | The count is per instance, not per name, so losing one of a pair is still a loss |
| `a second gallery in the same post is not reported` | Each source-backed `galleryBlock` counts its own name, so the second gallery is not treated as missing |
| `a block nested inside a modeled container is counted too` | The count walks every depth, not just the top level |
| `a code-view edit that loses a block is reported` | Hand-editing the source is the other way content goes missing, and it raises the banner the same way |

The editor posts its at-risk list on **every** load and code-view edit, an empty list included — that is how a post the user repaired clears its own banner. These tests therefore compare the reported *names*, not the number of messages.

### `reopening a post that already lost a block is quiet` (1 test)

| Test | What it checks |
|---|---|
| `content saved with the wrap disabled reloads with no alarm` | Banner state 4: once a block really is gone from the saved content, reopening the post finds nothing missing and stays silent, so the author is not nagged about a loss they already accepted |

### `a modeled block that saves no markup is preserved, not reported` (3 tests)

| Test | What it checks |
|---|---|
| `it raises no alarm on load` | The gap the alarm found on a live draft is closed |
| `it survives an edit elsewhere` | `<!-- wp:separator /-->` comes back intact, with no wrapper markup in the output |
| `a separator WordPress actually wrote stays an editable rule` | The fix does not freeze ordinary separators into cards |

### `loading an image post after an atom-only post` (3 tests)

| Test | What it checks |
|---|---|
| `an image loads after a gallery-only post` | A post whose whole document is one atom node leaves ProseMirror in a state where the next `setContent` silently no-ops; this pins that it does not |
| `an image loads after an embed-only post` | Same, for the other atom node |
| `the gallery-only post itself still loads` | The guard did not break the first load |

### `an attribute that could run script is not carried` (7 tests)

The raw-attribute carrier snapshots a loaded element's attributes and replays them onto the live contenteditable inside the privileged web view. An `on*` handler from post content would execute there. `isCarryableAttr` filters at snapshot time, and it has to be applied at all three snapshot points, so each one gets a test.

| Test | What it checks |
|---|---|
| `a block-level event handler is dropped` | `onmouseover` on a paragraph never reaches the live DOM, while an ordinary `data-` attribute still does |
| `an inline mark event handler is dropped` | Same through the `rawInline` mark, with `title` still carried |
| `a link event handler is dropped but its other attributes are kept` | Same through the link mark's own carrier |
| `a javascript: URL is dropped from a carried attribute` | A `javascript:` value in a URL-bearing attribute (here a quote's `cite`) is dropped |
| `whitespace inside a scheme does not get it past the filter` | Padding the scheme with whitespace or control characters does not evade the check |
| `an ordinary cite URL is still carried` | The filter is not a blanket ban — real URLs survive |
| `a handler never survives an edit back into post_content` | End to end: load, edit, save, and the handler is gone from what goes to WordPress |

### `preserved block bytes cannot be relocated by post text` (1 test)

| Test | What it checks |
|---|---|
| `text that looks like the old sentinel is left alone` | The placeholder `toWordPressHTML` leaves where a preserved block sat is a per-save random nonce. With the old fixed token, an author who typed it into a post had the preserved block's bytes moved to that spot — silently, because the block count never changed |

---

## JS editor tests (259 tests)

File: `Scripts/test-editor.js`
Transforms file: `Sources/QuillKit/Resources/editor-transforms.js`

Tests run under Node's built-in test runner with jsdom for DOM support. They test `toWordPressHTML`, `extractAlignment`, `formatHTML`, `countStats`, `findMatches`, `findMatchesLoose`, `fuzzyAnchorRegex`, `detectEmbedProvider`, `embedClassFor`, `passthroughLabelFromClass`, `passthroughLabelFromBlockName`, `parsePassthroughBlock`, and `isModeledFigure`/`QUILL_MODELED_FIGURE_CLASSES` from `editor-transforms.js`.

### `extractAlignment` (6 tests)

| Test | What it checks |
|---|---|
| `alignleft returns left` | `"alignleft"` → `"left"` |
| `alignright returns right` | `"alignright"` → `"right"` |
| `aligncenter returns center` | `"aligncenter"` → `"center"` |
| `empty string returns null` | `""` → `null` |
| `unrelated class returns null` | `"wp-block-image"` → `null` |
| `alignment class mixed with others is still detected` | `"wp-block-image alignright size-large"` → `"right"` |

### `toWordPressHTML` — headings (4 tests)

| Test | What it checks |
|---|---|
| `h1 gains wp-block-heading class` | `<h1>` → `class="wp-block-heading"` |
| `h2 through h6 each gain wp-block-heading` | All heading levels |
| `existing classes on heading are preserved` | Pre-existing classes kept alongside new class |
| `headings are idempotent` | Running twice doesn't duplicate the class |

### `toWordPressHTML` — lists (2 tests)

| Test | What it checks |
|---|---|
| `ul gains wp-block-list` | `<ul>` → `wp-block-list` |
| `ol gains wp-block-list` | `<ol>` → `wp-block-list` |

### `toWordPressHTML` — list item `<p>` unwrapping (8 tests)

| Test | What it checks |
|---|---|
| `single-child <p> inside <li> is unwrapped` | `<li><p>text</p></li>` → `<li>text</li>` |
| `multi-child <li> is left untouched` | Two `<p>` in one `<li>` → unchanged |
| `leading <p> is unwrapped when the rest of the <li> is a nested list` | `<li><p>text</p><ul>…</ul></li>` → text unwrapped, nested list kept |
| `unwrapping works at every level of a deep nest` | Applies recursively, not just at the top level |
| `ordered nested lists unwrap the same way` | `<ol>` nesting behaves identically to `<ul>` |
| `a paragraph AFTER the nested list keeps the item untouched` | `<li><ul>…</ul><p>text</p></li>` → unchanged |
| `an <li> whose first child is a list is left untouched` | Leading nested list → no unwrap |
| `already-Gutenberg nested markup passes through unchanged` | Idempotency on markup WordPress already produced |

### `toWordPressHTML` — blockquote & cite (5 tests)

| Test | What it checks |
|---|---|
| `blockquote gains wp-block-quote class` | `<blockquote>` → `wp-block-quote` |
| `empty cite is stripped` | `<cite></cite>` → removed from saved HTML |
| `whitespace-only cite is stripped` | `<cite>   </cite>` → removed |
| `non-empty cite is preserved` | `<cite>— Author</cite>` → survives |
| `cite stripping only applies inside blockquote` | `<cite>` outside blockquote not touched |

### `toWordPressHTML` — code blocks (1 test)

| Test | What it checks |
|---|---|
| `pre gains wp-block-code class` | `<pre>` → `wp-block-code` |

### `toWordPressHTML` — horizontal rules (2 tests)

| Test | What it checks |
|---|---|
| `hr gains wp-block-separator class` | `<hr>` → `wp-block-separator has-alpha-channel-opacity` |
| `hr class is idempotent` | Running twice doesn't duplicate the class |

### `toWordPressHTML` — images (10 tests)

| Test | What it checks |
|---|---|
| `figure with plain img gets wp-block-image class` | `<figure><img></figure>` gains `wp-block-image` class |
| `data-media-id produces wp-image-{id} class on img inside figure` | `data-media-id="42"` → `class="wp-image-42"` on `<img>` |
| `alignleft on img is moved to figure class` | `alignleft` moved from `<img>` to `<figure>` |
| `alignright on img is moved to figure class` | `alignright` moved from `<img>` to `<figure>` |
| `aligncenter on img is moved to figure class` | `aligncenter` moved from `<img>` to `<figure>` |
| `both alignment and media-id: figure gets align class, img gets wp-image class` | Both transforms applied together |
| `empty figcaption is removed from output` | `<figcaption></figcaption>` stripped |
| `non-empty figcaption gets wp-element-caption class` | Non-empty caption → `class="wp-element-caption"` |
| `whitespace-only figcaption is removed` | `<figcaption>   </figcaption>` treated as empty |
| `table figure is not treated as image figure` | `<figure class="wp-block-table">` → image transforms not applied |

### `toWordPressHTML` — image dimensions (12 tests)

Core stores a resized image as an inline `style` on the `<img>` plus an `is-resized` class on the figure, and repeats the numbers in the block comment. Quill models `width`/`height` as attributes, so the save has to translate.

| Test | What it checks |
|---|---|
| `width and height attributes become an inline style on the img` | Translated to core's `style`, which is what `save()` regenerates |
| `width and height attributes are removed from the img` | The attribute form does not survive alongside the style |
| `width alone forces height:auto, matching core save()` | |
| `height alone emits height only` | |
| `dimensions add is-resized to the figure` | |
| `no dimensions means no is-resized and no style` | |
| `stale is-resized is stripped when the image has no dimensions` | Resizing back to the original must not leave the class behind |
| `dimensions are carried into the wp:image comment attributes as px strings` | Core stores them as `"320px"`, not numbers |
| `width alone carries only width into the comment attributes` | |
| `an unresized image carries no width or height comment attribute` | |
| `an existing width style on the img survives without duplicating` | |
| `dimension handling is idempotent across a second save` | |

### `toWordPressHTML` — decorative images (4 tests)

| Test | What it checks |
|---|---|
| `role="none" on the img sets isDecorative in the comment attributes` | WP 7.1's "mark as decorative" toggle; `save()` regenerates the role from this attribute |
| `role="presentation" also sets isDecorative` | Both spellings accepted |
| `an image with no role carries no isDecorative attribute` | |
| `the role attribute stays on the img` | It rides the markup as well as the comment |

### `toWordPressHTML` — tables (10 tests)

| Test | What it checks |
|---|---|
| `table is wrapped in figure.wp-block-table` | `<table>` → `<figure class="wp-block-table">` |
| `all-th first row is promoted from tbody to thead` | All-`<th>` row moves to `<thead>` |
| `mixed th/td first row is NOT promoted to thead` | Mixed `<th>`/`<td>` → no promotion |
| `table already having thead is not modified` | Pre-existing `<thead>` → untouched |
| `table figure is wrapped in wp:table block comments` | The figure gets its own `wp:table` delimiter pair |
| `re-saving a delimited table does not stack wp:table comments` | Idempotency guard against the comment-stacking regression class |
| `table already inside wp-block-table is not double-wrapped` | Idempotency: one `wp-block-table` after two passes |
| `Tiptap table style and colgroup are stripped` | `style` attribute and `<colgroup>` removed from tables |
| `default colspan=1 and rowspan=1 are stripped from cells` | `colspan="1"` and `rowspan="1"` removed; non-default values preserved |
| `paragraph wrapper inside table cells is unwrapped` | Single `<p>` in `<td>` unwrapped; multi-`<p>` left as-is |

### `toWordPressHTML` — idempotency & edge cases (3 tests)

| Test | What it checks |
|---|---|
| `full document is idempotent across all transform types` | `toWordPressHTML(toWordPressHTML(x)) == toWordPressHTML(x)` for all element types |
| `empty paragraph is stable` | `<p></p>` → `<p></p>` |
| `unicode and emoji in text are preserved` | café, 🎉, curly quotes survive |

### `formatHTML` — block elements (4 tests)

`formatHTML` is the HTML pretty-printer used by code view (`_enterCodeView`). Tests verify structural indentation and inline element handling.

| Test | What it checks |
|---|---|
| `single paragraph renders on one line with no surrounding blank lines` | `<p>text</p>` → one line, no extra blank lines |
| `two top-level blocks are separated by a blank line` | Adjacent block elements have a blank line between them |
| `inline elements stay on the same line as their parent block` | `<strong>`, `<em>` etc. not moved to their own lines |
| `links stay inline` | `<a>` treated as inline, not block |

### `formatHTML` — nested block elements (5 tests)

| Test | What it checks |
|---|---|
| `list items are indented inside ul` | `<li>` indented one level inside `<ul>` |
| `table cells are indented under their row and section` | `<td>` indented inside `<tr>` inside `<tbody>` |
| `blockquote with p and cite each on their own indented lines` | `<p>` and `<cite>` inside `<blockquote>` each on own indented line |
| `div wrapping block children is indented like other block tags` | `<div>` (needed for `gutenbergPassthrough` code-view display) indents and recurses into children the same as `<figure>`/`<table>` |
| `a div with only raw-newline text content (e.g. EmbedBlock's wrapper) does not leave the URL and closing tag unindented (regression)` | Adding `div` to `formatHTML`'s `BLOCK` set for the row above initially broke code-view formatting of the pre-existing `EmbedBlock` wrapper div, whose only child is a text node containing literal `'\n'+url+'\n'` — without trimming that text, the URL and closing `</div>` landed flush-left on unindented lines. Fixed by trimming a block tag's text when it has no element children at all |

### `formatHTML` — special elements (5 tests)

| Test | What it checks |
|---|---|
| `img void element has no closing tag` | `<img>` serialized without `</img>` |
| `img is indented inside figure` | `<img>` child of `<figure>` gets proper indentation |
| `pre content is preserved verbatim without re-indenting` | Content of `<pre>` not touched (code block gotcha) |
| `empty input returns empty string` | `formatHTML("")` → `""` |
| `unicode and emoji are preserved` | Non-ASCII content survives pretty-printing |

### `formatHTML` — entity escaping (5 tests)

Guards the C1 code-view corruption bug: text nodes and attribute values must be re-escaped when serializing, since the DOM decodes entities on parse.

| Test | What it checks |
|---|---|
| `text node with < is escaped so it round-trips safely` | `5 < 10` → `5 &lt; 10` in output |
| `text node with & is escaped` | `a & b` → `a &amp; b` |
| `text node with > is escaped` | `a > b` → `a &gt; b` |
| `attribute value with " is escaped` | `"` inside attribute value → `&quot;` |
| `attribute value with & is escaped` | `&` inside attribute value → `&amp;` |

### `formatHTML` — HTML comments (5 tests)

Guards block comment preservation: WordPress block comments (`<!-- wp:paragraph -->` etc.) are HTML comment nodes (nodeType 8); if `formatHTML` drops them, code view silently strips all Gutenberg block markup.

| Test | What it checks |
|---|---|
| `block comment before an element is preserved` | `<!-- wp:paragraph -->` and `<!-- /wp:paragraph -->` survive `formatHTML` |
| `block comment with JSON attributes is preserved` | `<!-- wp:image {"id":42,"sizeSlug":"full"} -->` — JSON payload inside comment is not mangled |
| `opening comment appears on its own line before the element` | Opening comment is a separate line above the element, not concatenated inline |
| `closing comment appears on its own line after the element` | Closing comment is a separate line below the element, not concatenated inline |
| `multiple wrapped blocks each keep their block comments` | Two blocks each wrapped in open/close comments: all four comments present, in correct order |

### `countStats` (8 tests)

| Test | What it checks |
|---|---|
| `empty string returns zero counts` | `""` → `{ words: 0, chars: 0, readingTime: 1 }` |
| `null/undefined input returns zero counts` | `null` and `undefined` both return zero stats without throwing |
| `single word` | `"Hello"` → `words: 1` |
| `multiple words counted correctly` | `"Hello world foo"` → `words: 3` |
| `whitespace-only returns zero words` | `"   \t\n"` → `words: 0` |
| `chars counts all non-whitespace characters` | Punctuation and letters counted, spaces excluded |
| `unicode words counted correctly` | Multi-byte characters treated as words correctly |
| `reading time rounds up` | 400-word text → `readingTime: 2` (at 200 wpm, ceil) |

### `findMatches` (7 tests)

| Test | What it checks |
|---|---|
| `case-insensitive match by default` | `"hello"` matches `"Hello World"` |
| `case-sensitive flag respected` | `caseSensitive: true` → `"hello"` does not match `"Hello"` |
| `empty query returns no matches` | `""` → `[]` |
| `no match returns empty array` | Query not in text → `[]` |
| `regex special chars are escaped` | `"a.b"` matches literal `"a.b"`, not `"axb"` |
| `non-overlapping matches` | `"aa"` in `"aaaa"` → 2 matches, not 3 |
| `unicode offsets are correct` | Match positions in text containing multi-byte characters are byte-correct |

### `findMatchesLoose` (7 tests)

| Test | What it checks |
|---|---|
| `matches when editor text has a space before a comma but anchor does not` | `"DSPM , Content"` matches anchor `"DSPM, Content"` — the primary phantom-spacing case |
| `matches when the anchor has the extra space and editor text does not` | Reverse direction: anchor `"DSPM , Content"` matches editor `"DSPM, Content"` |
| `tolerates missing space after a comma` | `"A, B"` matches anchor `"A,B"` |
| `collapses multiple spaces between plain words` | Multiple spaces between words match `\\s+` |
| `still matches an exact phrase` | No regression on exact matches |
| `empty / whitespace query returns no matches` | `""` and `"   "` → `[]` |
| `does not require whitespace between plain words to be absent` | `"quickbrown"` does NOT match anchor `"quick brown"` — word gaps stay required |

### `fuzzyAnchorRegex` (3 tests)

| Test | What it checks |
|---|---|
| `makes whitespace around punctuation optional` | `"DSPM, Content"` → `DSPM\\s*,\\s*Content` |
| `collapses a leading space before punctuation into \\s*` | `"DSPM , Content"` → same regex as without the space |
| `requires a gap between plain words` | `"quick brown"` → `quick\\s+brown` (not optional) |

### `detectEmbedProvider` (5 tests)

| Test | What it checks |
|---|---|
| `youtube.com and youtu.be map to youtube` | Both `youtube.com` and `youtu.be` → `"youtube"` |
| `vimeo maps to vimeo with video type` | `https://vimeo.com/…` → `"vimeo"` |
| `x.com and twitter.com map to twitter` | Both `x.com` and `twitter.com` → `"twitter"` |
| `unknown host returns null` | `https://example.com/…` → `null` |
| `invalid URL returns null` | `"not a url"` → `null` |

### `embedClassFor` (3 tests)

| Test | What it checks |
|---|---|
| `youtube gets full Gutenberg class list with aspect ratio` | `embedClassFor("youtube", "video")` → `"wp-block-embed is-type-video is-provider-youtube wp-block-embed-youtube"` |
| `twitter gets rich type without aspect classes` | `embedClassFor("twitter", "rich")` → includes `is-type-rich is-provider-twitter` |
| `unknown provider gets bare wp-block-embed` | `embedClassFor(null, null)` → `"wp-block-embed"` |

### `toWordPressHTML` — embeds (5 tests)

| Test | What it checks |
|---|---|
| `embed figure gets Gutenberg block comment wrappers` | `<figure class="wp-block-embed …">` → wrapped with `<!-- wp:embed … -->` / `<!-- /wp:embed -->` Gutenberg block comments |
| `block comment wrapping is idempotent` | Running `toWordPressHTML` on already-wrapped embed doesn't double-wrap |
| `embed figure does not gain wp-block-image` | No `wp-block-image` class added, no alignment transform |
| `embed figure with caption gets block comment wrappers` | Embed `<figure>` containing a `<figcaption>` still gets wrapped correctly |
| `two embeds with the same URL are each wrapped exactly once` | Two identical embed figures both get their own open/close block comments — regression for the `String.replace()` first-match-only bug |

### `toWordPressHTML` — footnotes (5 tests)

| Test | What it checks |
|---|---|
| `marker anchors are numbered in document order` | First `<sup data-fn>` gets `[1]`, second gets `[2]`, etc. |
| `renumbering is idempotent and corrects stale numbers` | Running `toWordPressHTML` twice does not change numbers, and a wrong number is fixed |
| `sup without data-fn is left alone` | Plain `<sup>` not treated as a footnote marker |
| `footnotes list does not gain wp-block-list` | `<ol class="wp-block-footnotes">` → no `wp-block-list` added |
| `ordinary ol still gains wp-block-list` | Regular `<ol>` without `wp-block-footnotes` still receives `wp-block-list` |

### `toWordPressHTML` — footnote marker anchors (3 tests)

Footnote bodies now live in post meta rather than in `post_content` (`docs/footnotes-meta.md`), so Quill writes core's marker anchor and no backref at all — WordPress renders the backref itself.

| Test | What it checks |
|---|---|
| `marker sup gains core's id="<fnId>-link"` | The anchor core's own renderer targets |
| `no backref is written into the list — WordPress renders it from meta` | Writing one would show two arrows on the published page |
| `marker id is idempotent across repeated transforms` | |

### `extractFootnotes` (6 tests)

The split that moves footnote bodies out of the content and into meta on save.

| Test | What it checks |
|---|---|
| `replaces the list with core's self-closing delimiter` | The content keeps `<!-- wp:footnotes /-->` and nothing else |
| `returns each footnote body keyed by its id, in document order` | |
| `keeps inline markup inside a footnote body` | Bold, links and the rest survive the move |
| `strips a legacy backref anchor from the stored body` | Posts written before the move carry an inline backref that must not end up in meta |
| `content with no footnotes is returned untouched` | |
| `leaves the rest of the block comments intact` | |

### `inlineFootnotes` (5 tests)

The inverse, run on load so the notes are editable in the editor.

| Test | What it checks |
|---|---|
| `materialises the list from meta at the delimiter` | |
| `restores footnotes in meta order` | |
| `round-trips with extractFootnotes` | |
| `empty meta leaves the delimiter alone for the passthrough card` | A delimiter with no meta behind it is shown as a non-editable card rather than an empty list |
| `meta without a delimiter in the content changes nothing` | |

### `toWordPressHTML` — gallery (16 tests)

| Test | What it checks |
|---|---|
| `gallery figure gets wp:gallery and wp:image comment wrappers` | `figure.wp-block-gallery` + nested `figure.wp-block-image` gets `<!-- wp:gallery {ids,columns,linkTo} -->` and per-image `<!-- wp:image {...} -->` comments |
| `gallery wrapping is idempotent` | Running `toWordPressHTML` twice produces byte-identical output — no compounding whitespace between images on repeated saves |
| `gallery image captions survive the save transform` | A `figcaption.wp-element-caption` inside a nested gallery image figure is still present after the transform — the generic figure pass reaches nested gallery figures, so no gallery-specific caption pass is needed |
| `a gallery caption stays the last child of its own nested image figure` | DOM-structural guard (replaces a weaker substring check): the caption is not hoisted onto the `figure.wp-block-gallery` wrapper, sits after its `<img>` as the figure's last element child, and belongs to the right image — the captionless second image gains none |
| `each gallery caption is wrapped inside its own wp:image comment pair` | Splitting the output on `<!-- wp:image ` puts each caption inside its own image's comment block, never in a sibling's — so WordPress attributes the caption to the correct image |
| `a captionless gallery image gains no figcaption` | Exactly one `<figcaption>` is emitted for a two-image gallery where only one image has a caption — no empty placeholders |
| `an unclassed gallery caption gains wp-element-caption` | A `<figcaption>` with no class (classic/hand-written markup) is annotated with `wp-element-caption` |
| `an empty gallery caption is removed` | A `<figcaption>` with empty text is dropped entirely rather than emitted blank |
| `wrapping a captioned gallery is idempotent` | Running `toWordPressHTML` twice over a captioned gallery is byte-identical — captions don't duplicate or drift across repeated saves |
| `outer gallery figure does not gain wp-block-image class` | The generic image-figure transform excludes `.wp-block-gallery`, so the wrapper figure isn't misclassified |
| `gallery with linkTo=media wraps images in anchors and records linkDestination` | Images already wrapped in `<a href>` produce `"linkTo":"media"` / `"linkDestination":"media"` |
| `cropped=false omits is-cropped class and sets imageCrop:false` | Missing `is-cropped` class → explicit `"imageCrop":false` (only emitted at the non-default) |
| `sizeSlug is read from the image figure class, not hardcoded` | `size-medium` on the image figure produces `"sizeSlug":"medium"`, not a hardcoded `"large"` |
| `an image with no wp-image-N class omits the id key instead of writing null` | Images without a recognized media ID omit `"id"` entirely rather than writing `"id":null` |
| `stripping pre-existing wp:image comments does not consume the images between them` | Regression guard: a loaded gallery's `sourceHTML` can have zero characters between one image's `<!-- /wp:image -->` and the next's `<!-- wp:image -->`; the strip regex must not greedily span past the first comment and delete the images between them |
| `stripping a pre-existing wp:gallery comment works even with a CR before its closing -->` | Regression guard: the non-greedy attrs group is `[\s\S]*?`, not `.*?` — a `\r` before a comment's own `-->` must not defeat the match entirely (JS `.` excludes all line terminators, not just `\n`) |

### `passthroughLabelFromClass` (2 tests)

| Test | What it checks |
|---|---|
| `strips wp-block- prefix and title-cases` | `'wp-block-accordion'` → `'Accordion'` |
| `splits multi-word block names on hyphens` | `'wp-block-media-text'` → `'Media Text'` |

### `passthroughLabelFromBlockName` (3 tests)

| Test | What it checks |
|---|---|
| `bare core block name` | `'accordion'` → `'Accordion'` |
| `namespaced core block name drops the namespace` | `'core/accordion'` → `'Accordion'` |
| `namespaced plugin block name with multiple words` | `'my-plugin/foo-bar'` → `'Foo Bar'` |

### `parsePassthroughBlock` (5 tests)

| Test | What it checks |
|---|---|
| `returns null for an element with no wp-block- class` | Not a passthrough candidate → `null` |
| `class-only element (no adjacent comments)` | `blockLabel` derived from class, `blockName`/`attrsJSON` both `null`, `sourceHTML` is the element only |
| `element with adjacent wp:name comments (no attrs)` | `blockName` recovered from the comment, `attrsJSON` stays `null` |
| `element with adjacent wp:name comments including JSON attrs` | `blockName` and `attrsJSON` both recovered verbatim from the comment |
| `mismatched open/close comment names are not treated as a pair` | Open/close comment names must match to be treated as a real wrapper; otherwise falls back to class-only label with `blockName: null` |

### `isModeledFigure` (8 tests)

`isModeledFigure(el)` answers the one question `gutenbergPassthrough`'s figure-only parse rule asks: is this `wp-block-*` figure one of the four Quill actually models (`QUILL_MODELED_FIGURE_CLASSES` — image, gallery, embed, table)? Everything else must fall through to a passthrough card instead of being shredded by the generic parser.

| Test | What it checks |
|---|---|
| `the modeled-figure set is exactly image, gallery, embed and table` | Drift guard on `QUILL_MODELED_FIGURE_CLASSES` — adding a class without also giving that figure a real parse rule silently sends the block to the generic parser; removing one freezes a working block into a passthrough card |
| `every class in the set is recognised on a figure` | Each modeled class → `true` |
| `figure blocks Quill does not model are not exempted` | `wp-block-audio`/`video`/`pullquote`/`playlist`/`media-text` → `false`, so they reach passthrough |
| `a modeled class alongside WordPress size/align classes still counts` | `wp-block-image size-large alignwide is-resized` → `true` |
| `matching is per-class, not substring` | The parse selector is substring-based (`[class*="wp-block-"]`) while the exemption is exact `classList` membership, so `wp-block-image-slider` and `wp-block-tableau` → `false` (a third-party block must not be handed to the image/table rule) |
| `a non-figure element carrying a modeled class is not exempted` | `div.wp-block-image`, `ul.wp-block-gallery` → `false` (non-figures are filtered separately) |
| `a figure with no wp-block class is not exempted` | Bare `<figure>` and classic `figure.wp-caption` → `false` |
| `null and undefined are handled without throwing` | Both → `false` |

### `toWordPressHTML` — passthrough blocks (8 tests)

| Test | What it checks |
|---|---|
| `an element with data-quill-passthrough-name gets wrapped in matching wp:name comments` | An element carrying the temporary marker attribute gets fresh `<!-- wp:name -->`/`<!-- /wp:name -->` comments, and the marker attribute is removed |
| `data-quill-passthrough-attrs is emitted inside the opening comment` | The temporary attrs-JSON attribute is written into the opening comment's text, verbatim, then removed |
| `an element with no data-quill-passthrough-name attribute is left alone` | Class-only passthrough content (no original comments) gets no comments added |
| `wrapping is idempotent` | Running `toWordPressHTML` twice produces byte-identical output |
| `a nested wp:image comment inside a passthrough block survives the strip (regression)` | The whole-string `wp:image` comment strip can't distinguish Quill's own pre-existing comments from a foreign comment nested inside a passthrough subtree; passthrough elements are stashed out before stripping and spliced back in verbatim so nested `wp:image` comments survive |
| `a nested wp:gallery comment inside a passthrough block survives the strip` | Same stash/splice protection, for a nested `wp:gallery` comment |
| `data-quill-passthrough marker is stripped even with no blockName (class-only passthrough)` | The unconditional shielding marker (set regardless of `blockName`) never leaks into saved HTML |
| `nested content survives byte-for-byte — headings/cite/figcaption inside a passthrough block are not normalized` | Regression guard (found in code review): `toWordPressHTML`'s heading/cite/figure normalization passes ran unconditionally over the whole tree, so a splice-back that happened too early let them reach into and mutate a passthrough block's nested content (adding `wp-block-heading`, deleting an intentionally-empty `<cite>`/`<figcaption>`). Fixed by delaying the splice-back until after every other whole-tree pass has run, so passthrough content is truly untouched, not just shielded from the comment-strip regex |

---

### standalone image block comments (9 tests)

| Test | What it checks |
|---|---|
| a standalone image figure is wrapped in a wp:image comment pair | Output is exactly comment / `figure.wp-block-image` / comment, asserted on nodes rather than substrings |
| the wp:image comment carries the media id | Attrs JSON is `{id:201}`, read off the `wp-image-{id}` class |
| an image with no media id is wrapped with no attributes | Bare `<!-- wp:image -->`, matching what core writes when it has nothing to record |
| a size class is carried into the comment as sizeSlug | `size-large` on the figure becomes `sizeSlug:'large'` |
| a linked image records linkDestination media | An `<a>` parent of the `<img>` becomes `linkDestination:'media'` |
| an aligned image records its alignment | `alignleft` (moved to the figure by the pass above) becomes `align:'left'` |
| gallery images keep exactly one wp:image pair and the gallery is not image-wrapped | Guard: the standalone pass skips anything inside `.wp-block-gallery`, so nested images are wrapped once by the gallery pass and the gallery figure itself gets `wp:gallery`, never `wp:image` |
| wrapping a standalone image is idempotent across repeated saves | `wp(wp(html))` is byte-identical to `wp(html)`, one comment pair — the strip-then-rewrap cycle does not stack |
| data-media-id never reaches the saved output | The attribute is gone and `wp-image-201` is present |


### `block delimiters` (6 tests)

The descriptor-driven delimiter pass added in the Gutenberg block-model work. `toWordPressHTML` used to emit `<!-- wp: -->` comments for only `wp:image`, `wp:gallery` and `wp:embed`; every other block got a `wp-block-*` class and nothing else, which is what Gutenberg reads as classic content.

| Test | What it checks |
|---|---|
| `wraps a paragraph in wp:paragraph` | A bare `<p>` comes out inside a `wp:paragraph` delimiter pair |
| `wraps an h2 with no level, which is core default` | Core omits `level` for `<h2>`, so Quill must too, or every heading diffs |
| `wraps an h3 with its level attribute` | An `<h3>` emits `<!-- wp:heading {"level":3} -->`, with the level read off the tag |
| `wraps a list and each of its items` | Both `wp:list` and the per-item `wp:list-item` delimiters are emitted |
| `does not double-wrap already-delimited content` | Saving already-delimited content twice is byte-identical — the guard against the comment-stacking regression class |
| `leaves gallery delimiters exactly as they are` | The gallery fixture still ends up with exactly one `wp:gallery` opener, so the new pass does not collide with the three blocks that already had delimiters |

### `delimiter attributes are escaped the way core escapes them` (4 tests)

Every delimiter goes through core's own `serializeAttributes`. A plain `JSON.stringify` passes every string test while writing a comment WordPress would re-escape — or one that terminates early.

| Test | What it checks |
|---|---|
| `an embed URL's query ampersand is escaped` | `&` in a URL comes out as `\u0026`, as core writes it |
| `a double hyphen in a carried class cannot close its own comment` | `--` escaped, so the value cannot end the HTML comment it sits in |
| `angle brackets in a carried value are escaped` | |
| `a block with no attributes still gets no trailing space` | `<!-- wp:paragraph -->`, not `<!-- wp:paragraph  -->` |

### `img and hr self-close, br does not` (5 tests)

Core self-closes the void tags in the two blocks whose markup it owns. Without this, an edited post diffs on every image and separator in its history.

| Test | What it checks |
|---|---|
| `a separator closes itself` | `<hr … />` |
| `an image closes itself` | `<img … />` |
| `a line break is left alone` | `<br>` stays as core writes it |
| `an angle bracket inside an attribute does not truncate the tag` | The pass is a regex over the serialized string, so `>` inside an attribute value has to be treated as data |
| `an already self-closed tag does not gain a second slash` | |

### `anchor and className supports` (23 tests)

Core's `anchor` and `customClassName` supports. A block that came from outside Gutenberg carries both only in its markup, so the delimiter has to be derived from the root element — and the derivation has to tell a class core's own `save()` generated from one the author wrote.

| Test | What it checks |
|---|---|
| `an id on a modeled block's root becomes the anchor` | |
| `a class the author wrote becomes className` | |
| `both together are emitted, anchor first` | Core's own key order |
| `a block with neither gets neither key` | |
| 14 generated-class cases | `wp-block-heading`, `has-text-color`, `has-large-font-size`, `is-resized`, `are-vertically-aligned-top`, `items-justified-left`, `wp-elements-*`, `wp-container-*` and the six alignment classes are each checked not to leak into `className`, which would put them in the delimiter twice |
| `is-style- is kept, because that is where a block style lives` | The one `is-` token that is not generated — it is what the style picker reads and writes |
| `only the custom tokens survive a mixed class list` | |
| `a block marked noAnchor keeps its id out of the delimiter` | Four blocks have no anchor support in their `block.json`; writing one makes Gutenberg reject the block. The `id` still rides the markup |
| `what WordPress carried wins over what the markup implies` | |
| `a carried key keeps its place ahead of a derived one` | WordPress's own key order is preserved, so a post does not come back with its delimiter attributes reshuffled on every save |

### `ordered list start and reversed` (5 tests)

`core/list` stores both on the block as well as on the markup.

| Test | What it checks |
|---|---|
| `a start other than 1 reaches the delimiter` | |
| `a start of 1 does not` | Core omits the default |
| `reversed reaches it as a boolean` | |
| `both together, in core's order` | |
| `an unordered list gets neither` | |

### `a code block language class moves to the pre` (5 tests)

`core/code`'s `save()` draws no class on the inner `<code>`, so a language class Claude wrote there has to move up or the block fails validation.

| Test | What it checks |
|---|---|
| `the class lands on the pre and leaves the code bare` | |
| `and is reported as the block's className` | |
| `a code block with no language is untouched` | |
| `the move is idempotent` | |
| `a preformatted block is left out of it` | `core/preformatted` is a different block and keeps its own markup |

### `trailing paragraph` (5 tests)

The editor keeps an empty paragraph after a block the caret cannot get past, and the save removes it again. The condition is scoped to exactly the shapes that paragraph follows — "drop the last child if it is an empty paragraph" also deletes an empty `core/paragraph` an author wrote at the end of a post, and the block tripwire cannot see the difference.

| Test | What it checks |
|---|---|
| `drops the empty paragraph the editor keeps after a table` | |
| `drops it after an image figure too` | |
| `keeps an empty paragraph that is not last` | |
| `keeps a trailing paragraph that has text` | |
| `never empties a document that is only an empty paragraph` | |

### `unsupported block unwrapping` (7 tests)

The save side of unsupported-block preservation. Each wrapper element is replaced by a sentinel text node before `innerHTML` is taken, then the sentinel is substituted for the stored source, so markup is restored byte for byte instead of being escaped as text.

| Test | What it checks |
|---|---|
| `restores a shortcode block exactly` | The stored source comes back, delimiters and all |
| `restores markup with quotes and entities exactly` | `&amp;` and `&lt;` survive the attribute round-trip unchanged |
| `leaves no marker attributes behind` | No `data-quill-unsupported`, `wp-block-quill-unsupported` or `data-quill-passthrough` in the output |
| `is idempotent` | Saving twice produces the same bytes |
| `restores two wrappers in document order` | Sentinels are substituted in order, not swapped |
| `restores a source containing a dollar sequence` | A shortcode holding `$&` is not mangled by `String.replace`'s substitution syntax, which is why the replacement is a function |
| `a post with no wrappers is unchanged by the pass` | The selector misses and the pass is a no-op |

## JS keyboard tests (76 tests)

File: `Scripts/test-editor-keyboard.js`
Editor file: `Sources/QuillKit/Resources/editor.html`

Tests load the real `editor.html` in jsdom, instantiate the live Tiptap editor via `window._tiptapEditor`, dispatch real `keydown` events, and assert on the resulting ProseMirror document. This is the only automated coverage of the Enter/Backspace/Shift-Enter handlers — the code paths that caused the June 2026 regression chain.

**jsdom caveat:** ProseMirror only keymap-binds Backspace at node boundaries (joinBackward/lift); mid-text character deletion is browser `beforeinput`, which jsdom does not emit — so only boundary Backspace is asserted.

### `plain paragraphs` (4 tests)

| Test | What it checks |
|---|---|
| `Enter at end of paragraph creates an empty paragraph below` | Basic paragraph splitting |
| `Enter mid-word splits the paragraph cleanly` | Mid-text split |
| `Backspace at start of 2nd paragraph merges into the first (joinBackward)` | Boundary backspace merges paragraphs |
| `Shift+Enter inserts a hard break, not a new paragraph` | Hard break insertion |

### `headings` (1 test)

| Test | What it checks |
|---|---|
| `Enter at end of a heading drops to a paragraph (not another heading)` | Heading exit behavior |

### `lists` (3 tests)

| Test | What it checks |
|---|---|
| `Enter at end of a list item creates a new item` | Normal list item creation |
| `Enter in an empty trailing item exits the list` | Empty item → lift out to paragraph |
| `Backspace at start of the sole list item lifts it to a paragraph` | Boundary backspace in lists |

### `blockquotes & cite` (4 tests)

| Test | What it checks |
|---|---|
| `Enter in a blockquote creates a paragraph inside the quote` | Normal blockquote paragraph splitting |
| `Enter on an empty paragraph inside a blockquote lifts out` | Empty paragraph → exit blockquote |
| `Enter with a selection deletes it before splitting (regression: 8a4f00f)` | Selection deleted before `tr.split`; re-derives depth after delete |
| `Enter inside a cite exits the blockquote to a new paragraph` | Cite Enter → new paragraph below blockquote |

### `footnotes` (2 tests)

| Test | What it checks |
|---|---|
| `Enter in a footnote entry inserts a soft break and keeps text (regression: cbf3e8d)` | Footnote Enter → hardBreak, not swallowed |
| `Backspace at the start of a footnote entry does not corrupt the doc (regression: daee820)` | Boundary backspace in footnotes |

### `image captions` (2 tests)

| Test | What it checks |
|---|---|
| `Enter in an image caption exits to a new paragraph below (regression: 91679d2)` | Caption Enter → paragraph after image |
| `Enter in an image caption inside a blockquote stays well-formed (no image duplication)` | Nested caption Enter doesn't duplicate image |

### `image link-to-full-size` (7 tests)

| Test | What it checks |
|---|---|
| `image wrapped in <a> parses to linkTo media with linkHref, and round-trips` | Loading a figure whose `<img>` is wrapped in `<a href>` recovers `linkTo: 'media'`/`linkHref`, and re-serializes the same `<a>` wrapper |
| `image without a link wrapper defaults to linkTo none and omits <a> from output` | Unwrapped `<img>` defaults to `linkTo: 'none'`, `linkHref: null`, no `<a>` in output |
| `linked image preserves alignment, custom class, and mediaId alongside the link` | `linkTo`/`linkHref` coexist with alignment, custom figure class, and `mediaId` through the round-trip |
| `toggling linkTo to media via setNodeMarkup produces the <a> wrapper on save` | Toolbar toggle path (`setNodeMarkup`) produces the `<a>` wrapper on save, not just the load path |
| `toggling linkTo back to none via setNodeMarkup clears linkHref too` | Regression: turning the link off also clears the stale `linkHref`, not just `linkTo` |
| `classic (non-figure) linked image is detected via the bare img[src] parse rule` | Regression: pre-Gutenberg `<a href><img></a>` markup with no `figure.wp-block-image` wrapper still parses `linkTo`/`linkHref` (previously silently dropped the link on save) |
| `an <a> wrapper with an empty href is not treated as a full-image link` | Regression: `<a href="">` around an image does not set `linkTo: 'media'` (previously showed the toggle as "on" for a link that wouldn't actually save) |

### `class preservation through schema round-trip` (15 tests)

Every block extension is wrapped by `withClassAttr()` so author-authored `class`/`id` attributes survive `setContent` → `getHTML()`. These tests assert that per node type, plus the filters that stop Quill's own managed classes from being duplicated into the preserved attribute.

| Test | What it checks |
|---|---|
| `custom class on paragraph survives setContent/getHTML round-trip` | `<p class="...">` preserved |
| `custom class on heading survives round-trip` | Heading class preserved |
| `custom class on image figure survives round-trip` | `figure` class preserved |
| `custom id on image figure survives round-trip` | `figure` `id` preserved |
| `custom class on code block survives round-trip` | `<pre>`/`<code>` class preserved |
| `custom class on list survives round-trip` | List class preserved |
| `custom class on blockquote survives round-trip` | Blockquote class preserved |
| `custom class on table element survives round-trip` | Table class preserved |
| `wp-block-image class on figure is filtered from figureClass (not duplicated)` | Quill's own managed class is not re-added by the preservation attribute |
| `custom class on img element survives round-trip` | `<img>` class preserved separately from the figure's |
| `managed img classes (alignment, wp-image) are not duplicated in imgClass` | `alignleft`/`wp-image-N` are re-derived on save, not stored twice |
| `custom class on cite survives round-trip` | `<cite>` class preserved |
| `custom class on link survives round-trip` | `<a>` class preserved |
| `custom class is not copied to new node on Enter (keepOnSplit)` | Splitting a block does not clone the author's class onto the new block |
| `applyLink preserves existing link classes` | The link picker's `applyLink` keeps classes already on the anchor |

### `image marked as decorative (WP 7.1)` (7 tests)

WordPress 7.1's "Mark as decorative" image toggle writes `role="none"` on the `<img>`. The `imgRole` attribute on `ResizableImage` parses it and round-trips it through `toWordPressHTML`, under both the `figure.wp-block-image` parse rule and the bare `img[src]` fallback.

| Test | What it checks |
|---|---|
| `role="none" on the <img> parses into imgRole and round-trips` | `role` is read into the `imgRole` attr on load and re-emitted on the `<img>` |
| `role survives the toWordPressHTML save transform` | The save transform does not strip the attribute while annotating the figure |
| `an image with no role attribute emits no role on save` | No `role` is invented for images that never had one |
| `role is preserved on a classic linked image with no figure wrapper` | The bare `img[src]` fallback rule also carries `role` through |
| `a classic bare img keeps its role through the save transform` | Classic (non-Gutenberg) `<img>` markup keeps `role` on save |
| `role stays on the img when the image also links to its full size` | With `linkTo: 'media'`, `role` lands on the `<img>` nested in the `<a>`, not on the anchor |
| `an empty role attribute is dropped rather than emitted as role=""` | `role=""` is treated as absent, not serialized as an empty attribute |

### `window.insertImage cursor placement` (14 tests)

`window.insertImage` used to leave the cursor inside the new figure's empty `<figcaption>`, so typing straight after an insert wrote caption text. It now inserts an empty paragraph after the image and puts the cursor there; the caption is left untouched and still clickable, so captioning is opt-in. All three insert paths share this function (toolbar insert, post-upload insert, Finder drop). Intended consequence: the saved WordPress HTML gains an empty `<p></p>` after the image block.

| Test | What it checks |
|---|---|
| `inserting into an empty document leaves the cursor in a paragraph below` | Baseline: cursor lands in a paragraph, not the caption |
| `inserting after existing text appends the paragraph after the image` | Existing content is preserved; the new paragraph follows the figure |
| `the caption is left empty and still holds the image attrs` | `figcaption` stays empty while `src`/`mediaId`/`alt` land on the image node |
| `three consecutive inserts stack in order with one trailing paragraph` | Consecutive inserts reuse the previous paragraph rather than stacking blank ones |
| `a multi-image drop saves one wp:image pair per image, in drop order` | Ids in drop order, two closing comments, no blank paragraph wedged between figures, save transform idempotent |
| `the saved figure carries no caption and no empty paragraph` | The new paragraph is a sibling *after* `<!-- /wp:image -->`, never inside the figure |
| `the paragraph below the image accepts typing` | Typed text lands in the paragraph, not the caption |
| `inserting with the cursor in an existing caption appends below, leaving the caption intact` | Inserting from inside a caption doesn't clobber that caption |
| `inserting while an image node is selected replaces it and still lands below` | Node-selection replace path also ends below the new image |
| `inside a list item the image and its paragraph stay in the item` | The figure serializes inside `<li>` — insert doesn't break out of the list |
| `inside a blockquote the image and its paragraph stay in the quote` | Insert stays scoped to the blockquote |
| `inside a table cell the image and its paragraph stay in that cell` | Insert stays scoped to the cell |
| `from a code block the image lands after the block, leaving the code untouched` | Code block content is not mutated by the insert |
| `inside a footnote the insert is refused and the document is unchanged` | Footnote entries reject image insertion outright |

---

## JS gallery tests (36 tests)

File: `Scripts/test-editor-gallery.js`
Editor file: `Sources/QuillKit/Resources/editor.html`

Tests load the real `editor.html` in jsdom and instantiate the live Tiptap editor via `window._tiptapEditor` — the same approach as the JS keyboard tests — because `galleryBlock`'s `parseHTML`/`renderHTML` can't be exercised through the pure `editor-transforms.js` helpers alone.

### `galleryBlock` — insert and render (6 tests)

| Test | What it checks |
|---|---|
| `inserting a galleryBlock renders wp-block-gallery figure with nested image figures` | Sheet-style insert (`images`/`columns`/`cropped`/`linkTo` attrs) reconstructs the correct DOM shape |
| `non-default sizeSlug is honored by the reconstruction render path` | Inserting with `sizeSlug: 'medium'` renders `class="wp-block-image size-medium"` on each nested image figure, not the `large` default |
| `linkTo media wraps each image in an anchor to its own url` | `linkTo: 'media'` wraps each `<img>` in `<a href>` pointing at its own URL |
| `linkTo media links to fullUrl (true original), not the display-size url` | Regression: when Size is a non-full display size, `linkTo: 'media'`'s anchor must link to `image.fullUrl` (the true original), not `image.url` (the smaller displayed image) |
| `linkTo media falls back to url when fullUrl is absent` | An `images[]` entry with no `fullUrl` field still produces a working anchor, linking to `url` |
| `cropped false omits is-cropped class` | `cropped: false` omits the `is-cropped` class from the rendered figure |

### `galleryBlock` — load (parseHTML) (4 tests)

| Test | What it checks |
|---|---|
| `loading real gallery HTML recovers images, columns, cropped, linkTo` | Parsing a real `figure.wp-block-gallery` recovers all structured attrs correctly, including `sizeSlug: 'large'` |
| `loading a gallery with a non-large size class recovers that sizeSlug` | A loaded gallery whose image figures have `size-medium` recovers `attrs.sizeSlug === 'medium'`, not the hardcoded default |
| `loading a gallery with images linked to media recovers linkTo=media` | Images already wrapped in `<a>` are recognized as `linkTo: 'media'` on load |
| `captures sourceHTML verbatim, including content the structured attrs do not model` | `sourceHTML` captures the original figure's `outerHTML` (e.g. a caption) that the structured attrs don't represent |

### `galleryBlock` — verbatim re-render (sourceHTML) (2 tests)

| Test | What it checks |
|---|---|
| `a loaded gallery with a caption re-renders with the caption intact` | `sourceHTML` is re-emitted unchanged, preserving captions and other unmodeled content |
| `sheet-inserted galleries (sourceHTML null) still use the reconstruction path` | Sheet-inserted galleries (`sourceHTML: null`) always reconstruct from structured attrs, never accidentally reuse a stale `sourceHTML` |

### `galleryBlock` — code-view round-trip (2 tests)

| Test | What it checks |
|---|---|
| `serialize via toWordPressHTML then re-parse preserves a sheet-inserted gallery` | Save → reload round-trip preserves images/columns/cropped/linkTo for a sheet-inserted gallery |
| `serialize then re-parse preserves a loaded, captioned gallery verbatim` | Save → reload round-trip preserves a caption on a loaded gallery via `sourceHTML` |

### `window.insertGallery` bridge function (4 tests)

| Test | What it checks |
|---|---|
| `inserts a galleryBlock from a JSON payload` | The Swift→JS bridge function parses a JSON payload and inserts a `galleryBlock` |
| `sizeSlug from the JSON payload propagates to node attrs, defaulting to large` | A `sizeSlug` key in the JSON payload reaches `node.attrs.sizeSlug`; an omitted key defaults to `'large'` |
| `ignores an empty images array` | An empty `images` array is a no-op — never inserts a gallery with zero images |
| `inserting at the end of the doc does not synthesize a trailing paragraph` | Confirms the caret-after-an-atom problem is solved purely via gap-cursor CSS, not doc-model surgery — the gallery stays the doc's last node and no phantom `<p></p>` leaks into saved HTML |

### Gap-cursor styling (1 test)

| Test | What it checks |
|---|---|
| `editor.html overrides the default gap-cursor widget to match the app caret` | Guards the CSS override (`.ProseMirror-gapcursor:after { border-left: 1.5px solid #007aff }`) that restyles Tiptap's built-in gap-cursor widget from its default black horizontal bar to the app's blue vertical caret |

### `galleryBlock` — per-image captions (8 tests)

Covers the per-image Alt text and Caption values the gallery sheet collects, as `renderHTML`'s reconstruction path emits them.

| Test | What it checks |
|---|---|
| `a non-empty caption renders as a wp-element-caption figcaption` | A `caption` on an `images[]` entry renders as `<figcaption class="wp-element-caption">` |
| `each caption lands inside its own image figure` | Two images, one captioned → the caption is inside the first image's figure and the second has no `<figcaption>` |
| `an omitted caption emits no figcaption at all` | An entry with no `caption` key emits no `<figcaption>`, not an empty one |
| `caption text containing markup is escaped, not injected` | Caption is written via `textContent`, never `innerHTML` — `<script>`/`<b>` in the caption is escaped, not parsed as markup |
| `the caption follows the anchor when linkTo is media` | With `linkTo: 'media'`, the figure's children are `<a>` then `<figcaption>`, matching Gutenberg's ordering |
| `each per-image alt lands on its own img, in order` | DOM-structural guard (replaces a weaker single-image check): three images with alts `['First alt', '', 'Third alt']` produce `<img>` alt attributes in that exact order, so alts can't be shifted onto the wrong image |
| `an omitted alt still emits an empty alt attribute` | An entry with no `alt` key still renders `alt=""` — WordPress markup always carries it, and a missing attribute is an accessibility regression |
| `alt text containing quotes and markup is escaped, not injected` | Alt comes straight from a `TextField`; `Bob & "Al" <b>bold</b>` round-trips as the literal attribute value with no element escaping out of the quoted value and nothing extra injected into the figure |

### `galleryBlock` — alt and caption round-trip (insert → save → re-parse) (4 tests)

Exercises the exact JSON payload `PostEditorView` builds from `GallerySelection` (one dict per image with `id`/`url`/`fullUrl`/`alt`/`caption`) through `window.insertGallery`, then out through `toWordPressHTML` and back in.

| Test | What it checks |
|---|---|
| `alt and caption from the JSON bridge payload reach the node attrs` | The Swift→JS bridge carries per-image `alt`/`caption` into `node.attrs.images`, including empty values and values containing quotes/markup |
| `alt and caption survive save and re-parse, per image and in order` | Save → reload preserves ids, alts and captions per image and in order — nothing is dropped, reordered, or double-escaped |
| `each caption is saved inside its own wp:image comment pair` | Each saved caption sits inside its own `<!-- wp:image -->`…`<!-- /wp:image -->` block; the captionless middle image's block contains no `<figcaption>` |
| `saving a captioned gallery is idempotent` | `toWordPressHTML` over its own output is byte-identical for a captioned gallery |

### `galleryBlock` — parsing captions from loaded galleries (3 tests)

| Test | What it checks |
|---|---|
| `a caption on a loaded image figure is extracted into node attrs` | `parseHTML` reads a loaded figure's `figcaption` back into `images[i].caption` via `textContent` |
| `an image with no figcaption parses to an empty caption` | A sibling image with no caption parses to `''`, not `undefined`/`null` |
| `a loaded gallery still re-renders verbatim from sourceHTML` | Extracting captions into attrs doesn't disturb the `sourceHTML` verbatim re-render path |

### `galleryBlock` — captions survive load → edit → save (2 tests)

Regression suite for the greedy-comment-strip class of bug (matrix row 91), re-run with captions present: every debounced save runs `toWordPressHTML(editor.getHTML())` over a loaded gallery's verbatim `sourceHTML`, and a `<figcaption>` adds another element between two adjacent `wp:image` comments.

| Test | What it checks |
|---|---|
| `both images and both captions are still there after an edit and save` | A two-image, fully-captioned loaded gallery plus a real intervening edit elsewhere in the doc → both image figures, both captions and both alts survive the save; the edit is asserted to have actually happened |
| `the edited save is idempotent — captions do not duplicate or drift` | Re-saving the edited output is byte-identical, with exactly two `<figcaption>`s and two `<!-- wp:image ` comments — no compounding on repeated saves |

---

## JS container tests (275 tests)

File: `Scripts/test-editor-containers.js`
Editor file: `Sources/QuillKit/Resources/editor.html`

Tests load the real `editor.html` in jsdom and drive the live Tiptap editor through `window._tiptapEditor` — the same approach as the gallery, keyboard and passthrough suites. A container node's `parseHTML`/`renderHTML`, its priority against `gutenbergPassthrough`, and the toolbar controls that add and remove children can't be exercised through the pure `editor-transforms.js` helpers.

Five container blocks are covered end to end — **Columns**, **Details**, **Buttons**, **Accordion**, **Tabs** — plus **Pullquote** and **Preformatted**. Each block is checked on four concerns: insert, type into, parse from real WordPress markup, and save with correct `wp:` delimiters that do not stack across repeated saves. Beyond that, three cross-cutting groups: block-attribute carrying and ownership (Phase 5/6), editor-only chrome staying out of saved markup, and the click affordances on container rows.

**jsdom caveat:** every element reports a zeroed `getBoundingClientRect` and Ranges have no client rects, so the *geometry* half of the click-target work — hit-box size as rendered, which character a pointer lands on — is verified in a real browser, not here. What this suite asserts instead is the CSS rule text and the dispatched-event behavior.

### `columns block` (8 tests)

| Test | What it checks |
|---|---|
| `inserts the requested number of columns` | `window.insertColumns(3)` produces one `columnsBlock` with three children |
| `typing lands in the targeted column only` | Text goes into the first column; the second stays empty |
| `parses a real columns block from WordPress markup` | Comment-delimited `wp:columns`/`wp:column` markup parses to `columnsBlock` with two children |
| `saves with wp:columns and wp:column delimiters` | One `wp:columns` opener and one `wp:column` per column |
| `does not stack delimiters across repeated saves` | save → reload → save leaves exactly one `wp:columns` |
| `+Col adds a column to the block the cursor is in` | Pressing the real `[data-cmd="addColumnBlock"]` control takes two columns to three |
| `-Col removes the current column but never the last one` | `deleteColumnBlock` goes 2 → 1, then refuses to go lower |
| `passthrough does not claim a columns block` | Class-only `div.wp-block-columns` still parses as `columnsBlock`, not `gutenbergPassthrough` |

### `details block` (4 tests)

| Test | What it checks |
|---|---|
| `inserts a summary and a body` | `insertDetails()` produces a `detailsBlock` whose first child is a `detailsSummary` |
| `parses WordPress details markup` | `wp:details`-delimited `<details class="wp-block-details">` parses to `detailsBlock` |
| `saves with wp:details delimiters` | The delimiter pair is emitted on save |
| `summary text stays in the summary on save` | `<summary>Mine</summary>` survives as a summary rather than being hoisted into the body |

### `buttons block` (21 tests)

The Link mark also matches `a[href]`, so without a `contentElement` it claimed the button's own anchor: the label saved twice over, and a button with no href lost its label out of the block entirely. Most of this group exists to pin that fix and the link-picker behavior built on it.

| Test | What it checks |
|---|---|
| `inserts one button by default` | `insertButtons()` produces a `buttonsBlock` with one child |
| `parses WordPress buttons markup` | Real `wp-block-buttons`/`wp-block-button` markup parses to `buttonsBlock` |
| `preserves the button href on save` | A loaded button's `href` survives the save transform |
| `saves with wp:buttons and wp:button delimiters` | Both delimiter types are emitted |
| `a button emits exactly one anchor` | Regression: exactly one `<a>` in the output, with the full core class list and href intact |
| `a button with no href keeps its label inside the block` | Regression: the label stays inside `div.wp-block-button` and nothing leaks past the closing `wp:buttons` delimiter |
| `two buttons keep their own labels and order` | Two anchors, Alpha before Beta, each with its own href |
| `a typed button label survives a save and reload` | A typed label round-trips, and the second save is byte-identical to the first |
| `applyLink inside a button sets the node href, not a mark` | The link picker writes the node's `href` attribute; the label text carries no marks |
| `a linked button still emits exactly one anchor` | Linking via `applyLink` does not add a second bare anchor |
| `removeLink inside a button clears the href` | `href` becomes `null` and no `href=` appears in the save |
| `a button link survives a save and reload` | Output is stable and the node attribute is recovered on reload |
| `applyLink outside a button still applies a link mark` | Ordinary prose still gets a normal `<a href>` link mark |
| `the Buttons group Link control opens the link picker` | Pressing the real `[data-cmd="buttonLink"]` posts once to `showLinkPicker` with an empty href |
| `the Buttons group Link control seeds the picker with the current href` | An already-linked button opens the picker pre-filled |
| `the main toolbar link control opens the picker from inside a button` | The row-1 link control works inside a button too |
| `a linked button lights up both link controls` | Main and group controls both carry `.active` |
| `an unlinked button lights up neither` | Neither control is active |
| `the controls follow applyLink and removeLink` | Both light up on link and go dark on unlink |
| `the group control goes dark outside a button` | Linked prose lights the main control only |
| `the button label is plain text, not a link mark` | The label has no marks; the href lives on the node |

### `buttons toolbar controls` (1 test)

| Test | What it checks |
|---|---|
| `+Button adds a button and -Button never removes the last` | 1 → 2 → 1, then a further press is refused |

### `accordion block` (5 tests)

| Test | What it checks |
|---|---|
| `inserts one item with a heading and a panel` | `accordionBlock > accordionItem > accordionHeading + accordionPanel` |
| `parses the real accordion fixture` | `fixtures/accordion-block.html` becomes one `accordionBlock` with two items |
| `heading text round-trips` | The fixture's heading text survives a save |
| `saves with all four delimiter types` | `wp:accordion`, `wp:accordion-item`, `wp:accordion-heading`, `wp:accordion-panel` |
| `does not stack delimiters across repeated saves` | The second save is byte-identical, with exactly one `wp:accordion` opener despite its `{"autoclose":true}` attributes |

### `accordion toolbar controls` (1 test)

| Test | What it checks |
|---|---|
| `+Item adds a section and -Item never removes the last` | 1 → 2 → 1, then a further press is refused |

### `tabs block` (7 tests)

Real WP 7.1 structure is `tabs > tab-list` (a button per tab) `+ tab-panels > tab-panel`. The label is stored twice — as the button's text and as each panel's `label` attribute — so the save transform reads it back off the button to keep the two in sync.

| Test | What it checks |
|---|---|
| `inserts the requested number of tabs` | `tabsBlock > tabList + tabPanels`, each with the requested child count |
| `parses the real fixture into editable nodes` | Tab button text and panel body text land in the right nodes |
| `round-trips the fixture through the save transform` | `wp:tabs`, `wp:tab-list`, `wp:tab-panels`, one `wp:tab-panel` per panel, and the `<button type="button" role="tab">` shape |
| `a panel label follows its tab button text` | Each `wp:tab-panel` delimiter carries the `label` read off its own button |
| `does not stack delimiters across repeated saves` | One `wp:tabs`, two `wp:tab-panel` after a reload-and-resave |
| `passthrough does not claim a tabs block` | The fixture parses as `tabsBlock` |

### `tabs toolbar controls` (2 tests)

| Test | What it checks |
|---|---|
| `+Tab adds a button and a panel together` | Both the tab list and the panel list grow to three — they can never drift out of step |
| `-Tab removes the pair and never the last tab` | Both drop to one, then a further press is refused |

### `insert menu` (9 tests)

| Test | What it checks |
|---|---|
| `the toolbar exposes an insert button` | `#insert-button` exists |
| `the menu lists every container block` | columns, accordion, tabs, details and buttons all present as `[data-insert]` items |
| `clicking a menu item inserts that block` | Clicking the Details item produces a `detailsBlock` |
| `clicking a menu item label inserts that block` | The label lives in a span, so a real pointer lands on the span rather than the button the previous test clicks |
| `every menu item uses the heading menu label typography` | All seven items carry a `.heading-menu-label` span |
| `the insert button is a labelled pill like the heading dropdown` | A text label plus exactly one chevron SVG — no icon glyph |
| `the menu closes after an insertion` | The `visible` class is dropped once a block is inserted |

### `contextual toolbar row` (13 tests)

| Test | What it checks |
|---|---|
| `every contextual group lives in row 2, not the main toolbar` | All eight groups (blockquote, table, columns, buttons, accordion, details, tabs, image-align) are children of `#toolbar-row2` |
| `the row is hidden in ordinary prose` | Not visible, and no group is shown |
| `the row appears for a container and names only that group` | An accordion shows `accordion-controls` and nothing else |
| `the row disappears again when the cursor leaves` | Moving to a paragraph hides the row |
| `a load leaves the heading indicator neutral even when the post opens on a heading` | `_clearToolbarContext` resets the heading indicator to `P` on load — the one part of the reset row 2 cannot see |
| `placing the caret in that heading restores the indicator` | The same indicator reads `H2` and lights up once the caret is inside the heading |
| `nested containers show both groups at once` | A button inside a column reveals both `buttons-controls` and `columns-controls` |
| `the main toolbar keeps the groups that are not cursor-contextual` | The AI group and the insert menu stay in row 1 |

### `pullquote and preformatted` (5 tests)

| Test | What it checks |
|---|---|
| `setPullquote produces a pullquote node` | The command creates a real node, not a styled blockquote |
| `a pullquote saves with wp:pullquote delimiters` | The delimiter pair is emitted |
| `setPreformatted produces a preformatted node` | The command creates a `preformatted` node |
| `preformatted saves with wp:preformatted delimiters` | The delimiter pair is emitted |
| `a pullquote is not claimed by passthrough` | `figure.wp-block-pullquote` reaches its own node |

### `pullquote and preformatted round-trips` (5 tests)

| Test | What it checks |
|---|---|
| `a pullquote wraps its content in exactly one blockquote` | `figure > blockquote > p`/`cite` with no doubled blockquote |
| `a pullquote is not stamped with wp-block-quote` | Regression: pullquotes used to be silently rewritten as quotes |
| `repeated save cycles do not grow the pullquote` | Three further load/save cycles stay byte-identical |
| `preformatted is not stamped with wp-block-code` | The two blocks stay distinct |
| `preformatted keeps its whitespace through a save cycle` | Leading indentation survives and the second save matches the first |

### `block attributes survive an edit` (3 tests)

| Test | What it checks |
|---|---|
| `accordion autoclose survives an edit` | `{"autoclose":true}` is still in the delimiter after typing |
| `a column width survives an edit` | `{"width":"33.33%"}` survives, though Quill has no width UI at all |
| `an attribute Quill does not model is still preserved` | `{"metadata":{"name":"FAQ"}}` comes back untouched |

### `the attribute carrier never reaches saved HTML` (8 tests)

Two tests per fixture, over `accordion-block.html`, `tabs-block.html`, `gallery-block.html` and `post-17780.html`.

| Test | What it checks |
|---|---|
| `<fixture> round-trips byte-identically with no edit` | `window.setContent` → `window.getContent` returns the file unchanged — the full editor path, not just the transform |
| `<fixture> leaks no carrier attribute after an edit` | `data-quill-block-attrs`, the internal carrier for delimiter attributes, never appears in saved output |

### `accordion autoclose is a real attribute` (5 tests)

WordPress writes `autoclose` only into the block comment — verified against core's `accordion/save.jsx`, which emits no DOM attribute for it — so the carrier is the only copy on load and `data-autoclose` is Quill-internal.

| Test | What it checks |
|---|---|
| `autoclose is parsed from the block comment, not data-autoclose` | The node attribute is `true` after loading comment-only markup |
| `autoclose renders into the editor DOM so attrsFrom can read it` | `data-autoclose` appears in the editor's own HTML |
| `toggling autoclose off clears the node attribute` | The toggle command sets it `false` |
| `toggling autoclose on sets the node attribute` | A freshly inserted accordion starts `false` and toggles to `true` |
| `data-autoclose never reaches saved HTML` | The internal attribute is stripped while the delimiter keeps `{"autoclose":true}` |

### `details showContent is a real attribute` (7 tests)

The opposite case to autoclose: core's `details/save.jsx` renders `open={showContent}`, so `open` is real saved markup and must survive.

| Test | What it checks |
|---|---|
| `showContent is parsed from the block comment` | Comment-only markup sets the node attribute |
| `showContent is parsed from the open attribute WordPress saves` | Markup as WordPress actually writes it also sets it |
| `showContent renders open into the editor DOM so attrsFrom can read it` | `<details open>` in the editor's HTML |
| `toggling showContent off clears the node attribute` | The toggle command sets it `false` |
| `toggling showContent on sets the node attribute` | A freshly inserted details block starts `false` and toggles to `true` |
| `open stays in saved HTML when showContent is true` | Both the `open` attribute and the delimiter attribute are written |
| `no open attribute is saved once showContent is turned off` | Turning it off removes `open` from the markup |

### `attribute toggles in the contextual toolbar` (3 tests)

| Test | What it checks |
|---|---|
| `the autoclose button flips the accordion attribute` | Pressing the real control toggles the node attribute both ways |
| `the open button flips the details attribute` | Same for details |
| `each control group is revealed only inside its own block` | Accordion controls show and details controls hide inside an accordion, and vice versa |

### `a descriptor owns its declared attributes` (4 tests)

The carrier preserves every attribute the delimiter held, which is what keeps unmodeled attributes safe — but it also means `attrsFrom` returning `{}` can't be told apart from "this block has no such attribute". A descriptor names the keys it owns; those are dropped from the carrier before the DOM values merge.

| Test | What it checks |
|---|---|
| `turning off an owned attribute removes it from the saved delimiter` | `autoclose` disappears entirely rather than sticking at its loaded value |
| `an unowned attribute is still preserved when an owned one changes` | `showContent` goes, `metadata` stays |
| `turning an owned attribute back on restores it` | The delimiter comes back with `{"autoclose":true}` |
| `a column width is not owned and survives an edit` | `columnBlock` deliberately does not own `width` — Quill has no UI for it, so the carried value is the only copy |

### `editor chrome stays out of saved markup` (11 tests)

Accordion, tabs and details carry editor-only chrome: a forced-open `<details>`, a collapsed-for-preview class, the active tab. All of it is applied as ProseMirror decorations, which live outside the document — this group is the guard that none of it can reach a save.

| Test | What it checks |
|---|---|
| `a details block is open in the DOM even when showContent is false` | Forced open so the body stays editable, with no `open` in the save |
| `showContent true still saves the open attribute` | The real attribute is not suppressed along with the chrome |
| `collapsing an accordion item changes the DOM and not the document` | The DOM gains `is-collapsed`; the save is byte-identical to before |
| `collapsing is a toggle` | A second press clears it |
| `collapsing one item leaves its sibling expanded` | Collapse is per-item |
| `a details block collapses for preview the same way` | Stays `open` in the DOM — CSS does the hiding — and `is-collapsed` never saves |
| `the first tab is active when the cursor is elsewhere` | Default active tab with the cursor outside the block |
| `putting the cursor in a tab panel activates that tab` | Button and panel both gain `is-active-tab`; the sibling panel does not |
| `putting the cursor in a tab label activates that tab` | Same from the tab-list side |
| `the active tab class never reaches saved markup` | No `is-active-tab` in the output |
| `an accordion survives collapse, edit and save without losing an item` | Both items and the edit are present, with no chrome classes |

### `accordion headings match current core save markup` (9 tests)

Quill's heading markup was copied from `post-17780.html`, which an older WordPress wrote. Current `core/accordion-heading` emits `has-icon` classes and a `+` icon span and never emits `wp-block-heading`, so the old shape matched no registered save or deprecation and Gutenberg rejected every accordion Quill saved. Expected markup was verified against the live site's own bundled `block-library.js` (`showIcon` defaults true, `iconPosition` defaults right).

| Test | What it checks |
|---|---|
| `an accordion Quill inserts saves the heading exactly as core writes it` | Exact class set, button `type`/`class`, title-then-icon child order, and an `aria-hidden` `+` icon span |
| `wp-block-heading is never emitted` | The class core dropped is not written |
| `an old-format heading is upgraded on an edited save` | Loading old markup and typing produces current markup |
| `showIcon false in the block comment suppresses the icon and its classes` | No `has-icon*` classes, no icon span, title text kept |
| `iconPosition left puts the icon before the title, as core does` | `has-icon-left` and icon-then-title child order |
| `saving a showIcon-false accordion twice is idempotent` | The second save matches the first |
| `showIcon false is recovered from the markup when the comment is gone` | An in-editor copy/paste re-parses rendered markup with no delimiter, so the `has-icon` class is the only surviving copy of the setting |
| `the icon span is not typed into and the title still takes the text` | Typing lands in the title span; the icon keeps its `+` |
| `the editor hides the icon span so the ::after affordance still reads` | The stylesheet sets `display: none` on the icon span inside the editor |

### `container rows read as clickable` (10 tests)

The toggle used to be a narrow hit zone — the right 32px of an accordion header, the left 22px of a details summary — with no cursor affordance, so nothing about the row said it could be clicked. The whole row is the target now, with the row's own text as the one exception so a title can still be typed into.

| Test | What it checks |
|---|---|
| `the accordion row cursor sits on the toggle button, which covers the row` | The toggle rule sets `cursor: pointer` and not `text` |
| `the accordion title keeps a text cursor, because clicking it types` | The title span rule sets `cursor: text` |
| `only the details arrow is a pointer target, not the summary text` | `summary::before` is `pointer`; `summary` itself is `text` |
| `the details arrow box is big enough to hit` | At least 22px square, and drawn with `mask` rather than `clip-path` — a clipped box is hit-tested only where it paints, so the pointer appeared over the triangle alone |
| `an accordion header has no hover tint` | No `:hover` background rule |
| `tab labels are pointer targets` | `button[role="tab"]` is `pointer`, not `text` |
| `pressing an accordion header row collapses the item` | A real `mousedown` on the header collapses it |
| `pressing the details arrow collapses it` | A real `mousedown` on the summary collapses the block |
| `pressing a header row with an empty title places the caret instead of collapsing` | An empty title has no text to aim at, so the row must yield the click or a new accordion could never be named |
| `collapse state still never reaches saved markup` | A press-driven collapse leaves no `is-collapsed` in the save |

### `empty titles show a hint` (15 tests)

An accordion heading or details summary with no text is zero-width, so there is nothing to click and nothing to see. The hint is a node decoration plus CSS, never text in the document.

| Test | What it checks |
|---|---|
| `a freshly inserted accordion marks its own title as untitled` | The `is-untitled` decoration |
| `a freshly inserted details marks its own title as untitled` | |
| `a loaded title with text is not marked` | |
| `typing a title clears the mark and an empty one brings it back` | |
| `every empty title in a multi-item accordion is marked, not just the focused one` | |
| `the mark is decoration only and never reaches saved markup` | |
| `the hint is drawn in CSS, never inserted into the document` | A widget decoration next to the caret makes WebKit drop every keystroke, so the hint has to be CSS |
| `the hint names each block` | |
| `the hint cannot swallow the click that would place the caret in it` | |
| `the hint is out of flow, so an untitled row is no taller` | |
| `the hint is legible in dark mode too` | |
| `the details status badge is drawn on the box, not the summary` | |
| `pressing an untitled accordion row seats the caret in the title, not the panel` | The deferred caret placement an untitled row needs |
| `pressing an untitled details summary seats the caret in the summary` | |
| `the details arrow still collapses an untitled details` | |

### `delete block control` (3 tests) and `a selected separator` (14 tests)

The ✕ button, ⌘⇧⌫ and the block selection all resolve through one list, `DELETABLE_BLOCKS`, so teaching Quill a new container gives it all three gestures at once. The separator is the awkward case: it is a leaf, so it is reachable only through the node selection, not the ancestor walk every other container uses.

| Test | What it checks |
|---|---|
| `the ✕ deletes a ${label} block` / `the ✕ is offered inside a ${label} block` | Generated per deletable type |
| `the ✕ is hidden in ordinary body text` | |
| `offers the ✕, named as a separator` / `is removed by the ✕` / `is removed by ⌘⇧⌫ too` | The separator through both gestures |
| `leaves the surrounding paragraphs alone` | |
| `the ✕ stays hidden with the caret merely next to one` | |
| `the table group no longer carries its own delete button` | One control, not one per block type |
| `a nested block is removed before the one holding it` | Innermost first |
| `the cursor lands in the block after the deleted one` / `…falls back to the block before when nothing follows` | |
| `deleting the only block leaves an empty paragraph to type in` | |
| `⌘⇧⌫ removes the block the cursor is in` / `…leaves ordinary body text alone` | |
| `the minus buttons still refuse to remove the last part` | A columns block cannot be emptied of columns |

### `leaving a container block` (26 tests)

Esc and double-Enter are the two ways out of a container. Both resolve through the same list as the delete gesture, so every container behaves the same way — and the behaviours deliberately left alone (table Enter, mid-panel splits, preformatted line breaks) are pinned so a future change has to be deliberate.

| Test | What it checks |
|---|---|
| `Esc leaves a tab panel / a column / a table / a preformatted block / a details body / a blockquote / a code block` | One test per container |
| `Esc leaves the first tab panel, not just the last` | |
| `Esc leaves a column without breaking the columns block apart` | |
| `Esc makes the paragraph to land in when the block is last` / `…reuses the paragraph already below instead of stacking a blank one` | |
| `Esc steps out one container at a time when nested` | |
| `Esc does nothing in ordinary body text` | |
| `Esc closes an open menu rather than leaving the block` | The editor keymap runs before the document-level listeners that close menus, so the menu case has to be handled explicitly |
| `Enter twice leaves the first tab panel / a column / a details body / an accordion panel / a pullquote` | |
| `Enter twice still lifts out of a blockquote` / `three Enters still leave a code block` | Pre-existing behaviour, unchanged |
| `Enter on a panel's only empty paragraph leaves without emptying it` | |
| `Enter in a table cell still just adds a paragraph` / `Enter mid-panel still splits the paragraph normally` | Deliberately left alone |
| `Enter in a preformatted block adds a line, not a paragraph` / `three Enters leave a preformatted block, trailing blank lines trimmed` | |
| `Enter in a pullquote makes a paragraph, never a citation` | |

### `citation control` (9 tests)

| Test | What it checks |
|---|---|
| `the control reads Cite rather than showing an icon` | |
| `the control is offered inside a pullquote` / `it still adds and removes a blockquote citation` | One control, both quote blocks |
| `it adds a citation to a pullquote` / `it removes a pullquote citation again` | |
| `the caret lands in the pullquote citation ready to type` | |
| `a pullquote citation saves inside the blockquote` | Where core puts it |
| `Enter in a pullquote citation leaves the pullquote` | |
| `the control stays hidden in ordinary body text` | |

### `the table figure, its classes and its caption` (8 tests)

| Test | What it checks |
|---|---|
| `the caption stays inside the figure rather than becoming a paragraph` | |
| `the figure keeps the style class core put on it` / `the class never lands on the inner table` | |
| `the block comment keeps both of its attributes` / `the caption never reaches the delimiter` | The caption is markup, not a block attribute |
| `a table with no caption gains no empty figcaption` | |
| `a classic bare table saves as a core/table figure with fixed layout off` | |
| `a bare fixed-layout table keeps the class on the table, not the figure` | |

### `table row sections` (8 tests)

A table's `<thead>`/`<tfoot>` are document structure, not a setting, so they are hand-written rather than derived from the settings registry.

| Test | What it checks |
|---|---|
| `a loaded footer row comes back in a tfoot` | |
| `head, body and foot come back in core's own order` | |
| `the body keeps only its own rows` | |
| `the whole fixture round-trips byte-identically through an edit` / `it is idempotent across a second cycle` | |
| `a classic all-th first row is still promoted to a thead` | |
| `a picker-inserted table saves a thead and a tbody` | |
| `RECORDED LIMIT: sections plus a colspan gain a phantom cell` | Asserts the known upstream limit, so a future fix fails this test and points at the note below |

### `header and footer section toggles` (12 tests)

| Test | What it checks |
|---|---|
| `both toggles live in the table controls` / `they are hidden outside a table` | |
| `they reflect the sections a loaded table has` / `a table Quill inserted reads as header-on, footer-off` | |
| `turning the footer on adds a tfoot row of the right width` / `turning it off again removes the row` | |
| `turning the header off drops the thead` / `turning it back on adds a header row of th cells` | |
| `adding a footer does not demote an implicit header row` | |
| `the header toggle still reads as on once a footer exists` | |
| `pressing Header with a footer present never makes a second header row` | |
| `the last remaining row is never removed` | |

### `the table style toggle` (5 tests) and `the footer row reads as a footer` (4 tests)

| Test | What it checks |
|---|---|
| `it is labelled with the style it turns on` / `it reflects a loaded style` | The stripes style |
| `turning it off strips the class and the comment attribute` / `turning it on writes both halves back` | Both halves, or Gutenberg invalidates the block |
| `the block class is never mistaken for a style` | |
| `a foot row carries a marker the CSS can reach` / `the marker never reaches saved markup` | |
| `it is tinted like the header row, in both themes` / `a heavier top border separates it from the body` | Editor preview only |

### `table size picker` (12 tests)

The Word-style grid the table button opens instead of inserting a fixed 3×3.

| Test | What it checks |
|---|---|
| `the grid is ten columns by eight rows` | |
| `the table button opens it instead of inserting` | |
| `hovering reports the size it would insert` | |
| `clicking inserts exactly that size, with a header row` | |
| `it closes after inserting` / `pressing the button again closes it` | |
| `arrows resize and Enter inserts` / `arrows never run past the edges of the grid` | Keyboard parity |
| `Escape closes it and inserts nothing` / `Escape belongs to the picker before it belongs to the editor` | |
| `it refuses inside a footnote` | |
| `the panel is themed for dark mode` | |

---

## JS passthrough tests (36 tests)

File: `Scripts/test-editor-passthrough.js`
Editor file: `Sources/QuillKit/Resources/editor.html`

Tests load the real `editor.html` in jsdom and instantiate the live Tiptap editor via `window._tiptapEditor` — the same approach as the JS gallery/keyboard tests — because `gutenbergPassthrough`'s `parseHTML`/`renderHTML` can't be exercised through the pure `editor-transforms.js` helpers alone.

`gutenbergPassthrough` has two parse rules: a non-figure catch-all (`[class*="wp-block-"]:not(figure)`) and, since 2026-08-19, a figure-only rule (`figure[class*="wp-block-"]`) that claims every `wp-block-*` figure except the four in `QUILL_MODELED_FIGURE_CLASSES`. Both halves are covered here, along with guards that neither rule steals an element a real node already claims.

### `gutenbergPassthrough` — class-only markup, no wp: comments (4 tests)

| Test | What it checks |
|---|---|
| `parses into a single gutenbergPassthrough node` | An accordion's `div.wp-block-accordion` (no adjacent comments) parses into exactly one `gutenbergPassthrough` node with `blockLabel: 'Accordion'`, `blockName: null` |
| `round-trips the essential markup through getContent()` | `data-wp-interactive`, the heading toggle class, and list item text all survive a save with no `<!--` comments introduced |
| `an unrelated edit elsewhere in the document does not disturb the passthrough node` | Typing into a paragraph before the accordion doesn't touch the accordion's markup — it's a real schema node, not text riding on the `_rawHTML` safety net |
| `renders a static card, not the raw accordion markup, in the editor DOM` | The live editor DOM shows a `.passthrough-card` labeled "Accordion", not an actual clickable `<button class="wp-block-accordion-heading__toggle">` |

### `gutenbergPassthrough` — comment-wrapped markup (2 tests)

| Test | What it checks |
|---|---|
| `recovers blockName and attrsJSON from adjacent comments` | `<!-- wp:accordion {"autoclose":false} -->`/`<!-- /wp:accordion -->` around the same markup populates `blockName: 'accordion'`, `attrsJSON: '{"autoclose":false}'` |
| `regenerates matching wp:accordion comments on save` | Saving re-emits `<!-- wp:accordion {"autoclose":false} -->`/`<!-- /wp:accordion -->` around the element |

### `gutenbergPassthrough` — nested media blocks survive save (regression) (2 tests)

| Test | What it checks |
|---|---|
| `a wp:image comment nested inside a passthrough wp:group survives getContent()` | A `wp:group` passthrough wrapping a real `wp:image` figure round-trips the nested `<!-- wp:image {"id":42} -->`/`<!-- /wp:image -->` comments and the `<img>` intact, with no `data-quill-passthrough*` marker leaking into the output |
| `surviving through getContent() is stable across repeated saves (idempotent)` | Saving twice in a row produces byte-identical output |

### `gutenbergPassthrough` — does not steal elements other rules already claim (11 tests)

| Test | What it checks |
|---|---|
| `a real gallery figure still parses as galleryBlock, not gutenbergPassthrough` | `figure.wp-block-gallery` still parses as `galleryBlock` |
| `a real image figure still parses as image, not gutenbergPassthrough` | `figure.wp-block-image` still parses as `image` |
| `a real embed figure still parses as embedBlock, not gutenbergPassthrough` | `figure.wp-block-embed` still parses as `embedBlock` |
| `a table wrapped in figure.wp-block-table still parses as a table, not gutenbergPassthrough` | Regression guard for the precedence gap found during planning: the table's figure wrapper has no dedicated rule of its own and relies on `:not(figure)` to stay out of the catch-all's reach |
| `a heading with a wp-block-heading class still parses as heading, not gutenbergPassthrough` | Bare-tag rules (heading, by extension list, quote, code, hr) keep winning regardless of their `wp-block-*` class |
| `a wp-block-list <ul> still parses as a bulletList, not gutenbergPassthrough` | `ul.wp-block-list` → `bulletList` |
| `a wp-block-list <ol> still parses as an orderedList, not gutenbergPassthrough` | `ol.wp-block-list` → `orderedList` |
| `a wp-block-footnotes <ol> still parses as footnotesList, not gutenbergPassthrough` | `ol.wp-block-footnotes` → `footnotesList` |
| `a wp-block-quote blockquote still parses as a blockquote, not gutenbergPassthrough` | `blockquote.wp-block-quote` → `blockquote` |
| `a wp-block-code <pre> still parses as a codeBlock, not gutenbergPassthrough` | `pre.wp-block-code` → `codeBlock` |
| `a wp-block-separator <hr> still parses as a horizontalRule, not gutenbergPassthrough` | `hr.wp-block-separator` → `horizontalRule` |

### `gutenbergPassthrough` — unmodeled blocks on tags core nodes also match (3 tests)

| Test | What it checks |
|---|---|
| `a wp-block-social-links <ul> parses as gutenbergPassthrough, not a bulletList` | A `<ul>` the list extension would otherwise claim is recognised as an unmodeled block instead |
| `its anchors and icons survive a save that round-trips through Tiptap` | The social links' `<a>`s and inline SVG icons come back unchanged |
| `an unmodeled <pre> block (wp-block-verse) is preserved, not turned into a code block` | `pre.wp-block-verse` stays a verse block rather than being rewritten as a code block |

### `gutenbergPassthrough` — figure-rooted blocks Quill does not model (5 tests)

Before 2026-08-19 the catch-all excluded every `<figure>`, on the assumption Quill modeled them all. It models four. Every other `wp-block-*` figure was destroyed on save; these tests pin the fix.

| Test | What it checks |
|---|---|
| `a wp:playlist figure parses to gutenbergPassthrough, not shredded into loose nodes` | WordPress 7.1's new Playlist block becomes one passthrough node instead of a pile of loose paragraphs |
| `a wp:playlist figure survives a save byte-for-byte, comments and all` | The figure, its `<!-- wp:playlist -->` comment pair, and its `<figcaption>` all come back intact |
| `an audio figure is preserved rather than reduced to its caption text` | Regression: `figure.wp-block-audio` used to collapse to a bare `<p>` holding only the caption. Asserts `<audio>` and `figcaption.wp-element-caption` are still direct children with the right caption text, nothing hoisted out, and no `wp-block-image` class added |
| `a video figure is preserved rather than emptied` | Regression: `figure.wp-block-video` used to collapse to an empty `<p>` |
| `a pullquote figure stays a pullquote instead of being rewritten as a quote` | Regression: `figure.wp-block-pullquote` was silently rewritten as `blockquote.wp-block-quote`. Asserts `figure > blockquote > p`/`cite` nesting and text, the body child count, and that no `wp-block-quote` class is stamped on |

### `gutenbergPassthrough` — modeled figures still go to their own nodes (4 tests)

Specificity guards for the new figure rule: the four figures Quill does model must never reach the catch-all.

| Test | What it checks |
|---|---|
| `a wp-block-image figure still parses as an image` | `figure.wp-block-image` → `image` |
| `a wp-block-gallery figure still parses as a galleryBlock, nested image figures included` | `figure.wp-block-gallery` → `galleryBlock`, with its nested image figures intact |
| `a wp-block-embed figure still parses as an embedBlock` | `figure.wp-block-embed` → `embedBlock` |
| `a wp-block-table figure still parses as a table` | `figure.wp-block-table` → `table` |

### `gutenbergPassthrough` — figure blocks and the rest of the document (4 tests)

| Test | What it checks |
|---|---|
| `a playlist figure is stable across repeated load/save cycles` | Idempotency: the `wp:playlist` comment-pair count is unchanged across two save cycles (no comment stacking) |
| `passthrough figures keep their position among modeled blocks` | Asserts the exact top-level node-type sequence and output element/class sequence `p, figure.wp-block-audio, h2.wp-block-heading, figure.wp-block-image, p` — a passthrough figure does not migrate to the top or bottom of the document |
| `an unmodeled figure containing an img is not rewritten into an image block` | The passthrough stash shields a third-party figure that happens to hold an `<img>`: arbitrary attributes are kept, an empty `<figcaption>` is not pruned, and no `data-quill-passthrough*` marker leaks |
| `a classic figure with no wp-block class still parses as an image` | Guards the new `figure[class*="wp-block-"]` selector against claiming classic-editor image markup |

---

## JS paste tests (19 tests)

File: `Scripts/test-editor-paste.js`
Editor file: `Sources/QuillKit/Resources/editor.html`

Loads the real `editor.html` in jsdom and drives the live Tiptap editor, covering both clipboard branches — `transformPastedText` and `transformPastedHTML` (see the paste-path gotcha in `Sources/QuillKit/Resources/CLAUDE.md`) — plus `window.insertMarkdown`. Assertions are made against a flattened string form of the resulting ProseMirror document, so structure and text are both pinned.

**jsdom caveat:** jsdom has no `DataTransfer`, so the suite hand-builds `event.clipboardData`. It therefore exercises the flavors the tests construct, not what WKWebView actually delivers (RTF, webarchive, Word conditional-comment HTML, syntax-highlighted HTML from code editors). Treat green here as weaker evidence than the keyboard suite, and confirm real pastes in the app.

### `paste into footnotes` (4 tests)

| Test | What it checks |
|---|---|
| `multi-line plain text stays inside the footnote` | Blank-line-separated text collapses into the one footnote item instead of breaking out into body paragraphs |
| `single-line plain text is inserted unchanged` | Surrounding whitespace is trimmed, text lands in the footnote |
| `block HTML is flattened into the footnote` | A heading and a list paste in as plain text — the pre-existing `transformPastedHTML` guard |
| `CRLF and lone-CR line endings collapse the same way` | Windows and old-Mac line endings behave like `\n` |

### `paste into the body is unaffected` (3 tests)

| Test | What it checks |
|---|---|
| `multi-line plain text still becomes one paragraph per line` | The footnote handling did not change ordinary paste |
| `single-line plain text is inserted as-is` | One paragraph, no wrapping |
| `block HTML keeps its structure` | A heading and a list arrive as a heading and a list |

### `window.insertMarkdown` (11 tests)

| Test | What it checks |
|---|---|
| `converts headings, lists and inline marks` | Headings, list items and bold/italic all survive conversion |
| `converts blockquotes, fenced code and horizontal rules` | Each becomes its own node type |
| `emits no blank paragraphs between blocks` | No empty paragraphs padding the output |
| `converts tables` | GFM tables become real table nodes |
| `keeps images, matching what an HTML paste does` | Image handling is consistent with the HTML paste path |
| `task list checkboxes degrade to plain list items` | Quill has no task-list node, so checkboxes become ordinary items rather than raw text |
| `strips raw script tags in the source` | `<script>` in Markdown source does not reach the document |
| `refuses inside a footnote and leaves the document untouched` | Refusal is total — no partial insert |
| `refuses inside a code block and leaves the document untouched` | Same for code blocks |
| `reports empty input without touching the document` | Empty input is reported, not inserted |
| `inserts at the cursor rather than replacing the document` | Existing content survives the insert |

### `paste into a code block preserves line breaks` (1 test)

| Test | What it checks |
|---|---|
| `multi-line plain text keeps its newlines inside a code block` | Newlines are not collapsed into spaces the way they are in a footnote |

---

## JS footnotes tests (36 tests)

File: `Scripts/test-editor-footnotes.js`
Editor file: `Sources/QuillKit/Resources/editor.html`

Loads the real `editor.html` in jsdom. `core/footnotes` is a dynamic block with no `save()`, so the bodies live in post meta rather than in `post_content`: Quill sends `<!-- wp:footnotes /-->` plus a `meta.footnotes` JSON array. The full contract is in `docs/footnotes-meta.md`. The split crosses `setContent`, `getContent`, `getFootnotes()` and code view, so none of it is reachable from the pure helpers.

| Group | Tests | What it checks |
|---|---|---|
| `the transform helpers reach the editor as globals` | 1 | `extractFootnotes`/`inlineFootnotes` are callable in the page — the classic-script global-exposure boundary |
| `loading a post with native footnotes` | 3 | A delimiter plus meta becomes an editable list; the block is not frozen into an unsupported card; a delimiter with **no** meta behind it falls through to a passthrough card instead |
| `saving` | 8 | `post_content` carries the delimiter and never the list; `getFootnotes()` matches what core stores; an edited body reaches the meta; the marker keeps core's `<fnId>-link` anchor; no backref is written into `post_content`, because WordPress renders it; an unedited post saves back byte-identically; a second load/save cycle is idempotent; deleting the last marker clears the meta rather than stranding it |
| `migrating a legacy inline list` | 3 | A post written before the move is left exactly as it was until it is edited; the first edit moves the bodies into meta and the list out of the content; the legacy backref anchor does not survive into the meta |
| `two footnotes` | 3 | Both bodies load in meta order, survive a round trip in order, and the markers renumber 1, 2 |
| `inserting a brand-new footnote` | 3 | A post with none gains the delimiter and a meta entry, the marker anchors to the id core renders the backref for, and typing reaches the meta body |
| `code view shows what will actually be saved` | 4 | Code view shows the delimiter rather than the list (`_enterCodeView` builds its own source string, so `getContent`'s extraction had to be duplicated there); entering and leaving without editing keeps the meta; the list comes back in the visual editor afterwards |
| `backref chrome in the editor` | 8 | The trailing break stays in layout so an empty item keeps its caret (hiding it makes the item uneditable in WebKit); the backref is hidden through a node-view class rather than a `:has()` on the break, which WebKit does not re-evaluate when the break goes; the class tracks the item emptying and filling; the backref and marker opt out of the ⌘-held underline affordance, specifically enough to beat the rule they override; the backref is never serialized into `post_content` |
| `link colour is defined once per theme` | 3 | Both themes declared as variables on `:root` and `body.dark`; prose links, footnote markers and backrefs all read the variable; nothing carries a hard-coded colour |

---

## JS inline format tests (20 tests)

`Scripts/test-editor-inline-formats.js` — the real `editor.html` in jsdom. Covers the
inline marks Quill has no toolbar control for, and the Link mark's attribute carrier.

| Test | Checks |
|---|---|
| `<sub>`, `<sup>`, `<kbd>`, `<mark>`, `<abbr>` survive a load → edit → save | the `rawInline` mark preserves a tag and its attributes |
| a blockquote cite still parses as a cite node | the mark does not steal `<cite>` |
| bold, italic, strike, code and links are untouched | the mark does not shadow the core marks |
| the `inline-formats.html` fixture round-trips byte-identically | whole-fixture guard, no edit |
| the fixture keeps every format after an edit | whole-fixture guard, edited |
| title and data attributes survive an edit | the Link mark's `rawAttrs` carrier (F12) |
| the anchor round-trips byte-identically with no edit | carried attributes land in source order |
| the modelled attributes still win over the snapshot | a re-linked anchor takes the new `href`, keeps its `title` |
| a plain link gains nothing | no empty attributes added |

## JS block settings registry tests (13 tests)

File: `Scripts/test-block-settings-registry.js`
Source: `Sources/QuillKit/Resources/block-settings.js`

Pure Node, no DOM. Guards the registry's own shape before any consumer touches it: every entry names a known `kind`, every `flagClass` declares `class`/`when`/`default`, every `valueClass` pattern contains `{}`, every `attr` names an attribute, and no entry names a block `block-descriptors.js` has no descriptor for. It also reads its own source to fail on a **repeated block key** — a second `buttonBlock:` literal silently discards the first with no runtime error, which cost a real bug.

---

## JS block settings tests (227 tests)

File: `Scripts/test-editor-block-settings.js`
Editor file: `Sources/QuillKit/Resources/editor.html`

Loads the real `editor.html` in jsdom. The registry generates Tiptap attributes, delimiter keys and toolbar controls, so each half has to be exercised where it actually runs.

| Group | What it checks |
|---|---|
| `className survives on container blocks` | The carried class is spliced into the rendered class list and back into the comment, never doubled |
| `registry-generated attributes` | `accordionItem.openByDefault` parses comment-first, renders `is-open`, and settles the wrapper nesting order |
| `the delimiter half comes from the registry` | `attrsFromSettings`/`ownedAttrsFor` replace a hand-written `attrsFrom` |
| `the toolbar control comes from the registry` | A generated control appears only inside its block, reflects the value, and flips it |
| `block styles` | Button, quote, separator, image and table each keep a style through a save, replace rather than stack, and leave the user's own classes alone |
| `the tabs default tab` | A control on the panel writing `activeTabIndex` onto the tabs block, with the mark suppressed on a lone tab (where it would be noise) and back the moment a second tab exists |
| `a button / a prose link opening in a new tab` | `target` and `rel` as markup only, with core's own `noopener` append-and-trim |
| `the New tab control is gated on the link existing` | The one `showWhen` that names the node's own `href` rather than a sibling setting: hidden on an unlinked button, shown the moment a link is set, hidden again when it is cleared, and left standalone rather than paired with the style toggle |
| `accordion icons propagate to every heading` | Core stores `showIcon`/`iconPosition` twice, so the control writes the block and every heading in one transaction — one undo reverses the lot, and an item added afterwards inherits them |
| `the whole settings fixture corpus` | All twelve `settings-*.html` come back untouched with no edit, and save idempotently once edited |
| `sibling blocks are separated by a blank line` | Quill now writes core's blank line between sibling blocks inside a container, and a block that already carries its own delimiters is not given a second one |
| `every class-writing setting claims its class` | A drift guard with no runtime symptom: a setting that writes a class on its node's own root needs that node to claim `class` in `RAW_ATTRS_MODELED`, or the raw-attribute replay puts the source's class list back and resurrects the token the user just turned off |
| `every registry entry is covered` | Fails if a registry entry's name appears in no test — the drift guard |

**Recorded limit — sections plus colspan.** When a table has explicit `<thead>`/`<tfoot>` *and* a colspanned body cell, ProseMirror pads every row to a uniform cell count at parse time, so the header and footer each gain a phantom empty cell. This is upstream of anything the save transform can reach; in isolation colspan round-trips correctly and sections round-trip correctly, and only the combination fails. `test-editor-containers.js`'s `RECORDED LIMIT: sections plus a colspan gain a phantom cell` **asserts the phantom cell**, so if it is ever fixed upstream that test fails and points here.

**Blank lines between sibling blocks.** Gutenberg separates sibling blocks with a blank line and Quill now does the same (`sibling blocks are separated by a blank line`). The fixture corpus test still asserts idempotency after an edit rather than byte-identity against the fixture, because several fixtures were captured with single newlines in the gaps.

---

## Manual / functional test checklists

Run these against a real WordPress test site (or a local Docker WordPress) using an Application Password. Before each pass, quit the running app first — `build.sh` replaces the binary underneath it, so skipping the quit tests the old build:

```bash
osascript -e 'quit app "Quill"' 2>&1; sleep 2 && ./build.sh 2>&1 && open Quill.app
```

> Tip: use a disposable WordPress instance so destructive tests (delete, trash, publish) don't pollute a real site.

### 7.1 Authentication & onboarding

- [ ] Launch with no saved credentials → login/preferences screen appears.
- [ ] Enter a valid site URL, username, and app password → app connects and post/page lists appear.
- [ ] Enter a site URL without `https://` (e.g. `example.com`) → app either adds the scheme automatically or shows a clear error.
- [ ] Try a site URL with a trailing slash, a subdirectory install (`example.com/blog`), and a non-standard port → all connect successfully.
- [ ] Enter a wrong password → a readable error message appears (not a silent failure or crash). Quit and relaunch → the app still shows the login screen (bad credentials were never written to disk, since validation now happens before the save).
- [ ] Enter a URL for a non-WordPress site or one with the REST API disabled → a clear error appears.
- [ ] Paste an app password that contains spaces → authentication succeeds (WordPress app passwords normally have spaces).
- [ ] No macOS Keychain password prompt appears during normal use.
- [ ] Quit and relaunch → credentials are remembered and lists reload without re-entering them. A spinner appears during loading — the empty-state placeholder does NOT flash before posts arrive.
- [ ] Change the site URL in settings → lists update to the new site; any saved AI sample posts are cleared.

### 7.2 Sidebar, lists, navigation

- [ ] Posts, Pages, Local Drafts, and Media sections each load and show their items.
- [ ] The section picker sits at the top of the sidebar, not in the window toolbar. Each segment carries an icon; hovering a segment shows a hover state and the pointer does not change to a resize cursor.
- [ ] Switch sections with the picker → the list, the search prompt and the editor empty state all follow, and the selection in the old section is not carried over.
- [ ] Clicking a sidebar item highlights it with Quill's amber accent (not the default macOS blue). This holds only while the user's System Settings accent is "Multicolor" — see the root `CLAUDE.md`.
- [ ] Type in the search field → the current section filters case-insensitively; clearing the search restores all items.
- [ ] **Search field focus.** On launch the search field does *not* hold focus (no caret, typing does not land in it). Click it → it takes focus. Then press Tab from elsewhere, or turn on Full Keyboard Access → the field is reachable without the mouse.
- [ ] The search prompt names the section: Search Posts, Search Pages, Search Drafts, Search Media.

**Sidebar focus — the three checks.** Nothing here is automatable: the bug only appears once the WKWebView holds first responder, and scripted clicks cannot put it there (see the scripted-clicks gotcha in `docs/gotchas.md`). A selected row draws *emphasized* (solid amber, white text) when the list has focus and *unemphasized* (flat grey) when it does not. Grey is the failure. Last run green on 2026-09-20.

- [ ] **The main case.** Open a post, click into the editor body and type a character, then click a different post in the sidebar → the newly selected row is amber, not grey.
- [ ] **Media round trip.** Click into the editor body, switch to Media, click a few thumbnails, switch back to Posts and click a row → the row is amber and nothing flickers. `focusPostList()` returns early in Media mode; this checks the return trip still works.
- [ ] **Settings open.** Open Settings (⌘,) and leave it open, click back on the main window and select a different post → the row is still amber. Clicking the main window makes it key first, so `NSApp.keyWindow` is correct by the time the handler runs.
- [ ] Collapse the sidebar with the toolbar toggle → the toolbar shows only the sidebar toggle; Refresh and the + menu are gone. Expand it again → the order is toggle, Refresh, +, all above the sidebar. Press ⌘R → the current section still refreshes. The shortcut lives on View → Refresh, not on the toolbar Refresh button, so a collapsed sidebar must not take it away.
- [ ] When a section is empty (no posts, no pages, no drafts, no media), a descriptive placeholder appears. The editor empty state says "post", "page", or "draft" depending on the active section.
- [ ] Switch to the Media section → the post list, search bar, and toolbar are replaced by a thumbnail grid.
- [ ] Scroll to the bottom of the Posts or Media list → more items load automatically; loading stops when all items have been fetched.
- [ ] The dividers between sidebar/editor and editor/settings panels have no drag cursor — they are fixed boundaries, not resizable splitters.
- [ ] Click the native sidebar toggle at the left of the window toolbar → the sidebar collapses; click again → it returns. The detail column expands to fill the space. `NavigationSplitView` owns this; there is no app-side visibility flag any more.
- [ ] Upload a PDF via the Media tab → the sidebar cell shows a document icon (not a broken image); the detail panel shows a document icon with "Preview unavailable" (not "Image unavailable"); no alt text field appears.
- [ ] Collapse and expand the sidebar repeatedly → the post list does not refetch from the server each time (no spinner flash). The `lastLoadedCredentials` guard is what prevents it; collapsing no longer remounts the view, so this is now a guard against future remounts rather than a live trigger.
- [ ] **Sidebar width.** Delete the saved window state (or launch on a fresh account) → the sidebar opens at about 310pt. Drag it narrower → it stops at 260pt. Quit and relaunch → it never restores below 260pt.
- [ ] **Offline, Local Drafts shows the drafts and no error.** Turn off Wi-Fi and launch → Local Drafts lists every saved draft. The sidebar shows no error row, the empty-state overlay does not appear, and the detail placeholder does not say "Couldn't load…". Switch to Posts → the error row and "Couldn't load posts" appear there.
- [ ] A failed load in Posts, Pages or Media says "Couldn't load …", not "No … yet". The error triangle lines up with the first line of the error text, not the middle of a wrapped message.

### 7.3 Editor — content & Gutenberg round-trip

- [ ] Open an existing remote post → content renders the same as it does in WordPress.
- [ ] When clicking a post, the editor briefly shows "Start writing..." while loading, then content appears. Content should be complete and not truncated.
- [ ] Apply each formatting option: bold, italic, strikethrough, inline code, links, headings (h1–h6), bullet lists, numbered lists, blockquote, code block, table. Each renders correctly.
- [ ] Save a post containing all formatting types → fetch the raw content via the WordPress REST API (`?context=edit`). Verify: headings have `wp-block-heading` class, lists have `wp-block-list`, tables are wrapped in `figure.wp-block-table`, images are wrapped in `figure.wp-block-image`, and the first all-header row in a table is promoted to `<thead>`.
- [ ] Open a post, save it without making any changes, then fetch the raw content → it should be identical to before (no drift).
- [ ] Multi-paragraph list items survive a save without being collapsed into a single paragraph.
- [ ] **Block fidelity round trip.** In Gutenberg, make a post with: a paragraph given a text colour and a font size, a button given background and text colours and a border radius, an accordion whose heading has a text colour, a quote containing a heading and a list, a default table, an image linked to a custom URL with "open in new tab", a Group, and a Media & Text. Save. Open it in Quill, type one character in an unrelated paragraph, save. Reopen in Gutenberg → **no block shows "Block contains unexpected or invalid content"**, and every colour, radius, link target and table layout is as it was. This is the one check `--check-fixtures` cannot make, because only Gutenberg runs Gutenberg's validator.
- [ ] Open a **classic** (pre-Gutenberg) post, type one character, save → the post is converted to blocks. Expected, not a bug; confirm no prose is lost, and note that a wrapper `<div>` with a custom class does not survive.
- [ ] A post containing a Group or Media & Text shows a "Not editable in the visual editor" card with a peek of its source, and saving without touching it leaves the post byte-identical.
- [ ] **Blockquote behavior:**
  - [ ] Toggle blockquote on → text is wrapped in a blockquote.
  - [ ] Click the cite toggle button (bookmark icon, appears in toolbar when inside a blockquote) → an empty cite line appears at the bottom (subdued, right-aligned). Click again → the cite is removed.
  - [ ] Type an author name in the cite line, save → `<cite>` persists in the saved HTML.
  - [ ] Leave the cite line blank, save → no empty `<cite>` appears in the saved HTML.
  - [ ] Press Enter inside the cite → cursor exits the blockquote into a new paragraph below.
  - [ ] Press Enter at the end of a paragraph inside a blockquote → a new paragraph is created inside the blockquote (not outside it).
  - [ ] Press Enter in an empty paragraph inside a blockquote → the empty paragraph exits the blockquote (lift out).
  - [ ] Press Backspace in an empty cite → the cite is deleted (not the entire blockquote).
  - [ ] Toggle blockquote off → the quote and its cite are removed cleanly.
- [ ] Write content with curly quotes, emoji, and non-Latin scripts → save and reload → characters are preserved exactly.
- [ ] Open or create a very long post (10k+ words) → the editor stays responsive; save completes successfully.
- [ ] Paste content from Word, Google Docs, or Safari → HTML is reasonable; no script tags or unexpected elements injected.
- [ ] **Unmodeled Gutenberg block passthrough:** open code view (`</>`), paste an unsupported block's markup (e.g. a Core Accordion block's rendered HTML — `div.wp-block-accordion` with nested items/panels), exit code view → an "Accordion" card appears instead of flattened/merged text. Make an unrelated edit elsewhere in the post, save, re-enter code view → the accordion's original markup (including any nested `data-wp-*` attributes) is still present, byte-for-byte.
- [ ] **Figure-rooted blocks (Audio / Video / Pullquote / Playlist):** in WordPress, add an Audio block, a Video block, a Pullquote block, and (on WP 7.1+) a Playlist block to a test post. Open that post in Quill → each appears as a non-editable card, not as flattened text, an empty paragraph, or a plain quote. Make an unrelated edit elsewhere in the post, save, re-fetch the raw content via the REST API (`?context=edit`) → each block's original markup, `<!-- wp:… -->` comments and `<figcaption>` are unchanged. Confirm the blocks are still in their original positions relative to the surrounding paragraphs and images.
- [ ] Save that same post a second and third time without touching the passthrough cards → the raw content does not grow and no block comments are duplicated.
- [ ] **Block delimiters.** Save a post containing a paragraph, headings, lists, a quote, a code block and a separator → fetch the raw content. Every block is wrapped in its own `<!-- wp:name -->` pair, blocks are separated by one blank line, and an `<h2>` writes no `level` attribute (core's default) while an `<h3>` writes `{"level":3}`.
- [ ] Open the same post in Gutenberg → no block shows "This block contains unexpected or invalid content".
- [ ] **Inline formats Quill has no button for.** In Gutenberg, write a paragraph using subscript, superscript, keyboard input, highlight and an abbreviation. Open it in Quill, type one character elsewhere, save → all five survive.
- [ ] **Deliberate `&nbsp;` indentation** at the start of a paragraph survives an edit and a save.
- [ ] **An empty paragraph the author wrote at the end of a post** is still there after an edit and a save. (Quill keeps its own empty paragraph after a table or image so the caret has somewhere to land; that one is chrome and should not be saved.)
- [ ] Confirm the four blocks Quill *does* model still behave normally in the same post: an image is still selectable/resizable, a gallery still shows its thumbnail grid, an embed still renders, and a table is still editable.

### 7.4 Editor — images

- [ ] Click the insert image button in the toolbar → select an image from the picker → it appears at the cursor position in the editor.
- [ ] In the image picker grid, click a specific thumbnail → it selects that exact image (not an adjacent one).
- [ ] Drag an image file from Finder onto the editor → a progress pill reading "Uploading image…" appears at the bottom **before** the upload finishes, then the image inserts and a success toast replaces it.
- [ ] Drag a non-image file (e.g. a `.txt` or `.pdf`) onto the editor → nothing happens (file is ignored).
- [ ] Drag multiple image files onto the editor at once → all upload and insert; the pill counts up ("Uploading image 2 of 3…") and the drop ends in **one** summary toast ("3 images inserted"), not one toast per file.
- [ ] Drop a `.heic` alongside two ordinary images → the batch still ends in a single "3 images inserted" toast (the "Converted to JPEG" note only appears on a single-file drop).
- [ ] Disconnect the network and drop one image → the toast reads "Upload failed: …" with the underlying error. Reconnect, then drop three images with one deliberately unusable → the toast summarizes as "1 of 3 images failed to upload".
- [ ] Drop a batch of images, and while the pill is still counting, drop a second batch → the two batches run one after the other: the pill never disappears early, and a toast and the pill are never visible on top of each other in the bottom slot.
- [ ] After any image insert (toolbar button, media picker, or Finder drop), start typing immediately → the text goes into a new paragraph **below** the image, not into the caption. Click the caption area under the image → the caret moves there and a caption can be typed.
- [ ] Insert two images back to back → only one empty paragraph sits between/after them (blank paragraphs don't stack).
- [ ] Save a post with an inserted image and check code view → an empty `<p></p>` follows the `<!-- /wp:image -->` block. This is expected, not a bug.
- [ ] Insert an image with the cursor inside a list item, a blockquote, and a table cell → in each case the image and its new paragraph stay inside that container.
- [ ] Disconnect from the network, then try to insert or drag an image → an error message appears; the editor content is not corrupted.
- [ ] Drag a large file (10+ MB) onto the editor → the UI stays responsive during upload (no freeze). Same check using the Media tab upload button.
- [ ] Click an image in the editor → resize handles appear on the corners and edges. Drag a handle → the image resizes while maintaining its aspect ratio.
- [ ] Add a caption to an image, then click the image → resize handles should align to the image edges, not extend down to the bottom of the caption.
- [ ] Click inside an image caption and press Enter → a new paragraph is created below the image; the cursor moves to it. The image and caption remain intact.
- [ ] Click an image that was inserted from the media library → the image toolbar shows size buttons (Thumbnail, Medium, Large, Full). Click each → the image swaps to that size.
- [ ] Click Reset on an image with sizes loaded → the image returns to its original full-size dimensions. On an image without media sizes, Reset removes custom width/height constraints.
- [ ] Click a classic-editor image (no explicit width/height attributes) → the image toolbar shows the image's natural dimensions (not blank fields).
- [ ] Set image alignment to left, center, and right → text wraps correctly for each. Save and fetch the raw HTML → the figure has `wp-block-image alignleft/aligncenter/alignright`.
- [ ] With an image selected, scroll the editor → the image toolbar moves with the image. Click elsewhere to deselect → the toolbar disappears.
- [ ] Click inside the alt text or caption field in the image toolbar → the toolbar stays open (doesn't close when you click its own controls).
- [ ] Insert images of different formats (`.jpg`, `.png`, `.gif`, `.webp`, `.heic`, `.tiff`) → each uploads successfully.
- [ ] **HEIC conversion:** drag an iPhone `.heic` photo (try one named `IMG_1234.HEIC`, uppercase) onto the editor → it uploads and inserts, and the toast reads "Converted to JPEG · Image inserted". Check the WordPress media library → the attachment is a `.jpg` with real dimensions and the usual generated sub-sizes (thumbnail/medium/large), not a size-less HEIC.
- [ ] Upload the same `.heic` from the Media tab's upload button and from the media picker inside `GallerySheet` → both also land as JPEGs with sub-sizes. (Only the drag-and-drop path mentions the conversion in its toast; the other two do not.)
- [ ] Confirm the converted photo is right-side up and at full resolution (EXIF orientation and pixel dimensions are preserved), and that the original `.heic` file on disk is untouched.
- [ ] Drag a large HEIC photo (10+ MB) onto the editor → the editor stays responsive while it converts and uploads (no beachball).
- [ ] Upload a `.jpg`, `.png` and `.pdf` → each uploads unchanged, with no conversion toast and no extension change.
- [ ] **Decorative images:** in WordPress, mark an image as decorative (the image block's "Mark as decorative" toggle, WP 7.1+). Open that post in Quill, make an unrelated edit, save → re-fetch the raw content and confirm the `<img>` still carries `role="none"`. Do the same for a decorative image that also links to its full size → the `role` stays on the `<img>`, not on the `<a>`.
- [ ] Insert a fresh image in Quill and save → its `<img>` has no `role` attribute at all (Quill never invents one).
- [ ] Open the insert image picker from the editor toolbar → the file dialog only shows image files; PDFs and movies are not selectable.
- [ ] Open the upload dialog from the Media tab → the file dialog accepts images, PDFs, and movies.
- [ ] In the media picker sheet, the Cancel button is visible and dismisses the sheet.
- [ ] If the media library has more than 50 images, scroll the picker grid to the bottom → a spinner appears and the next page appends, with no button to click. Keep scrolling → it pages again. Confirm no image appears twice (a duplicated row means the `hasMore`/`isLoadingMore` guards inside `loadMoreMedia` were lost). Do the same in `GallerySheet`.
- [ ] Click the Gallery toolbar button → the `GallerySheet` opens with a media grid; tapping images toggles a checkmark and adds them to the "Selected" list; "Insert Gallery" is disabled until at least one image is selected.
- [ ] With 2+ images selected, set columns, toggle crop, set "Link to" (None / Full Image), set Size (Thumbnail / Medium / Large / Full Size), click Insert Gallery → a read-only thumbnail-grid card appears in the editor. Toggle code view (`</>`) and confirm `<!-- wp:gallery -->`/`<!-- wp:image -->` block comments with the chosen settings, including `"sizeSlug"` matching the selected size.
- [ ] In `GallerySheet`, click Upload → pick a new image from disk → it uploads, appears in the media grid, and is automatically added to the Selected list.
- [ ] In `GallerySheet`, click the chevron on a selected image → an Alt text and a Caption field expand inline beneath it. Click the chevron again → the row collapses; the values typed are retained.
- [ ] Select an image that already has alt text and/or a caption in the media library → expand its row → both fields are prefilled with the library values (plain text, no HTML tags or `&amp;`-style entities).
- [ ] Type into the expanded Alt text and Caption fields → each keystroke lands in the field, the caret stays put, and the row does not collapse or start dragging. (Regression: a `List` row's drag gesture otherwise steals mouse-down from the `TextField`.)
- [ ] With a row expanded, try to drag it by its grip → it does **not** reorder (expanded rows are `moveDisabled`). Hover the grip → the row collapses, and dragging then works normally.
- [ ] Expand a row, then deselect that image in the media grid, then re-select it → its row comes back **collapsed** and draggable, not still expanded (regression: expanded state leaking after deselect).
- [ ] Set alt text and captions on 2+ images, reorder them, click Insert Gallery → check code view: each `alt=""` and `<figcaption class="wp-element-caption">` is attached to the correct image, in the displayed order.
- [ ] Enter alt text and a caption containing `&`, `<b>bold</b>` and a double quote → insert → code view shows them escaped as text, not as live markup, and the gallery card renders normally.
- [ ] Leave alt text and caption blank on an image → insert → that image's markup has `alt=""` and no `<figcaption>` at all.
- [ ] After editing alt text/caption in the sheet, check the image in the WordPress media library (or the Media tab) → its library alt text and caption are **unchanged** (sheet edits are insert-time only).
- [ ] Insert a captioned gallery, make an unrelated visual edit elsewhere in the post, save, re-fetch the raw content → all captions and alts are still present and not duplicated.
- [ ] Save a post containing a sheet-inserted gallery, then make an unrelated visual edit elsewhere in the post and save again → re-fetch the raw content and confirm the gallery block comments are still present (this is the fix for the previous `_rawHTML`-only silent-drop behavior).
- [ ] Open a post containing a gallery authored outside Quill (e.g. in the WordPress block editor) → it loads as a read-only thumbnail-grid card, not exploded into individual resizable images. Clicking it does not open `GallerySheet` (insert-only for v1).
- [ ] Open a post containing a gallery with an image caption (authored outside Quill) → make an unrelated visual edit elsewhere and save → re-fetch the raw content and confirm the caption is still present (verifies the `sourceHTML` verbatim round-trip, not just the structured reconstruction path).
- [ ] Insert a gallery (or embed) at the very end of a post, then click just after it → the caret shows as a thin blue vertical bar (not a black horizontal bar). Type → a new paragraph is created at that position and text is entered normally.
- [ ] Click a single (non-gallery) image → in the image toolbar, toggle "Link to Full Image" on → save and check code view/raw HTML: the `<img>` is wrapped in `<a href>` pointing at the media's full-resolution URL. Toggle it back off → save again → the `<a>` wrapper is removed. Open a post with a pre-existing linked image (authored outside Quill) → the toggle shows as already on.
- [ ] Drag an image from Finder onto the editor (or paste one) so it has no `mediaId` → select it → confirm the "Link to Full Image" button is visible and toggling it on wraps the image's current `src` in `<a href>` on save.

### 7.5 Editor — links

- [ ] Select text, click the link button → a link popover appears anchored near the selected text. With no selection, the popover anchors to the toolbar button instead.
- [ ] Type a search query in the link popover → results from posts, pages, categories, tags, and media appear.
- [ ] As search results appear, the popover grows taller to fit them (results are not clipped or hidden).
- [ ] Select a search result → a link is inserted on the selected text. Manually typing a URL also works.
- [ ] Search for something with no matches → an empty state is shown; no crash.
- [ ] Search while offline → the popover handles the error gracefully (no crash or hang).
- [ ] Insert links with `http://` and `https://` URLs → Cmd+clicking them in the editor opens the system browser. Hold Cmd → links show an underline and pointer cursor. Release Cmd → cursor returns to normal. Insert a `mailto:` link → Cmd+clicking it opens Mail. Insert a `file:///` or `javascript:alert(1)` link via code view → Cmd+clicking it does nothing (blocked for security).
- [ ] Clicking a link without holding Cmd places the cursor inside the link text (for editing) — it does not open the link.
- [ ] **The editor never navigates away.** Cmd+click an external link → it opens in the browser and the editor still shows the post (toolbar present, content intact, not a blank or remote page). Paste a `<meta http-equiv="refresh">` via code view → the editor stays put. This is the `decidePolicyFor` guard in `EditorCoordinator`; it is only wired up while that method matches `WKNavigationDelegate` exactly, so a "nearly matches" build warning means this test will fail.

### 7.6 Editor — code view

**Entering and exiting**
- [ ] The `</>` button appears in the toolbar's utility group, alongside the spell-check and image-align controls.
- [ ] Click `</>` → the visual editor switches to a code textarea; all other toolbar buttons become disabled; the `</>` button shows an active/highlighted state.
- [ ] The code textarea shows nicely formatted HTML: block elements on their own lines, inline elements (`<strong>`, `<a>`, etc.) stay on the same line as their parent, list items are indented inside their list, table cells are nested under rows, and `<pre>` content is left exactly as-is. Top-level blocks are separated by blank lines.
- [ ] Click `</>` again → the editor switches back to visual mode; toolbar buttons re-enable; any HTML changes made in the textarea are reflected in the visual editor.

**Editing and saving**
- [ ] Make a change in the code textarea, exit code view → the visual editor shows the change.
- [ ] Enter code view without changing anything, exit → the visual editor content is completely unchanged.
- [ ] Enter and exit code view repeatedly without editing → the HTML formatting does not accumulate extra blank lines or whitespace with each cycle.
- [ ] With code view active, press ⌘S → the content from the textarea is saved to WordPress (not stale content from before entering code view).
- [ ] Make a change in the code textarea, press ⌘S without exiting code view first → the change is saved to WordPress.
- [ ] While in code view, click a different post in the sidebar → code view exits automatically and the new post loads in visual mode.
- [ ] In dark mode, the code textarea background and text colors match the rest of the editor (no bright white flash).
- [ ] With the image toolbar or embed menu open, enter code view → both dismiss automatically (no stale floating panels remain).

**Special characters**
- [ ] Write a paragraph containing `5 < 10`, `a & b`, and a `"quoted"` word. Enter code view → the HTML shows `&lt;`, `&amp;`, `&quot;` correctly. Switch back to visual → original text is intact. Save and reload → still intact.

**Block posts/pages** (posts created in the WordPress block editor)
- [ ] Open a block-based post that uses Gallery or Columns blocks. Enter code view without making any visual edits first → WordPress block comments (`<!-- wp:gallery -->`, etc.) are visible in the textarea.
- [ ] Open the same post, make a visual edit (e.g. fix a typo), then enter code view → block comments are gone. This is expected: once you edit visually, Quill's editor becomes the source of truth.

**Non-block pages** (pages with plain HTML, no Gutenberg blocks)
- [ ] Open a page with no block comments (e.g. a simple About page). Enter code view → the HTML is indented and readable, not compressed onto a single line.

**Round-trips**
- [ ] Make a visual edit, then open code view → the edit is visible in the HTML.
- [ ] Make a visual edit → save → close the post → reopen → content is intact.
- [ ] Make only visual edits, never open code view → save → content saves correctly.
- [ ] Edit in code view → exit → save → close the post → reopen → enter code view → the edit is present and the HTML is still formatted (not compressed).

### 7.7 Save / publish / draft / schedule

- [ ] Save a local draft → it persists locally only (no network call); toast shows "Saved locally".
- [ ] If the local draft save fails (e.g. disk full) → a red error toast appears with the failure reason.
- [ ] Publish a local draft → a remote post is created on WordPress; the local copy disappears from the Drafts list; the sidebar selection moves to the new remote item in the Posts or Pages section.
- [ ] A page draft publishes to the pages endpoint; a post draft publishes to the posts endpoint.
- [ ] Press ⌘S on a remote draft → it updates on WordPress while keeping its "draft" status.
- [ ] Press ⌘⇧P or click Publish on a remote post → the post publishes. The button label matches the action: "Publish" for drafts, "Update" for published posts, "Schedule" for future-dated posts, "Submit for Review" for pending posts, "Publish Privately" for private posts.
- [ ] Set a future date on a post → status changes to "future" and the post is scheduled. Check on the WordPress server that the scheduled time matches (particularly important for sites in non-UTC timezones).
- [ ] Close and reopen a scheduled post → the correct future date appears in the settings panel.
- [ ] Type a new category or tag name in the settings panel, then save → the category/tag is created on WordPress, its ID is attached to the post, and it appears in the category/tag list.
- [ ] If creating a new category or tag fails (e.g. no permission) → the save stops with an error; post content is not lost. Retry the save → any names that already succeeded before the failure are not resubmitted (no "term_exists" error re-blocking the save).
- [ ] Open a post while offline (or force the full-post fetch to fail) → an error toast explains the post may be missing content; attempting to save shows "Can't save — this post never finished loading" instead of silently publishing empty content over the real post.
- [ ] On a new post, leave the slug blank → it stays blank (doesn't inherit another post's slug). Edit the slug and save → the slug is sent. On an existing post, leave the slug blank → the server's current slug is preserved (not overwritten with empty).
- [ ] Set a featured image → it appears on the post. Clear the featured image → it is removed on the server.
- [ ] Toggle comment status between open and closed → the setting round-trips correctly on save.
- [ ] In the page parent picker, the current page does not appear in the list. Save with a parent selected → the parent is set on the server.
- [ ] The Publish button shows an outline paper plane on a draft (and for other status changes) and an outline up-arrow circle on a published post. Publish a remote draft → the button switches to Update, with the up-arrow icon, straight away, without reselecting the post.

### 7.8 Conflict detection

- [ ] Open a remote post in Quill. Edit the same post from another client (or directly on the server) so its `modified` date changes. Save in Quill → a "Conflict Detected" dialog appears.
  - [ ] Click "Keep Local" (⌘↩) → Quill saves its version, overwriting the server.
  - [ ] Click "Use Server" → Quill reloads the server's content, discarding local edits.
  - [ ] Click "Cancel" → the dialog closes and editing continues; no data is lost.
- [ ] Open a post, immediately save without anyone else changing it → no conflict alert appears.
- [ ] Preview a draft post, then save → no spurious conflict alert appears.
- [ ] On a site using plain permalinks (`?p=123` URLs), click Preview → the browser opens the correct URL with `&preview=true` appended (not a malformed double `?`).
- [ ] On a site using pretty permalinks (`/my-post/` URLs), click Preview → the browser opens `…/?preview=true`.

### 7.9 Autosave / unsaved changes / navigation

- [ ] Edit a remote post, wait 30 seconds → an autosave is created. Navigate away and back → a "Unsaved changes restored" toast appears and the stashed edits are shown.
- [ ] Open a remote post that has no local changes → no "Unsaved changes restored" toast appears.
- [ ] Edit a local draft, navigate away without saving → switch back and reopen it → the edits are preserved.
- [ ] Edit a local draft, immediately click the Media section (before the 30-second autosave timer fires) → switch back to Drafts and reopen the draft → the edits are present.
- [ ] Edit a remote post, immediately click the Media section → reopen the post → "Unsaved changes restored" toast appears and the edits are shown.
- [ ] Switch directly between two posts (without going through Media) → edits from the first post don't leak into the second; no duplicate autosaves.
- [ ] Edit a remote post and navigate away → the edits are stashed locally but not pushed to WordPress.
- [ ] Successfully publish or update a post → reopen it → no "Unsaved changes restored" toast (the stash was cleared on save).
- [ ] Edit a local draft → the window's close button shows the standard unsaved-changes dot. Save it (⌘S) → the dot clears.
- [ ] Edit a remote post → the same dot appears, and clears on Update.
- [ ] Switch from a dirty post to a clean one → the dot clears rather than sticking to the window.
- [ ] Edit a post, then click the Media section without saving → the dot clears as the editor closes. SwiftUI can detach the marker view before it is dismantled, so a teardown that reads `nsView.window` finds nothing and leaves the dot lit with no editor open.
- [ ] Rapidly switch between several posts → no autosave data from one post appears in another; no crashes.
- [ ] Quit the app with unsaved local-draft edits → relaunch → the edits are recovered.
- [ ] Open a remote post, make edits → a "Revert" button appears in the editor header. Click it → a "Revert to Server Version?" dialog appears.
  - [ ] Click "Revert" (⌘↩) → local edits are discarded and the server content reloads.
  - [ ] Click "Cancel" → editing continues; no data is lost.
- [ ] The Revert button does not appear for local drafts.
- [ ] The Revert button does not appear for a remote post that has not been edited.
- [ ] Trigger two toasts in quick succession (e.g. two rapid saves) → the second toast's 2-second dismiss timer is not cut short by the first toast's timer; it stays visible for its own full duration.

### 7.10 Delete / trash

- [ ] Right-click a remote post and choose Delete → a confirmation dialog appears. Confirm → the post moves to WordPress Trash (recoverable, not permanently deleted).
- [ ] Same test with a page → the page moves to Trash.
- [ ] Delete a local draft → it disappears from the sidebar and is removed from local storage.
- [ ] Delete a media item → a confirmation dialog warns that deletion is permanent. Confirm → the item is gone from both the grid and the WordPress server.
- [ ] If deletion fails (e.g. no permission, or offline) → an error alert appears; the item remains in the list.
- [ ] Click Cancel on any delete confirmation → nothing happens.

### 7.11 AI features (requires an Anthropic API key)

**Setup**
- [ ] With no API key configured: the pencil (✦) and checkmark buttons in the editor toolbar are hidden, and AI items are absent from the right-click context menu.
- [ ] Add an API key in Settings → both toolbar buttons appear and AI context menu items appear, without relaunching the app.

**Generate content**
- [ ] Click the pencil button on an empty editor → the generate dialog opens directly. On a non-empty editor → a "Replace Content?" confirmation appears first.
  - [ ] ⌘↩ confirms from the keyboard; Escape or Cancel dismisses without generating.
- [ ] Generate a post → the result includes a title and structured HTML with headings (not just plain paragraphs).
- [ ] If Claude's response is cut off by the token limit → a "Post may be cut off" dialog appears. "Get Full Version" (⌘↩) retries for a complete result; "Use What I Have" accepts the truncated version.
- [ ] Generate with web search enabled → the result is coherent and complete (not fragmented); citations don't break the output.

**Selection operations (right-click menu)**
- [ ] Select some text, right-click → Make Longer, Make Shorter, To Table, and To List appear in the context menu. Each produces a correct result when clicked.
- [ ] Deselect all text, right-click → the AI items are absent.
- [ ] The AI menu items are not hidden by macOS AutoFill or Services items that may be injected into the menu.
- [ ] Select text inside a bullet list, right-click → Make Longer/Shorter appear. The result preserves the list format.
- [ ] Click inside a table, select some cells, right-click → Make Longer/Shorter appear. The result preserves the table structure.
- [ ] Drag-select in reverse (from bottom to top) → AI menu items still appear for selections ≥ 10 characters.
- [ ] Make Shorter on one sentence in the middle of a paragraph → only that sentence changes; the sentences before and after it stay, and the paragraph is not split.
- [ ] Make Longer on one sentence → the result is a few sentences in the same paragraph, not several new paragraphs. Make Shorter on a long paragraph → it stays one paragraph.

**Result handling**
- [ ] AI-generated content replaces the selected text cleanly — no empty paragraphs appear before or after the inserted content. Save and check the raw HTML for stray `<p></p>` tags.
- [ ] Click Accept → the AI content is kept; click Discard → the original content is restored.
- [ ] If the AI returns tables, lists, or headings, save and fetch the raw HTML → it has proper WordPress classes (`wp-block-table`, `wp-block-list`, `wp-block-heading`, etc.).
- [ ] If Claude errors or times out → the original text is restored, an error toast appears, and the editor is not corrupted.
- [ ] Disconnect from the internet and trigger an AI operation → the error message reads as a clear "couldn't reach the Anthropic API" message, not a raw NSURLError string.
- [ ] Trigger an AI operation via the right-click menu on one selection, then — while the result bar is still showing — right-click a different selection and trigger another AI operation. Only one Accept/Discard bar should be interactive; pressing Return or Escape does not double-fire.
- [ ] Select a sentence and ask for a rewrite that will contain `&` (e.g. select "Research and development costs are high." and Make Shorter, which usually returns "R&D") → the editor shows `R&D`, not `R&amp;D`. Save and check the raw HTML → `R&amp;D`, never `R&amp;amp;D`.
- [ ] Select a sentence together with the space after it (drag one character past the full stop) and Make Shorter → the result keeps one space before the next sentence. Repeat with the space before the sentence.
- [ ] Start an AI operation, and while "✶ Rewriting…" is showing, click a different post → the new post opens unchanged, no Accept/Discard bar appears, and the reply never lands in it. Go back to the first post and check its content (known gap: the placeholder can be saved there; see `Views/Editor/CLAUDE.md`).
- [ ] If Claude's reply is empty after cleanup (for example only whitespace or an empty code fence) → the original text is restored and an error toast appears; no Accept/Discard bar is shown over the placeholder.

**AI result bar**
- [ ] The Accept/Discard bar floats above the Quill window but does not float above other apps when you switch away from Quill.
- [ ] The bar has no rectangular shadow artifact around it.
- [ ] Both buttons are clearly visible in light mode and dark mode.
- [ ] The bar sits centred at the bottom of the editor, not beside the result, so it never covers the rewritten text or the text around it. Resize the window while it shows → it stays centred at the bottom.
- [ ] Trigger the AI result bar, then type in the sidebar search field → the bar stays visible and correctly positioned (doesn't disappear or duplicate).

**Style guide**
- [ ] In Settings, select sample posts → a style guide is generated. Re-save with the same sample posts → no new Claude call is made. Change the site URL → sample posts and style guide are cleared.

**Post evaluation**
- [ ] Click the checkmark button in the editor toolbar → a panel appears with a summary and a list of findings.
- [ ] Click a finding card → the corresponding sentence in the editor is selected and scrolled into view (the full sentence, not just a few words).
- [ ] If a style guide is saved, evaluation findings that match the author's established voice should not appear (e.g. intentionally conversational tone not flagged).
- [ ] The number of findings is reasonable (5–12 for a typical post); clicking every finding navigates to the correct sentence.
- [ ] The checkmark button shows an active/highlighted state while the evaluation panel is open.
- [ ] The checkmark button is disabled (non-clickable) while the evaluation is running.
- [ ] Click evaluate, then immediately switch to another post → the old evaluation result does not appear for the new post.

### 7.12 Settings panel & preferences

- [ ] Open the settings panel for a **post** → it shows categories, tags, slug, excerpt, and discussion. For a **page** → it shows parent page, slug, and discussion only (no categories, tags, or excerpt).
- [ ] In the category list, checked categories appear first (alphabetical), then unchecked (alphabetical). This ordering holds when filtering by search and after toggling a category on/off.
- [ ] Selected tag chips above the search box are in alphabetical order; unselected tags in the dropdown are also alphabetical.
- [ ] The amber accent color is used throughout the settings panel.
- [ ] Preferences opens from both the app menu (⌘,) and any in-app settings button. The sample post picker is populated (not empty).
- [ ] The post settings, media and writing-check inspectors use Finder-style section headings (small, semibold, secondary, normal case, not uppercase), system rounded-border fields (the excerpt included), and the same 16pt margins. Compare against the sidebar in light and dark.
- [ ] In Preferences, the Save button sits on the window background below the form, with no grey section box behind it.

### 7.13 Window / appearance

The hand-painted title bar is gone (native-ui, 2026-09-18). The window toolbar is
now the system toolbar drawing its own Liquid Glass, so the old title-bar colour
matching and its four-way launch-appearance grid no longer apply. What replaced
them is the toolbar-fade guard: see the toolbar-fade gotcha in `docs/gotchas.md`
and the `.toolbarBackgroundVisibility` entry in `Sources/QuillKit/Views/CLAUDE.md`.

- [ ] With the app open, toggle dark mode in System Settings → the editor, toolbar, and sidebar all switch immediately without relaunching.
- [ ] Enter and exit full screen → the window chrome stays stable.
- [ ] Open a post, then toggle the inspector open and closed → the toolbar does not dim or fade. This is what `InspectorTitlebarFix` suppresses; watch the toolbar, do not glance away.
- [ ] Re-expand the inspector after collapsing it → the content pane's titlebar background does not paint over the inspector's first 52pt.
- [ ] Launch the app and watch through the post list arriving → no flash in the toolbar at any point, including the first second.
- [ ] Select a post, edit it, and save/publish to WordPress → no flash when the request completes.
- [ ] Switch sections (Posts → Pages → Drafts → Media) → no flash.
- [ ] Narrow the window until the editor toolbar runs out of room → buttons collapse into the overflow menu rather than crushing together or clipping their labels. Widen it again → they come back in the same order.
- [ ] The editor action buttons read as one icon capsule, and the Publish/Update button keeps its colour rather than washing out when the window loses focus.

**Pickers across an appearance switch** — through macOS 26, SwiftUI stamped a fixed `NSAppearance` on the AppKit popup button behind every `Picker` and never refreshed it, so a picker kept drawing its old bezel and label color after a switch (light pill with dark text in a dark panel; pale, near-invisible text in a light one). Quill carried a `.rebuildsOnAppearanceChange()` modifier for this. macOS 27 fixes it: retested 2026-09-18 with the modifier reduced to a true no-op that never reads `colorScheme`, and the sidebar section picker and the inspector's Status picker both repainted correctly in both directions without a relaunch. The modifier is deleted. Keep checking both directions as a regression guard, since each leaves a picker wrong in a different way.

- [ ] Open a post's settings panel in **light**, switch the system to **dark** → the Status picker (and Parent Page picker on a page) turns dark with light text, matching the panel.
- [ ] Open the panel in **dark**, switch the system to **light** → the pickers turn light with dark, readable text.
- [ ] After either switch, click the Status picker → the menu opens and changing the selection still works.
- [ ] Open the gallery sheet, switch appearance while it's open → its Link To and Size pickers follow.
- [ ] The title field and top border spacing look correct (no extra gaps or overlap).
- [ ] The app icon appears in the Dock and in the About window.
- [ ] On launch, a "Loading editor…" overlay appears briefly and fades out once the editor is ready. It should never stay visible permanently.
- [ ] In dark mode, links in the editor are visible (light blue on dark background), not unreadable dark blue.
- [ ] Switch to dark mode while the app is running → open a post → editor, toolbar, and editor-wrap all start in dark colors immediately (no white flash).

### 7.14 Context menus

- [ ] Right-click in the editor → the menu shows Cut, Copy, and Paste with correct enabled/disabled states. No macOS AutoFill, Services, or other system-injected items appear.
- [ ] Right-click in the title field → only Cut, Copy, and Paste appear. No AutoFill or Services items.
- [ ] Right-click on a misspelled word in the editor → up to 8 spelling suggestions appear above Cut/Copy/Paste with a separator. Click a suggestion → it correctly replaces the misspelled word.
- [ ] Right-click a misspelled word next to an emoji (e.g. `speling 🎉`) → the suggestion replaces only the word without corrupting the emoji or surrounding text.

### 7.15 Spell check

- [ ] Click the "ABC" toolbar button → misspelled words are highlighted. The highlights clear when you start editing.
- [ ] Spell check runs without crashing on the current macOS version.

### 7.16 Stats panel

- [ ] The stats area shows word count, character count, and reading time.
- [ ] Counts update as you type.
- [ ] In code view, the counts freeze. Switch back to visual mode → they refresh.
- [ ] A short post shows "1 min" reading time; longer posts round up (e.g. 400 words → 2 min).

### 7.17 Publish status helpers

- [ ] The publish button label matches the post status: draft → "Publish", published → "Update", future → "Schedule", pending → "Submit for Review", private → "Publish Privately".
- [ ] The toast message after saving reflects what happened (e.g. "Published" vs "Updated" vs "Scheduled").
- [ ] Set a future date → the status changes to "future" and the button changes to "Schedule".
- [ ] Set visibility to Private → the status changes to "private" and the button changes to "Publish Privately".

### 7.18 Find & replace

- [ ] Press ⌘F (or click the toolbar button) → the find & replace bar appears. Press Escape or the close button → it closes.
- [ ] Type in the Find field → all matches in the editor are highlighted in yellow.
- [ ] The match counter shows "1 of N" and updates as you change the query.
- [ ] Click Next/Previous → the highlight moves between matches and wraps around at the beginning/end.
- [ ] Type a replacement, click Replace → the current match is replaced and the highlight advances to the next match.
- [ ] Click Replace All → every match is replaced in one operation.
- [ ] Toggle case-sensitive mode on → a lowercase query no longer matches uppercase text.
- [ ] In code view, the find bar is hidden and no highlights appear in the textarea.

### 7.19 Embeds

- [ ] Paste a YouTube, Vimeo, or Twitter/X URL into the editor → it displays as an embed card showing the provider name and URL.
- [ ] Save and fetch the raw HTML → the embed is a valid Gutenberg `wp-block-embed` block with correct provider classes (e.g. `is-type-video is-provider-youtube wp-block-embed-youtube`).
- [ ] Close and reopen the post → the embed card still renders correctly.
- [ ] View the post on the live WordPress site → the embed renders as the expected player/widget.
- [ ] Paste an unrecognized URL → it saves as a generic embed block without provider-specific classes.
- [ ] An embed card does not show resize handles or get treated as an image.

### 7.20 Footnotes

- [ ] Right-click and choose Insert Footnote → a superscript `[1]` appears at the cursor and a matching entry appears in the footnotes list at the bottom of the document.
- [ ] Insert a second footnote → it is numbered `[2]`. The numbers follow document order.
- [ ] Delete a footnote marker from the text → its entry is automatically removed from the footnotes list.
- [ ] Press Enter inside a footnote entry → a line break (soft break) is inserted within the entry; the text is not lost or swallowed.
- [ ] Type text in a footnote list entry → the text is preserved on save.
- [ ] Click a footnote number in the list → the cursor jumps to the corresponding marker in the text.
- [ ] Click the ↩ button at the end of a footnote entry → the cursor jumps to the corresponding marker in the text.
- [ ] Save the post → fetch the raw HTML (`?context=edit`). The content ends with `<!-- wp:footnotes /-->` and **no** list; the bodies are in `meta.footnotes`. Markers are `<sup>` elements carrying core's `<fnId>-link` id, and there is no `↩` back-link anywhere in the content — WordPress renders that itself.
- [ ] Close and reopen the post → footnotes render correctly and are editable; the ↩ button is present in each entry in the editor.
- [ ] View the post on the live WordPress site → footnote numbers are clickable links to the footnote list, exactly one back-arrow per note, and it jumps back to the inline marker.
- [ ] **Edit only a footnote body** — change nothing else in the post. The window's unsaved-changes dot appears, the autosave fires, and switching to another post and back keeps the edit. (Before this was fixed the post never read dirty and the edit was lost.)
- [ ] **A post that has a footnotes delimiter but no meta behind it** shows a non-editable card rather than an empty list, and saving without touching it leaves it alone.
- [ ] **Legacy migration:** open a post whose footnotes were written as an inline list by an older build. Save it without editing → unchanged. Now type one character and save → the bodies move into `meta.footnotes`, the list leaves the content, and no stray backref is stored.
- [ ] Open a post with footnotes in code view → the source shows the delimiter, not the list. Leave code view without editing → the notes are still there.
- [ ] With the cursor inside a footnote entry, toolbar buttons for block operations (headings, blockquote, code block, lists, table, image, embed) are disabled.
- [ ] With the cursor inside a footnote, pressing keyboard shortcuts for block operations (e.g. ⌘⇧7 for ordered list, ⌘⇧8 for bullet list) does nothing.
- [ ] With the cursor inside a footnote entry, Backspace and Delete keys work normally (can delete characters and merge text).
- [ ] Drag an image from Finder onto a footnote entry → an error toast appears ("Images can't be inserted in footnotes") and the image is not inserted.
- [ ] Paste rich content (containing headings, lists, or images) into a footnote → block elements are stripped; only inline text and formatting survive.

### 7.21 Update checker

- [ ] Launch the app → if the latest release at `api.github.com/repos/cpoteet/Quill/releases/latest` has a higher version than the running build, a banner appears in the sidebar with the new version number.
- [ ] Click "View Release" → opens that release's GitHub page in the default browser.
- [ ] The page "View Release" opens is an `https://github.com/…` URL. The checker ignores a release whose `html_url` is anything else, so no banner appears for it.
- [ ] The banner version number has no leading `v`, even though the Git tag does.
- [ ] The banner is the first row in the sidebar list, above the posts — not below them. Check with a site that has enough posts to fill the list.
- [ ] Click the dismiss (×) button → the banner disappears and does not reappear for the same version on subsequent launches.
- [ ] If the remote version equals or is older than the current version, no banner appears.
- [ ] With no internet connection at launch, toggle the sidebar hidden and visible again (or otherwise trigger a remount) once connectivity returns → the update check runs again and a banner appears if applicable (a failed first check should not permanently skip checking for the rest of the session).

### 7.22 Block-risk banner

Run this on a **new local draft**, never a published post.

- [ ] Open a post containing a block Quill cannot model and does not preserve → no banner. Preservation is the normal case; the banner means content actually went missing.
- [ ] Force the failure case: in code view, paste a block, leave code view, and delete the card it became. A banner appears naming the block, in the singular if it is one block and the plural if it is more, and it says this is Quill's limitation rather than something you did.
- [ ] **While the banner is unacknowledged, saving is refused** — ⌘S, Publish/Update, and Save Draft all show the "Can't save yet" message.
- [ ] Switching to another post while the banner is up does **not** write the squashed content (check the draft in SQLite, not through the UI — see the root `CLAUDE.md`).
- [ ] Closing the editor while the banner is up does not write it either.
- [ ] Autosave is suspended while the banner is up — no new row appears in the `autosaves` table.
- [ ] Acknowledge the banner → the wording changes, saving is allowed, and the banner stays on screen.
- [ ] Save → the banner moves to its past-tense stage and points at WordPress revisions as the way back.
- [ ] **Repair the post in code view** (paste the missing block back) and leave code view → the banner clears itself and saving works again, without reopening the post.
- [ ] Reopen a post that was already saved with a block missing → **no** banner. The loss is already in the saved content, so there is nothing left to warn about.
- [ ] **A post you have not edited never raises a blocking banner.** Open a post, do not type, press ⌘S → it saves. An untouched post writes its original bytes back, so there is nothing to lose.
- [ ] Switch to another post and back → the banner state belongs to the post, not the window.
- [ ] **The banner does not crash Quill.** Open a post whose banner appears, then toggle the inspector, resize the window, and switch posts → no crash. Save Settings while that post is open → no crash. A `.fixedSize` on the banner text caused an AppKit constraint loop here.

### 7.23 Container blocks & the insert menu

- [ ] The toolbar has a labelled insert button; opening it lists every container block Quill can insert.
- [ ] Insert each of Columns, Details, Buttons, Accordion, Tabs, Pullquote, Preformatted and Separator → each appears, the caret lands somewhere sensible inside it (the first tab panel, the first column, the accordion title), and the menu closes.
- [ ] Type into each one, save, reopen → the text is there and the block still renders as a block.
- [ ] Open each in Gutenberg → no validation warning.
- [ ] **Delete gesture:** with the caret inside a container, the ✕ appears at the far right of the contextual toolbar row and names the block it would remove. Press it → the block goes, the caret lands in the block after it (or the one before, if nothing follows), and deleting the only block in the post leaves an empty paragraph to type in.
- [ ] ⌘⇧⌫ does the same thing. Neither offers itself in ordinary body text.
- [ ] Inside nested containers, the gesture removes the innermost block first.
- [ ] **Exit gesture:** Esc leaves a tab panel, a column, a table, a details body, a blockquote, a code block and a preformatted block, landing in the paragraph below — creating one if the block is last, reusing the one already there if not. Nested containers step out one level at a time.
- [ ] Esc with a menu open closes the menu instead of leaving the block.
- [ ] Enter twice does the same as Esc in a tab panel, a column, a details body, an accordion panel and a pullquote. Enter in a table cell still just adds a paragraph, and Enter mid-paragraph still splits it.
- [ ] **Empty titles:** a freshly inserted accordion or details shows a greyed hint in place of its title. Clicking the row places the caret in the title rather than collapsing the block; typing clears the hint, emptying it brings it back. The hint never appears in the saved content, and the row is no taller for having one.
- [ ] Clicking anywhere on an accordion header row or the details arrow collapses the block; clicking the title text places the caret.
- [ ] **Cite:** inside a pullquote or a blockquote, the toolbar offers a "Cite" control. Adding one puts the caret in it ready to type; Enter leaves the quote; removing it takes the citation away cleanly. It saves inside the blockquote, where core puts it.
- [ ] Collapse state, hints and selection chrome never reach the saved markup — check the raw content after collapsing things and saving.

### 7.24 Block settings & style controls

- [ ] With the caret inside a block that has settings, a second toolbar row appears naming only that block's group; it disappears when the caret leaves, and nested containers show both groups at once.
- [ ] Toggle each style control (button, quote, separator, image, table) → the style applies in the editor, survives a save and a reopen, replaces the previous style rather than stacking, and leaves classes you wrote yourself alone.
- [ ] Open each in Gutenberg → the style shows there too, and the block is valid.
- [ ] **Accordion icons:** change the icon and its position → every heading in the accordion changes with the block, one undo reverses the lot, and an item added afterwards inherits the setting.
- [ ] **Open in new tab:** on a button with a link, the control appears and writes `target`/`rel`; on a button with no link it is hidden, and it appears the moment a link is set. The same control exists for a prose link.
- [ ] **Default tab:** with two or more tabs, one is marked as the default and the mark follows the control, not the caret. With a single tab there is no mark. The mark never reaches the saved markup.
- [ ] **Settings a block has that Quill has no control for** — a column's width, a details `name`, `is-not-stacked-on-mobile` — survive an edit untouched.
- [ ] Turning a setting **off** actually removes it; it must not come back on the next load.

### 7.25 Tables

- [ ] The table toolbar button opens a size grid rather than inserting a fixed table. Hovering reports the size; clicking inserts exactly that, with a header row. Arrow keys resize and Enter inserts; Escape closes it without inserting; pressing the button again closes it. It refuses inside a footnote, and it is legible in dark mode.
- [ ] Header and footer toggles reflect the sections a loaded table has, add and remove `<thead>`/`<tfoot>` rows of the right width, never create a second header row, and never remove the last remaining row.
- [ ] The footer row is tinted and separated from the body in both light and dark mode, and that styling never reaches the saved markup.
- [ ] The stripes style toggle reflects a loaded style and writes both halves — the class and the comment attribute — when turned on, removing both when turned off.
- [ ] A table caption written in Gutenberg stays a caption in Quill rather than becoming a paragraph, and comes back inside the figure on save.
- [ ] A classic bare `<table>` saves as a `core/table` figure and opens cleanly in Gutenberg.
- [ ] **Known limit:** a table with explicit head/foot sections *and* a colspanned body cell gains a phantom empty cell in the header and footer. This is upstream of Quill's save; it is recorded, not fixed.



### 7.26 Media library (gallery, filters, inspector)

Added 2026-09-19 with the native media panel. None of this is automated — the
`NSCollectionView` bridge cannot be unit tested, and background computer-use
clicks do not reach it (see `Views/Media/CLAUDE.md`). Full-screen control or a
human is required.

- [ ] Media opens on a gallery in the content column, not a sidebar grid.
- [ ] The sidebar lists five filters: All Media, Images, Documents, Audio, Video.
- [ ] Single-clicking a thumbnail selects it and opens the inspector.
- [ ] Arrow keys move the selection left, right, up and down.
- [ ] The inspector follows the selection and shows the right filename.
- [ ] The toolbar's Media Info button is disabled when nothing is selected.
- [ ] That button closes the inspector without clearing the selection ring.
- [ ] With the inspector closed, selecting another image does NOT reopen it.
- [ ] Pressing the button again reopens it, showing the current selection.
- [ ] Right-clicking offers Show Details above the other items.
- [ ] Show Details opens the panel on the right-clicked image, with the panel closed beforehand.
- [ ] Editing alt text and clicking away saves, and shows "Saved".
- [ ] Space opens the large preview. Space closes it. Escape closes it.
- [ ] Double-clicking a thumbnail opens the large preview.
- [ ] Typing a space in the search field does NOT open the preview.
- [ ] Scrolling to the bottom loads the next page.
- [ ] **A first page that fits the window still pages.** Make the window tall enough (or wide enough) that all 30 thumbnails are visible with no scrollbar → page 2 loads anyway. Paging hangs off the last cell being displayed, not off scrolling, so an unscrollable first page must not strand the library at 30 items.
- [ ] Each filter returns the right items; Documents covers PDFs but not `.txt` — a `.txt`/`.csv`/`.vtt` file appears under All Media only (WordPress's `media_type` takes one value; see `docs/gotchas.md`).
- [ ] A filter with no results shows "No media yet"; a search with none shows "No matches found".
- [ ] The toolbar Refresh button reloads and keeps the active filter.
- [ ] Toolbar + menu → Upload Media opens the file picker and does NOT create a post.
- [ ] File → New Media (⌘⌥N) opens the same file picker.
- [ ] Right-clicking a thumbnail selects it and offers Copy URL, Open in Browser, Delete.
- [ ] Deleting removes the thumbnail and clears the selection.
- [ ] **Paging survives a local change.** Delete an item, then scroll to the bottom → the next page continues from where the grid ends, with nothing skipped. Upload an item, then scroll to the bottom → nothing appears twice. Paging sends an offset taken from the item count, so both cases self-correct; a page number would not.
- [ ] Uploading adds a thumbnail, selects it, and shows a spinner while it runs.
- [ ] Upload a file the active filter excludes (select Images, upload a PDF) → the sidebar switches to All Media and the new item is visible and selected, rather than vanishing into a view that cannot show it.
- [ ] Start a second upload before the first finishes → the spinner runs until both are done, not until the shorter one is.
- [ ] **A failed load does not loop.** Turn off Wi-Fi and open Media → one failed request (watch the network in Console or a proxy), not a stream of about 20 a second, and exactly one Media Info button in the toolbar.
- [ ] On a site with `WP_DEBUG_DISPLAY` on and a plugin that prints a PHP warning, Media still loads. If a warning still reaches the reply, the error says a plugin or theme may be adding text to it.
- [ ] No bottom button strip remains, and there is exactly one Refresh button and one + menu.
- [ ] The gallery renders correctly in light and in dark appearance. Judge colour from a native-resolution screenshot, not a downsampled one.

### 7.27 Menu bar, Help & the public site

Added 2026-09-20 with the open-source release work. The Help items and the About
window's licence link all point at `quill.siolon.com`, which is published from
`site/` by the GitHub Pages workflow — a 404 here means the deploy, not the app.

**Help menu**
- [ ] Help → **User Guide** opens `quill.siolon.com/docs.html` in the default browser, and the page loads (not a 404).
- [ ] Help → **Changelog** opens `quill.siolon.com/changelog.html`, and the newest release at the top matches the running build's version.
- [ ] The Help menu contains only those two items — no leftover "Quill Help" wording, and no macOS-injected Search field behaviour that swallows them.
- [ ] About Quill → the **End User Licensing Agreement** link opens `quill.siolon.com/license.html`. The credit links (Tiptap, ProseMirror, SQLite.swift, Vecteezy) each open their own site.
- [ ] The version shown in About matches the version the update checker compares against.

**Menu commands**
- [ ] File → New Post (⌘N) and New Page (⌘⇧N) each create a local draft in the right section, from any section including Media.
- [ ] File → New Media (⌘⌥N) opens the file picker and does not create a post.
- [ ] Edit → **Paste as Markdown** (⌘⇧V) converts Markdown on the clipboard into real blocks (a heading stays a heading, a list stays a list). Plain ⌘V in the same spot is unaffected and still pastes normally.
- [ ] Edit → Find… (⌘F) opens the find bar; File → Save (⌘S) and Publish (⌘⇧P) match the buttons in the editor.
- [ ] File → Revert to Saved… and Preview in Browser are enabled on a remote post and disabled on a local draft.
- [ ] View → Refresh (⌘R) reloads the current section — including while the sidebar is collapsed.

**The site itself**
- [ ] `quill.siolon.com` loads over HTTPS, and the download link on it fetches the current release.
- [ ] The docs page (`site/docs.html`) matches the app: spot-check a few sections against the running build, and confirm nothing describes the pre-native-UI interface (a hand-painted title bar, a toolbar section picker, a sidebar media grid).
- [ ] The changelog's newest entry lists this release's changes; older entries are left as they shipped, including the original "Quill Help" wording for v1.7.0.

---

## Non-functional & resilience

- **Offline / flaky network:** Every network action (save, load, upload, search) shows a user-visible error when it fails. No hangs or crashes.
- **Slow network:** While saving, the save button shows a loading state and is disabled. Clicking rapidly does not submit twice.
- **Large media library:** A media grid with 500+ items scrolls smoothly, paginates correctly, and does not consume unbounded memory.
- **File permissions:** Credential and AI settings files are stored with restricted permissions (only the current user can read them).
- **Crash recovery:** Force-quit the app mid-edit → relaunch → local drafts and autosaved edits are recovered.
- **Typing performance:** On a large document, typing remains responsive (content transforms run on a debounce, not on every keystroke).
- **Security:** Pasting or loading HTML with `<script>` tags or `onerror=` attributes does not execute any scripts. AI-generated HTML is inserted as content only.
- **Thumbnail bandwidth:** The media grid loads small thumbnail images (a few KB), not full-resolution originals. Verify with a network proxy on a grid of large images.
- **Taxonomy caching:** On the second app launch with the same site URL, no `/categories` or `/tags` network requests are made (served from a local cache). Changing the site URL triggers a fresh fetch.

---

## Regression matrix — "known gotchas" guards

Each row is a documented gotcha from `CLAUDE.md`. ✅ = automated test, 👁 = manual verify.

| # | Gotcha | Guard |
|---|---|---|
| 1 | Pages omit `categories`/`tags` | ✅ `WPPostDecodingTests.pageOmittingCategoriesAndTagsDefaultsToEmpty` |
| 2 | `WPPost.type` routing posts vs pages | ✅ `WPPostDecodingTests` + 👁 §7.7 |
| 3 | Scheduling uses `date_gmt` not `date` | ✅ `PostPayloadTests.schedulingUsesDateGmtKeyNotDate` + 👁 §7.7 |
| 4 | Media dimensions as floats | ✅ `WPMediaDecodingTests.floatDimensionsDecodeToInt` |
| 5 | `slug` omitted when empty | ✅ `PostPayloadTests.nilSlugOmitsKeyFromJSON` + 👁 §7.7 |
| 6 | Trash `force=false` vs media `force=true` | ✅ `WordPressClientTests` + 👁 §7.10 |
| 7 | Cancellation re-thrown, not wrapped | ✅ `WordPressClientTests.urlErrorCancelledRethrowsAsCancellationError` |
| 8 | `searchLinks` ignores sub-failures | ✅ `WordPressClientTests.searchLinks*` |
| 9 | Web-search response joined across blocks | ✅ `AnthropicClientTests.multipleTextBlocksAreJoinedInOrder` |
| 10 | Web-search preamble before `TITLE:` | ✅ `AIPromptBuilderTests.webSearchPreambleGluedDirectlyToTitle` |
| 11 | AI prompt must name HTML elements | ✅ `AIPromptBuilderTests.generatePostPromptNamesHTMLElements` |
| 12 | `toWordPressHTML` transforms (all rows) | ✅ JS editor tests + 👁 §7.3 |
| 12a | Empty blockquote `<cite>` stripped on save | ✅ JS `empty cite is stripped` + 👁 §7.3 |
| 13 | List `<p>` unwrap only single-child | ✅ JS `multi-child <li> is left untouched` |
| 14 | Table thead promotion / figure wrap | ✅ JS table tests |
| 15 | Style-guide regeneration rules | 👁 §7.11 |
| 16 | Curly quotes in Swift strings | ✅ `DraftStoreTests.unicodeAndEmojiRoundTrip` + JS `unicode and emoji in text are preserved` + 👁 §7.3 |
| 17 | Autosave restore toast not spurious | 👁 §7.9 |
| 18 | Conflict baseline refresh (no false positive) | 👁 §7.8 |
| 19 | Selection-anchored link popover + sizing | 👁 §7.5 |
| 20 | `AIResultPanel` child-window / shadow / button style | 👁 §7.11 |
| 21 | AI insert at block boundaries (no empty `<p>`) | 👁 §7.11 |
| 22 | Media grid `Color.clear` layout | 👁 §7.2 |
| 23 | Context-menu AutoFill leakage | 👁 §7.14 |
| 24 | Sidebar toggle hides panel and keeps button visible | 👁 §7.2 |
| 24 | macOS 26 spell-check KVC crash | 👁 §7.15 |
| 25 | Ephemeral session (no keychain prompts) | 👁 §7.1 |
| 26 | Sidebar not `List`; layout not `NavigationSplitView` | 👁 §7.2 |
| 27 | `JSONFileStore` writes chmod 600 + atomic | ✅ `JSONFileStoreTests.savedFileHasChmod600` |
| 28 | `AppSupportDirectory` override isolation | ✅ `CredentialsStoreTests.appSupportOverrideKeepsFilesInTempDir` |
| 29 | AI selection ops via right-click, gated on `hasTextSelection` | 👁 §7.11 + 👁 §7.14 |
| 30 | Accepted AI result is Gutenberg-transformed | 👁 §7.11 |
| 31 | `appState.posts` list has empty content (`_fields` filter) | ✅ `WordPressClientTests.fetchAllPostsRequestIncludesFieldsFilter` + `fetchPostRequestOmitsFieldsFilter` + `WPPostDecodingTests.missingContentAndExcerptDefaultToEmpty` |
| 32 | `thumbnailURL` used in grids, not full-res `sourceURL` | ✅ `WPMediaDecodingTests.thumbnailURL*` + 👁 §7.2 |
| 33 | External link navigation restricted to http/https/mailto | ✅ `EditorCoordinatorTests` (all 7) + 👁 §7.5 |
| 34 | `uploadMedia` streams from file, no RAM buffering | ✅ `WordPressClientTests.uploadMediaStreamsFromFileNotHttpBody` + 👁 §7.4 |
| 35 | Code view entity escaping (< & > " in text/attrs) | ✅ `formatHTML — entity escaping` (5 JS tests) + 👁 §7.6 |
| 36 | Block comments preserved by `formatHTML` (nodeType 8) | ✅ `formatHTML — HTML comments` (5 JS tests) + 👁 §7.6 |
| 37 | Stats freeze in code view; refresh on exit | ✅ `countStats` (8 JS tests) + 👁 §7.16 |
| 38 | Find & replace decorations don't re-fire `update` | ✅ `findMatches` (7 JS tests) + 👁 §7.18 |
| 39 | Embed figure passes through, not treated as image | ✅ JS embed tests + 👁 §7.19 |
| 40 | Footnote markers renumbered by `toWordPressHTML` | ✅ JS footnote tests + 👁 §7.20 |
| 41 | Footnotes list excluded from `wp-block-list` | ✅ JS `footnotes list does not get wp-block-list` |
| 42 | `FootnotesList`/`FootnoteItem`/`FootnoteMarker` parse priority | 👁 §7.20 (load existing post with footnotes) |
| 43 | `FootnoteSync` deletes list entry when marker removed | 👁 §7.20 |
| 44 | Footnote backref: `sup` gets `id="ref-fn-…"`, list item gets `<a class="footnote-backref">` | ✅ `toWordPressHTML — footnote backrefs` (3 JS tests) + 👁 §7.20 |
| 45 | Non-image media shows file icon in sidebar cell and "Preview unavailable" in detail view; alt text hidden | 👁 §7.2 |
| 46 | Evaluation `ANCHOR:` field parsed to `finding.anchor`; omission → `nil` | ✅ `EvaluationParserTests.anchorFieldIsParsedIntoFinding` + `.anchorFieldIsNilWhenOmitted` |
| 47 | Classic (pre-Gutenberg) content gets wpautop treatment | ✅ `WPPostDecodingTests.classicContent*` (10 tests) |
| 48 | HTML entities in post/media titles decoded for display | ✅ `WPPostDecodingTests.decodes*` + `.noEntitiesPassthrough` (5 tests) |
| 47 | Style guide injected into evaluation prompt when non-nil/non-empty | ✅ `EvaluatePostPromptTests.promptIncludesStyleGuideWhenProvided` + `.promptOmitsStyleGuideBlockWhenNil` |
| 48 | `stripHTML` decodes typographic entities (smart quotes, em/en dash, ellipsis) | ✅ `EvaluatePostPromptTests.promptDecodesSmartQuoteEntities` + `.promptDecodesTypographicDashAndEllipsis` |
| 49 | Empty state flash before first load (`hasLoadedList`/`hasLoadedMedia`) | ✅ `AppStateLoadingTests` (2 tests) + 👁 §7.1 |
| 49 | Evaluation task cancelled on post switch — stale result cannot appear for new post | 👁 §7.11 (switch posts mid-evaluation) |
| 50 | Confirmation sheets (Revert / Conflict / Replace / Truncation) have ⌘↩ on primary action | 👁 §7.8 + §7.9 + §7.11 |
| 51 | HR → `wp-block-separator has-alpha-channel-opacity` | ✅ JS `hr gains wp-block-separator class` + `hr class is idempotent` |
| 52 | Tiptap table artifacts stripped (style, colgroup, default colspan/rowspan, p-in-cell) | ✅ JS table cleanup tests (3 tests) |
| 53 | AI Make Longer/Shorter uses list/table-specific prompts when context detected | ✅ `AIPromptBuilderTests.makeLongerWithListContextUsesListInstruction` + 3 siblings + 👁 §7.11 |
| 54 | AI selection detection uses ProseMirror state (handles reversed/table selections) | 👁 §7.11 (select in table, right-click) |
| 55 | AI result panel clamps to webview bounds, fallback for invalid rects | 👁 §7.11 |
| 56 | Footnote content restricted to inline-only (no images, block elements, keyboard shortcuts) | 👁 §7.20 |
| 57 | Image drops rejected in footnotes with error toast | 👁 §7.20 |
| 58 | Paste in footnotes strips block elements to inline text | 👁 §7.20 |
| 59 | Update checker version comparison handles all semver cases, and strips the tag's `v` prefix first | ✅ `UpdateCheckerTests` (12 tests) |
| 60 | Draft save failure shows error toast | 👁 §7.7 |
| 61 | `syncContentToSwift` fires after AI-generated content set | 👁 §7.11 (generate post, verify autosave captures content) |
| 62 | Backspace/Delete passthrough inside footnotes (`_fnPassthrough`) | 👁 §7.20 (delete chars in footnote entry) |
| 63 | Image caption Enter exits to paragraph below (imageCaptionExit plugin) | 👁 §7.4 (Enter in caption) |
| 64 | Blockquote Enter: splits paragraphs inside, lifts empty paragraph out | 👁 §7.3 (Enter behavior in blockquote) |
| 65 | Cite toggle button adds/removes cite node in blockquote | 👁 §7.3 (cite toggle) |
| 66 | Footnote back-arrow is `contentEditable: false` (not selectable/editable) | 👁 §7.20 (↩ not part of editable text) |
| 67 | Excerpt field does not adopt auto-generated `rendered` excerpt from WordPress | ✅ `WPPostDecodingTests.excerptText*` (4 tests) |
| 68 | `stripHTML` phantom space before punctuation after inline tags | ✅ `AIPromptBuilderTests.promptDoesNotInjectSpaceBeforePunctuationAfterInlineTags` + `.promptStripsSpaceBeforeClosingPunctuation` |
| 69 | Anchor matching tolerates whitespace differences around punctuation | ✅ `findMatchesLoose` (7 JS tests) + `fuzzyAnchorRegex` (3 JS tests) |
| 70 | Footnote Enter inserts soft break (not swallowed) | ✅ `test-editor-keyboard.js` footnote Enter test + 👁 §7.20 |
| 71 | Blockquote Enter with selection deletes selection before split | ✅ `test-editor-keyboard.js` blockquote selection test + 👁 §7.3 |
| 72 | Image toolbar scroll handler cleaned up before reattaching | 👁 §7.4 (select multiple images in sequence) |
| 73 | Image toolbar clamped below main toolbar-wrap | 👁 §7.4 (scroll image near top of viewport) |
| 74 | Cmd+click opens links (scheme-restricted via `isAllowedExternalURL`) | ✅ `EditorCoordinatorTests` + 👁 §7.5 |
| 75 | `WordPressClient` query params escape literal `+` to `%2B` | ✅ `WordPressClientTests.searchQueryPlusCharacterIsPercentEscaped` |
| 76 | AI-generated `<cite>` wrapper stripped but inner citation text kept, even across a nested inline tag | ✅ `AIPromptBuilderTests.citeTagWrapperStrippedButTextKept` + `.citeTagWithNestedInlineTagStillStripped` + `.emptyCiteTagRemovedEntirely` |
| 77 | `AnthropicClient` transport errors wrapped as `AnthropicError.networkError` with friendly offline message | ✅ `AnthropicClientTests.networkFailureWrapsAsAnthropicNetworkError` + `.networkErrorShowsFriendlyMessageWhenUnderlyingDescriptionMentionsOffline` + `.networkErrorPassesThroughUnrecognizedMessage` |
| 78 | `AnthropicClient` decodes responses with `stop_reason` omitted (Optional) | ✅ `AnthropicClientTests.missingStopReasonFieldDoesNotThrowAndIsNotTruncated` |
| 79 | MIME type lookups consolidated into `MimeType.forFile`/`forExtension` (no per-call-site drift) | ✅ `MimeTypeTests` (12 tests) |
| 80 | `SidebarView.loadAllSections`/`UpdateChecker.check` don't rerun on sidebar remount when credentials unchanged | 👁 §7.2 (toggle sidebar visibility, confirm no refetch) |
| 81 | `PostEditorView` refuses to save when the full-post load failed (`contentLoadFailed`) | 👁 §7.7 (simulate load failure, attempt save) |
| 82 | Taxonomy creation retry doesn't resubmit already-created pending names | 👁 §7.7 (create post with 2+ new tags, force one to fail, retry save) |
| 83 | `AIResultPanel` event monitor not double-registered across repeated `show()` calls | 👁 §7.11 (trigger AI op twice via right-click without dismissing) |
| 84 | Toast dismiss timer restarts on every `presentToast()` call via a bumped `toastToken`, even when two consecutive toasts share identical text (keying `.task(id:)` on the message string alone couldn't detect that case) | 👁 §7.9 (trigger two consecutive same-text toasts — e.g. save twice with no changes — and confirm the second shows for a full 2s. Note: a multi-image drop now raises one summary toast, so it no longer exercises this) |
| 85 | `PostEditorView.loadItem()` bails out of its catch block on a stale/cancelled load instead of writing `contentLoadFailed`/`saveError` for whichever post is now displayed | 👁 §7.7 (switch away from a post before its full-content fetch fails) |
| 86 | `saveError` is reset at the start of every `loadItem()` call so a stale error banner from a previous failed load doesn't persist over a subsequently-opened post or draft | 👁 §7.7 (fail a post load, then open a different post/draft that loads fine) |
| 87 | `UpdateChecker.check()` throws on transport/decode failure so `hasCheckedForUpdate` only latches on success, matching `lastLoadedCredentials`'s retry-on-failure semantics | 👁 §7.21 (simulate a network failure on first check, confirm a later remount retries) |
| 88 | `APIError`/`AnthropicError` share one `NetworkErrorHeuristics.isConnectivityFailure` substring check instead of two independently-maintained copies | ✅ `AnthropicClientTests.networkErrorShowsFriendlyMessageWhenUnderlyingDescriptionMentionsOffline` + `.networkErrorPassesThroughUnrecognizedMessage` |
| 89 | Existing galleries loaded from a post survive as an atomic `galleryBlock` node (not the `_rawHTML` verbatim safety net) — an unrelated visual edit elsewhere no longer silently drops the gallery on save | ✅ `WPPostDecodingTests.blockGalleryContentSurvivesEditorHTML` + JS `toWordPressHTML — gallery` (16 tests) + `galleryBlock` load/round-trip tests (13 tests) + 👁 §7.4 |
| 90 | `galleryBlock.parseHTML` never returns `false`/degrades to standalone images for a gallery it can partially handle (e.g. captions) — only for zero-image-figure input | ✅ `galleryBlock` — verbatim re-render tests (2 tests, caption preserved via `sourceHTML`) |
| 91 | `toWordPressHTML`'s upfront strip of pre-existing `wp:embed`/`wp:gallery`/`wp:image` comments uses a non-greedy attrs match (`[\s\S]*?-->`) so it can't span past the first comment's close and delete image figures between two adjacent comments with no newline separator (a loaded gallery's `sourceHTML` has no such guarantee, unlike this function's own freshly-wrapped output), and stays immune to a stray `\r` before a comment's own `-->` (JS `.` excludes all line terminators, not just `\n`, so a `.*?` group — unlike `[\s\S]*?` — would fail to match at all in that case) | ✅ `toWordPressHTML — gallery.'stripping pre-existing wp:image comments does not consume the images between them'` + `.'stripping a pre-existing wp:gallery comment works even with a CR before its closing -->'` |
| 92 | Tiptap's default gap-cursor widget (black horizontal bar) is restyled via CSS to the app's blue vertical caret wherever the caret sits next to an atomic `galleryBlock`/`embedBlock` node — fixed at the CSS layer, not by inserting/stripping a synthetic trailing paragraph in the doc model | ✅ `gap-cursor styling` (1 test) + `window.insertGallery bridge function.'inserting at the end of the doc does not synthesize a trailing paragraph'` + 👁 §7.4 |
| 93 | Gallery `linkTo: 'media'` links to the image's `fullUrl` (true full-resolution original), not its display-size `url` — a non-full Size selection no longer silently links thumbnails to themselves instead of the original file | ✅ `galleryBlock — insert and render.'linkTo media links to fullUrl (true original), not the display-size url'` + `.'linkTo media falls back to url when fullUrl is absent'` + 👁 §7.4 |
| 94 | `WPMedia.sizedURL(for:)` falls back to `sourceURL` when the matched size entry's `source_url` decoded to an empty string (not just when the entry is absent) — matches the existing `thumbnailURL` guard for the same WordPress API quirk | ✅ `WPMediaDecodingTests.sizedURLFallsBackToSourceURLWhenMatchedSizeHasBlankURL` |
| 95 | `GallerySheet`'s Upload button adds the newly-uploaded image directly to the gallery's `selected` list, not just the media grid — matches the evident purpose of an inline upload button inside a gallery-building flow | 👁 §7.4 (click Upload, confirm the new image is already checkmarked/listed in Selected without an extra click) |
| 96 | Single (non-gallery) image's "Link to Full Image" toggle: `ResizableImage.linkTo`/`linkHref` attrs parse from a pre-existing `<a>` wrapper on load (figure-wrapped **and** bare `img[src]`/classic-content markup), require a non-empty `href` to count as linked, round-trip through `toWordPressHTML` on save, and coexist with alignment/custom class/`mediaId` | ✅ `test-editor-keyboard.js` `image link-to-full-size` (7 tests) + 👁 §7.4 |
| 97 | Image toolbar's "Link to Full Image" button is always available (not hidden for images with no `mediaId` or whose media sizes lack a `"full"` entry) — toggling on falls back to the image's current `src` when no media-library size data is known, so an already-linked externally-sourced image is never stuck with an unreachable toggle; toggling off also clears the stale `linkHref` | 👁 §7.4 (select a drag-dropped/external image with no media ID, confirm the Link to Full Image button is visible and toggles correctly) |
| 98 | `EditorCoordinator.mediaSizesDict(for:)` synthesizes a `"full"` size entry from `media.sourceURL` when WordPress's `media_details.sizes` omits one (a common API shape) — mirrors the existing `WPMedia.sizedURL(for:)` fallback for the same quirk, so the Full-size preset button and Link to Full Image toggle aren't silently disabled for images that have other sizes but no explicit `"full"` entry | ✅ `EditorCoordinatorTests.mediaSizesDictAddsFullFallbackWhenSizesOmitsIt` + `.mediaSizesDictPreservesExistingFullEntry` + `.mediaSizesDictFallsBackToSourceURLWhenNoSizesAtAll` + `.mediaSizesDictReturnsNilWhenSourceURLIsEmpty` |
| 99 | Unmodeled Gutenberg blocks (Accordion, Columns, Group, etc.) no longer get silently flattened/merged when a post is loaded or code view is exited — a `gutenbergPassthrough` atomic node captures the element's `outerHTML` verbatim and survives unrelated edits elsewhere in the doc, instead of ProseMirror's default "no rule matched, recurse into children" behavior destroying the wrapper structure | ✅ `test-editor-passthrough.js` class-only + comment-wrapped suites (6 tests) + `parsePassthroughBlock` (5 JS tests) + 👁 §7.3 |
| 100 | `gutenbergPassthrough`'s catch-all parse rule (`[class*="wp-block-"]:not(figure)`, priority 1) never claims an element another node already owns — headings, lists, footnote lists, quotes, code blocks and separators keep winning despite their `wp-block-*` class, and `figure.wp-block-table` (which has no dedicated parse rule of its own and relies on transparent pass-through to the bare `<table>`) still reaches the table node via the figure rule's `QUILL_MODELED_FIGURE_CLASSES` exemption | ✅ `test-editor-passthrough.js` `'does not steal elements other rules already claim'` (11 tests) + `'modeled figures still go to their own nodes'` (4 tests) |
| 101 | `toWordPressHTML`'s unconditional whole-tree passes (comment-strip regex, plus heading/cite/figure/list/table/footnote normalization) can't distinguish Quill's own content from a `gutenbergPassthrough` subtree's nested content — passthrough elements are stashed out via placeholder divs *before any pass runs* and spliced back in verbatim only after every pass has completed, so a `wp:group` wrapping a real `wp:image` keeps its nested comment, and a nested `<h3>`/`<cite>`/`<figcaption>` is never mutated by the heading-class/empty-cite/empty-figcaption passes. Splicing back too early (right after the comment-strip alone) was an initial-implementation regression caught in code review — only the comment regex was shielded, not the other passes | ✅ `toWordPressHTML — passthrough blocks` (8 JS tests, incl. nested `wp:image`/`wp:gallery` regressions and the byte-for-byte heading/cite/figcaption guard) + `test-editor-passthrough.js` `'nested media blocks survive save'` (2 tests) |
| 102 | `RenderedString.editorHTML`'s classic-vs-block content heuristic checks for a `wp-block-` class substring, not just `<!-- wp:` comments and `<p>` tags — without it, a post consisting entirely of class-only Gutenberg block markup (`gutenbergPassthrough`'s target case: no comment, no paragraph) was misclassified as classic content and corrupted by `wpautop()` before the JS-side parser ever saw it, defeating the passthrough feature's byte-for-byte round-trip on the very next load | ✅ `WPPostDecodingTests.classOnlyGutenbergBlockContentUnchanged` |
| 103 | `formatHTML`'s `BLOCK` set gained `div` so `gutenbergPassthrough`'s nested divs indent correctly in code view, but this also reformats the pre-existing `EmbedBlock` wrapper div (whose only child is a text node with literal `'\n'+url+'\n'`) — without trimming, the URL and closing `</div>` land on unindented lines below the opening tag. Fixed by trimming a block tag's text content when it has no element children at all | ✅ `formatHTML — nested block elements.'a div with only raw-newline text content...'` |
| 104 | The greedy-comment-strip regression class (row 91) re-exercised **with captions present**: a `<figcaption>` puts another element between two adjacent `wp:image` comments inside a loaded gallery's verbatim `sourceHTML`, which every debounced save re-runs `toWordPressHTML` over. A caption must not be hoisted onto the gallery wrapper, attached to the wrong image, duplicated, or consumed along with its image figure by an unrelated edit elsewhere in the doc | ✅ `galleryBlock — captions survive load → edit → save` (2 tests) + `toWordPressHTML — gallery.'a gallery caption stays the last child of its own nested image figure'` + `.'each gallery caption is wrapped inside its own wp:image comment pair'` + `.'wrapping a captioned gallery is idempotent'` + 👁 §7.4 |
| 105 | Per-image gallery alt text and captions come straight from `TextField`s in `GallerySheet`, so both are serialized as data, never markup: the caption is written with `textContent` (never `innerHTML`) and the alt attribute value can't be broken out of by embedded quotes or tags. Alts also stay bound to their own image in payload order, and an omitted alt still emits `alt=""` rather than dropping the attribute (an accessibility regression, not a cosmetic diff) | ✅ `galleryBlock — per-image captions.'caption text containing markup is escaped, not injected'` + `.'alt text containing quotes and markup is escaped, not injected'` + `.'each per-image alt lands on its own img, in order'` + `.'an omitted alt still emits an empty alt attribute'` + 👁 §7.4 |
| 106 | `WPMedia.captionText` reads `caption.raw` only (via `RenderedString.excerptText`) and returns `""` for a rendered-only payload — the gallery sheet's Caption field prefills with plain text or nothing, never with the `<p>`-wrapped `rendered` HTML WordPress returns outside `context=edit` | ✅ `WPMediaDecodingTests.captionDecodesPlainTextFromRaw` + `.captionRawHasHTMLStrippedAndEntitiesDecoded` + `.captionWithOnlyRenderedYieldsEmptyText` + `.missingCaptionIsNilAndTextIsEmpty` + 👁 §7.4 |
| 107 | `GallerySheet.toggle(_:)` removes the image's id from `expandedIDs` when deselecting, so expanded state can't leak: re-selecting the same image previously brought its row back already expanded — and therefore already `moveDisabled`, silently unable to be drag-reordered. An expanded row is `moveDisabled(true)` because a `List` row's drag gesture otherwise steals mouse-down from the inline `TextField`s; hovering the drag grip collapses the row to restore dragging. No SwiftUI test harness exists for any of this | 👁 §7.4 (expand a row, deselect it in the grid, re-select it → collapsed and draggable; and: expand a row, confirm dragging is disabled, hover the grip, confirm it collapses and drags) |
| 108 | `gutenbergPassthrough` gained a second, figure-only parse rule (`figure[class*="wp-block-"]`, priority 1). The original catch-all excluded every `<figure>` on the assumption Quill modeled them all — it models four. Every other `wp-block-*` figure was destroyed on save: `figure.wp-block-audio` collapsed to a bare `<p>` holding only its caption text, `figure.wp-block-video` to an empty `<p>`, `figure.wp-block-pullquote` was silently rewritten as `blockquote.wp-block-quote`, and WordPress 7.1's `figure.wp-block-playlist` lost its wrapper, block comments and `<figcaption>`. All four are now preserved byte-for-byte as passthrough cards, keep their position among modeled blocks, and are stable across repeated load/save cycles | ✅ `test-editor-passthrough.js` `'figure-rooted blocks Quill does not model'` (5 tests) + `'figure blocks and the rest of the document'` (4 tests) + 👁 §7.3 |
| 109 | `isModeledFigure(el)`/`QUILL_MODELED_FIGURE_CLASSES` is the sole exemption list for the figure rule, and the two sides use different matching: the parse selector is substring-based (`[class*="wp-block-"]`) while the exemption is exact `classList` membership. A third-party `wp-block-image-slider` or `wp-block-tableau` must therefore reach passthrough rather than be handed to the image/table rule, and the set itself is drift-guarded — adding a class without also giving that figure a real parse rule sends the block to the generic parser, removing one freezes a working block into a static card | ✅ `isModeledFigure` (8 JS tests) |
| 110 | WordPress 7.1's "Mark as decorative" image toggle writes `role="none"` on the `<img>`; the `imgRole` attr parses it and round-trips it through `toWordPressHTML` under both the `figure.wp-block-image` rule and the bare `img[src]` classic-markup fallback, stays on the `<img>` rather than the `<a>` when the image also links to full size, emits nothing when the source had no role, and treats `role=""` as absent | ✅ `test-editor-keyboard.js` `'image marked as decorative (WP 7.1)'` (7 tests) + 👁 §7.4 |
| 111 | WordPress 7.1 accepts HEIC over the REST API but cannot generate sub-sizes for it, so the attachment lands with no dimensions and no sizes. `ImageConversion.prepareForUpload` converts HEIC/HEIF to JPEG locally first (quality 0.9), preserving EXIF orientation and pixel dimensions, writing to a per-upload UUID temp directory that `cleanup()` removes whole; JPEG/PNG/PDF pass through untouched, a file ImageIO cannot decode falls back to the original rather than blocking the upload, and two same-named files converted in one drop don't collide | ✅ `ImageConversionTests` (17 tests) + 👁 §7.4 |
| 112 | `ImageConversion.prepareForUpload` is a synchronous decode + re-encode, so the two MainActor-isolated callers (`PostEditorView.handleDroppedImages`, `MediaSidebarSection.uploadFromDisk`) run it inside `await Task.detached(priority: .userInitiated) { … }.value` rather than inline — calling it directly froze the UI for the length of the conversion. `uploadPickedImage` was already off the main thread | 👁 §7.4 (drop a large HEIC photo, confirm the editor stays responsive and does not beachball while it converts) |
| 114 | `window.insertImage` leaves the cursor in an empty paragraph *after* the new figure instead of inside its empty `<figcaption>` — typing straight after an insert used to silently write caption text. The caption is untouched and still clickable, so captioning is opt-in; consecutive inserts reuse the previous trailing paragraph rather than stacking blank ones; and the insert stays scoped to its container (list item, blockquote, table cell) or is refused outright (footnotes). Intended consequence: saved content gains an empty `<p></p>` after the image block. All three insert paths (toolbar, post-upload, Finder drop) share the function | ✅ `test-editor-keyboard.js` `'window.insertImage cursor placement'` (14 tests) + 👁 §7.4 |
| 115 | A Finder drop shows an `UploadStatusPill` before HEIC conversion even starts, and a multi-file drop ends in **one** summary toast rather than one toast per file — per-file toasts overwrote each other so a 3-image drop effectively reported nothing. The message builders are pure statics so the wording (singular vs plural, the "Converted to JPEG" note, partial-failure counts) is pinned by tests even though the pill itself is untestable SwiftUI state | ✅ `PostEditorHelpersTests` "Dropped-image upload feedback" (10 tests) + 👁 §7.4 |
| 116 | `UploadStatusPill` and the toast share one bottom slot, so overlapping Finder drops raced on `uploadStatus`: a second batch dropped mid-upload cleared the pill early and let a toast and the pill render on top of each other. `PostEditorView` holds a `@State private var dropTask: Task<Void, Never>?` and the `onImageFilesDropped` callback chains each batch onto the previous one (`await previous?.value`), so drop batches never interleave. Any future code that writes `uploadStatus` must go through the same queue. Pure SwiftUI view plumbing with no extractable helper — manual only | 👁 §7.4 (drop a batch, drop a second batch while the pill is still counting, confirm pill and toast never overlap) |
| 113 | Standalone (non-gallery) images saved without `<!-- wp:image -->` comments, so WordPress parsed them as classic HTML rather than core/image blocks and offered no image controls; `data-media-id`, an editor-internal attribute, also shipped in post content. `toWordPressHTML` now wraps every standalone `figure.wp-block-image` in a `wp:image` pair with the attributes it can derive, skips gallery-nested figures so the gallery pass keeps owning those, and removes `data-media-id` once the `wp-image-{id}` class is emitted | ✅ `test-editor.js` `'standalone image block comments'` (9 tests) |
| 117 | ProseMirror renders a `style` attribute by assigning `element.style.cssText`, which parses the declaration into the CSSOM and writes it back normalized — `color:#cf2e2e` became `color:rgb(207, 46, 46)` in both engines, and WebKit also moved the attribute to the end of the tag. Gutenberg compares the stored `style` against what `save()` regenerates from the comment attributes, so every coloured paragraph, heading, list and button was invalidated on the first edit. A style WordPress wrote now rides as `data-quill-style` and `toWordPressHTML` rebuilds the element's attribute list to rename it back, keeping both the value and its position verbatim | ✅ `test-editor-block-settings.js` `'inline styles and delimiter attributes are written the way core writes them'` + `settings-paragraph-color.html`, `settings-list.html` + 👁 `--check-fixtures` |
| 118 | Delimiter attributes went out through `JSON.stringify` at five save sites instead of core's `serializeAttributes`, so `--` (invalid inside an HTML comment), `<`, `>`, `&` and `\` were left unescaped. Carried keys were also spread rather than overlaid, which moved every key the node recomputes to the end of the comment and diffed every post | ✅ same describe block + `settings-embed.html` |
| 119 | A node that renders a child element from a fixed template discarded everything core wrote on that child: a button's `<a>` lost its colour classes and border radius, an image's `<a>` lost `target`/`rel`/`class` and had its `linkDestination` rewritten from `custom` to `media`, and an accordion heading lost its colour classes. `RAW_CHILD_ATTRS` snapshots those children by tag and `replayClassList` replays every class the node cannot write itself, in the source's own order | ✅ `test-editor-block-settings.js` `"attributes on a node's child elements survive"` + `settings-button-color.html`, `settings-accordion-color.html`, `settings-image.html`, `settings-image-custom-link.html` |
| 120 | A quote's non-paragraph inner blocks lost their delimiters — a heading or list inside a `core/quote` came back as bare markup, which fails core's validation. `blockquote`'s descriptor is now `shape: 'container'` and recurses like any other, skipping `<cite>` | ✅ `test-editor-block-settings.js` `'a quote holds inner blocks, not bare markup'` + `settings-quote-inner.html` |
| 121 | A table's `has-fixed-layout` class was dropped, because the parse rule matches the `<figure>` and never saw the `<table>`'s own class. Gutenberg then accepted the block through a *deprecation* whose default is `false` and silently migrated the setting off, so every WordPress-made table lost fixed layout after any Quill edit with no error anywhere. The `hasFixedLayout` attribute now reads the class first and the comment second, and a Quill-inserted table gets the class so it matches the current `save()` | ✅ `test-editor-block-settings.js` `'a table carries its own fixed-layout setting'` + `settings-table-fixed.html` |
| 122 | `<img>` and `<hr>` were written bare where core self-closes them, so every edited post diffed on every image and separator in WordPress revision history. The void-element pass steps over quoted attribute values (`(?:"[^"]*"|'[^']*'|[^>"'])*`) — a naive `<img[^>]*>` ends the match at the `>` inside an `alt="a <b> tag"`, because HTML escapes `&` and `"` in an attribute value but not `<` or `>` | ✅ `test-editor-block-settings.js` `'void elements are written the way core writes them'` + the gallery suite's hostile alt strings |
| 123 | `blockSourceSlices` had no byte offsets, so it walked a cursor and resynced on `'<!-- /wp:'` — which for a self-closing block is the *next* block's close comment. One non-canonical block cost byte-exactness for every block after it. `topLevelBlockRanges` now scans WordPress's own delimiter pattern with a nesting depth counter and returns real offsets, falling back to the reconstruction walk only when the delimiters do not nest | ✅ `test-block-serializer.js` `'blockSourceSlices'` (incl. the non-canonical, nested and unclosed cases) |
| 124 | Two preservation mechanisms with different fidelity: top-level unmodeled blocks were routed to the class-based `gutenbergPassthrough` card whenever their markup carried a `wp-block-*` class, and that card is not byte-exact — Tiptap's `elementFromString` strips inter-element whitespace before any parse rule runs, so Group, Cover and Media & Text lost the newlines between their inner blocks on every edit. A `wp:html` block holding one `wp-block-*` classed element also lost its identity entirely. `blockNeedsWrapping` is now `!!blockName && !modelsBlockName(blockName)` (plus the no-markup guard), so every unmodeled top-level block takes the exact-slice path and the class rule is left to hold nested blocks only | ✅ `test-block-serializer.js` `'blockNeedsWrapping'` + `'wrapUnsupportedBlocks'` + `settings-group.html`, `settings-media-text.html`, `settings-spacer.html` + 👁 `--check-fixtures` |
| 125 | The data-loss tripwire compared *sets of names* over top-level blocks only, so a post with two `wp:html` blocks stayed silent when one went missing (the survivor accounted for the name) and never looked inside a modeled container at all. It now counts every block name at every depth on both sides and reports any name the document holds fewer of, and it runs after a code-view edit as well as a load | ✅ `test-editor-preservation.js` `'the alarm reports only genuine loss'` + `test-block-serializer.js` `'countBlockNames and unrepresentedBlockNames'` |
| 126 | `EditorCoordinator.setContent` deduped on the HTML alone, so a footnote-only difference — an autosave restore, or two drafts sharing a body — never reached JS. `EditorPushState` holds both halves and each message handler records its own | ✅ `EditorPushDecisionTests` (4 tests) |
| 127 | The Link mark modelled only `href`/`target`/`rel`, so core's `title` and its own `data-*` on an anchor were dropped on the first edit | ✅ `test-editor-inline-formats.js` `'a link keeps the attributes the mark does not model'` |
| 128 | Every heading emitted `{"level":2}`, which core omits because 2 is the default — harmless to Gutenberg, noise in every post's diff. An h2 Quill authored now writes no level, while an h2 whose comment explicitly carried one keeps it | ✅ `test-block-serializer.js` `'block descriptors'` + `test-editor-block-settings.js` `'a heading omits the level core treats as the default'` |
| 129 | A classic (undelimited) post is **converted** to blocks on the first edit, and a wrapper element the conversion has no block for — a bare `<div class="custom-box">` — is dropped with its class. The tripwire is silent because freeform content is not a block. This is the same flattening Gutenberg's own "Convert to blocks" performs and is almost certainly wanted, but it is a conversion, not preservation | 👁 §7.3 (open a classic post, type one character, save, compare the raw content) — recorded in the block-model design spec under "Existing posts are out of scope" |
| 130 | The raw-attribute carrier replayed **every** attribute of a loaded element onto the live contenteditable, `on*` handlers from post content included, which then ran inside the privileged web view. `isCarryableAttr` now filters at all three snapshot points | ✅ `test-editor-preservation.js` `'an attribute that could run script is not carried'` (7 tests) |
| 131 | The placeholder left where a preserved block sat was the fixed string `QUILLUNSUPPORTED<n>QUILLEND`; an author could type it into a post and the first-occurrence replace then moved the preserved bytes to that text — silently, because the block count never changed. It is a per-save random nonce now, substituted with one global pass | ✅ `test-editor-preservation.js` `'preserved block bytes cannot be relocated by post text'` |
| 132 | The trailing-paragraph strip removed the last child whenever it was an empty `<p>`, which also deleted an empty `core/paragraph` an author wrote at the end of a post. Scoped to the shapes `TRAILING_PARAGRAPH_AFTER` actually follows | ✅ `test-editor.js` `'trailing paragraph'` (5 tests) |
| 133 | The leading-whitespace strip on top-level paragraphs used `/^\s+/`, which in JavaScript also matches U+00A0, so deliberate `&nbsp;` indentation was deleted. Now `/^[\n\r\t ]+/` | 👁 §7.3 — **no automated guard**; an `&nbsp;` test would be worth adding |
| 134 | A passthrough card's markup was shielded from the comment-strip regex but not from the style-compaction and void-element passes, so `style="color: red"` became `style="color:red"` and `<img src="x">` became `<img src="x"/>`. Its content is stashed behind the nonce now, like an unsupported wrapper | ✅ `test-editor.js` `'inner image markup survives exactly as authored'` |
| 135 | `normalizeAITables`'s `table\b` matched the `table` in `<table-of-contents style="…">` and rewrote it into `<table class="has-fixed-layout"-of-contents>`. The match now ends at `(?![-\w])` | ✅ `AIPromptBuilderTests` `cleanOperationResult` & `normalizeAITables` (13 tests) |
| 136 | The block-risk guard was on `save(status:)` and `performAutosave` only, so switching posts, closing the editor, or ⌘S on a local draft still wrote the squashed content. `flushToDB` and `saveLocalOnly` check `alarmBlocksSaving` too | 👁 §7.22 — `alarmBlocksSaving` is view state with no test harness; the banner stages it reads *are* unit-tested |
| 137 | Editing only a footnote *body* changes no content HTML, so the post never read dirty: no dot, no autosave, and the post-switch flush was skipped, losing the edit. `isDirty` compares the footnotes as well | ✅ `DraftStoreTests.footnotesSurviveAnEditThatOnlyChangesTheContent`, `AutosaveStoreTests.replacingAnAutosaveKeepsTitleContentAndFootnotesInStep` + 👁 §7.20 |
| 138 | The banner blocked saving even on an untouched post, which saves `_rawHTML` back byte-for-byte and cannot lose anything — the user had to click through a content-deletion warning for a lossless save. `alarmBlocksSaving` adds `htmlContent != cleanContent` | 👁 §7.22 — same view-state limit |
| 139 | Repairing a post in code view left saving blocked until it was reopened, because the editor only reported a non-empty at-risk list. It reports on every load and code-view edit now, empty included, and `nextAlarm` clears or preserves the stage | ✅ `BlockRiskAlarmTests.anEmptyReportClearsTheAlarm` + 3 more, `test-editor-preservation.js` `'a code-view edit that loses a block is reported'` + 👁 §7.22 |
| 140 | `--check-fixtures` with no path silently launched the GUI instead of running the fixture check | ✅ manual: `./Quill.app/Contents/MacOS/Quill --check-fixtures` prints a usage line and exits 2 |
| 141 | Media paging ran off a page cursor, so a local upload or delete shifted the server's rows under it — the next page repeated an item or skipped one. `MediaLibraryView.loadMoreMedia` sends `offset: appState.mediaItems.count` instead, because the local count *is* the window into the server's filtered list | ✅ `WordPressClientTests.fetchMediaOmitsOffsetUnlessAsked` + `fetchMediaSendsTheRequestedPageAndPageSize` + 👁 §7.x |
| 142 | An upload made under a filter that excludes it was inserted into `mediaItems` anyway, so it was invisible and it desynced the paging offset. `MediaFilter.matches(_:)` now mirrors `mediaTypeParameter`, and a non-matching upload switches the filter to All Media | ✅ `MediaFilterTests.matchesAcceptsOnlyWhatTheServerFilterWouldReturn` + 👁 §7.x |
| 143 | `DocumentEditedMarker.dismantleNSView` cleared the dot through `nsView.window`, which is already nil whenever SwiftUI detached the view first — the window's unsaved-changes dot stayed lit with no editor open. `MarkerView` holds a `weak var markedWindow` and clears through that | 👁 §7.9 — `NSViewRepresentable` teardown has no test harness |
| 144 | The heading indicator kept the last post's level after a load, because `_clearToolbarContext` — the reset that runs in place of `updateToolbar` while `_toolbarIdle` is set — is the only path that touches it | ✅ `test-editor-containers.js` `'a load leaves the heading indicator neutral even when the post opens on a heading'` + `'placing the caret in that heading restores the indicator'` |
| 145 | Two overlapping uploads shared `isUploading`, so the second's completion cleared the spinner while the first was still running. `MediaLibraryView` chains them through a `uploadTask` awaiting the previous one, the same pattern as `PostEditorView`'s `dropTask` | 👁 §7.x — SwiftUI view state with no harness |
| 146 | Check Spelling crashed Quill: the NSSpellChecker completion closure inherited main-actor isolation and trapped when called on the text-checking queue. It is `@Sendable` now and hops to the main queue with plain strings | ✅ `EditorCoordinatorTests.misspelledWordsReturnsOnMainActorWithoutTrapping` |
| 147 | A post with two galleries raised a false Gallery-at-risk banner, which blocks saving after an edit: `_accountedBlockCounts` added a source-backed node's own name only if the whole post's count lacked it | ✅ `test-editor-preservation.js` `'a second gallery in the same post is not reported'` |
| 148 | Make Shorter / Make Longer (and the convert operations) on part of a paragraph replaced the whole paragraph, deleting unselected sentences. `showAIResult` now replaces exactly the selection, inserting a lone `<p>` result inline, and restores the pre-operation document itself rather than round-tripping HTML, which shifted positions after a split | ✅ `test-ai-output-validity.js` `'a right-click AI result replaces only the selection'` |
| 149 | After publishing a remote draft the toolbar kept saying Publish until the post was reselected: `isPublishedRemote` read the post as selected, not the cached copy `save()` updates | 👁 §7 publish checks — SwiftUI view state with no harness |
| 150 | The Media panel looped ~20 requests a second whenever a load failed, and flashed a second Media Info button: `.inspector` was attached outside `MediaLibraryView`, so its `.task` was rebuilt on every branch switch | 👁 manual — see `Views/Media/CLAUDE.md` |
| 151 | On a site with `WP_DEBUG_DISPLAY` on, one PHP warning made every Media listing unreadable, because Quill's GET requests did not send `Accept: application/json`, the signal WordPress uses to turn `display_errors` off | ✅ `WordPressClientTests.requestsAcceptJSONSoWordPressHidesPHPWarnings` |
| 152 | A plugin or theme printing a PHP warning ahead of the JSON made every request fail with a generic decoding error. `APIError.decodingError` now says a plugin or theme may be adding text to the reply | ✅ `WordPressClientTests.phpWarningAheadOfJSONExplainsThePluginCause` |
| 153 | Make Longer / Make Shorter gave Claude no length target, so the result did not scale with the selection. The prompt now names a word target tiered at 40 and 150 words, never 0, and none for list or table context | ✅ `AIPromptBuilderTests.lengthTiersSwitchAtFortyAndAfterOneHundredFiftyWords`, `makeShorterNeverTargetsZeroWords`, `wordTargetCountsWordsAcrossParagraphBreaks`, `listAndTableContextsGetNoWordTarget` |
| 154 | A plain-text AI result inserted inline went in through Tiptap's `insertContentAt` as an HTML string, which Tiptap inserts verbatim when it has no marks: `R&amp;D` appeared literally and saved as `R&amp;amp;D`. It goes in as a text node built from the decoded text now | ✅ `test-ai-output-validity.js` `'a plain-text result holding … goes in as text, not markup'` (3 tests) + 👁 §7.11 |
| 155 | A selection that included the space before or after a sentence lost that space, gluing the result to its neighbour. The inline range now shrinks off an edge space | ✅ `test-ai-output-validity.js` `'a selection with a {trailing, leading} space keeps the space'` (2 tests) + 👁 §7.11 |
| 156 | A reply that was empty after cleanup left Accept/Discard showing over the "✶ Rewriting…" placeholder. `showAIResult` returns `true` or `null`, and Swift discards and shows the error toast on `null` | ✅ `test-ai-output-validity.js` `'showAIResult reports whether it inserted anything'` (JS half) + 👁 §7.11 (Swift half) |
| 157 | Switching posts while an AI operation was in flight let the reply land in the newly opened post. `setContent` clears the AI state, `showAIResult` refuses with no operation in progress, and `PostEditorView` cancels `aiTask` and dismisses the result panel in `loadItem()`. Still open: the old post's flush can save the placeholder (`Views/Editor/CLAUDE.md`) | ✅ `test-ai-output-validity.js` `'a result that arrives after the post changed leaves the new post alone'` + 👁 §7.11 |
| 158 | With the original kept as HTML, Discard went through `getHTML`/`setContent`, which trims a paragraph's trailing space. `_aiOriginalDoc` keeps the ProseMirror doc itself, and Discard posts the restored HTML to Swift | ✅ `test-ai-output-validity.js` `'discarding keeps a space the author just typed at the end of a paragraph, and tells Swift'` |
| 159 | The highlight after `showAIResult` and the caret after Accept are computed from the inserted range, not the original selection | ✅ `test-ai-output-validity.js` `'the highlighted result is exactly the inserted text, and accepting puts the caret after it'` |
| 160 | Offline, Local Drafts showed the network load's "Couldn't load…" error in the sidebar, the empty state and the detail placeholder, though drafts are local. `AppState.sectionListError` hides `listError` on Local Drafts | 👁 §7.2 — no test covers `sectionListError` |
| 161 | The update banner offered and opened whatever `html_url` the releases API returned. It must now be `https` on `github.com` | 👁 §7.21 — the URL check has no unit test |

---

## What's not yet automated

The automatable Swift and JS layers are covered. The remaining gaps require a live WordPress site or SwiftUI UI test infrastructure and cannot be run headlessly:

- **onDisappear flush (§7.9):** The `onDisappear` closure fires in the SwiftUI view lifecycle, which can't be triggered from Swift Testing. Manual steps cover local-draft-to-Media and remote-post-to-Media scenarios.
- **Preview URL on plain-permalink sites (§7.8):** `previewURL` logic is fully unit-tested; the manual step verifies the resulting URL actually loads in the browser on a real site.
- **Insert-image picker file filter (§7.4):** `NSOpenPanel.allowedContentTypes` is an AppKit call; the panel itself can only be verified by running the app.
- **`GallerySheet`'s expandable alt/caption rows (§7.4):** the chevron expand/collapse, `moveDisabled` while expanded, the grip-hover collapse, and expanded state clearing on deselect are all SwiftUI `List` row behavior with no test harness. The values those fields produce *are* covered end-to-end on the JS side; only the interaction is manual.
- **Dropped-image progress pill and drop-batch serialization (§7.4):** `UploadStatusPill`, the shared bottom slot it occupies with the toast, and the `dropTask` chaining that keeps overlapping Finder drops from interleaving are all SwiftUI view state with no test harness. The *messages* the pill and toast display are unit-tested; only the timing and layering are manual.
- **Container row hit geometry (JS container tests):** jsdom reports a zeroed `getBoundingClientRect` for every element and gives Ranges no client rects, so how big a toggle's hit box renders and which character a pointer lands on can only be checked in a real browser. The CSS rules and the `mousedown` behavior behind those affordances *are* asserted.
- **The save paths' block-risk guard (§7.22):** `alarmBlocksSaving` and the four call sites that read it (`save(status:)`, `performAutosave`, `flushToDB`, `saveLocalOnly`) are SwiftUI view state with no test harness. The banner stages it reads, and `nextAlarm`'s clear/preserve/raise decision, *are* unit-tested; only the wiring into the save paths is manual.
- **Menu commands and the Help links (§7.27):** `CommandGroup` items in `QuillApp.swift` only exist once AppKit builds the menu bar, and the Help/About links leave the app entirely. Nothing here has a harness — the destinations must be clicked.
- **UI flows, SwiftUI/AppKit rendering, WKWebView bridge interactions, conflict detection, autosave restoration, AI result panel visual correctness:** Documented in §7, run before each release.

## Test suite gotchas


- **Each network test suite needs its own `URLProtocol` subclass** — `@Suite(.serialized)` only serializes within a suite; two serialized suites sharing `MockURLProtocol.requestHandler` (a global static) race against each other. Solution: give each suite its own subclass with its own `static var requestHandler` (e.g. `AnthropicMockURLProtocol` in `Tests/QuillTests/Support/`).
- **`httpBody` is always nil in `URLProtocol.startLoading()`** — URLSession moves the body to `httpBodyStream`. To inspect request bodies in mock tests, reconstruct from the stream. See `AnthropicMockURLProtocol.startLoading()` for the pattern.
- **DOM-wrap + string-strip round-trips can leave orphaned whitespace text nodes** — when a transform inserts a separator (e.g. `\n\n`) *between* two wrapped elements rather than adjacent to either one's own delimiter, a later strip-by-regex pass can't fully remove it (each strip regex only consumes whitespace touching its own comment tag), so the separator survives as a stray whitespace-only text node between the bare elements. Re-wrapping then stacks a new separator on top instead of replacing it, and the output grows on every save. Fix at the DOM level, scoped to the exact container being re-wrapped: strip whitespace-only child text nodes immediately before re-inserting separators, rather than adding more regex. Discovered in the gallery block-comment wrapper (`toWordPressHTML`'s `figure.wp-block-gallery` handling); relevant to any future block that wraps a repeated list of sibling elements with per-item comments.
- **Greedy `[^\n]*` in comment-stripping regexes can span multiple comments and delete the content between them** — `toWordPressHTML`'s upfront strip of pre-existing `wp:embed`/`wp:gallery`/`wp:image` comments used `<!-- wp:X [^\n]*-->` to match one comment's attrs. This assumes each comment is followed by a `\n` before the next one starts, which holds for freshly-wrapped content (the wrap step itself always inserts a `\n`) but not for a *loaded* gallery's `sourceHTML` (`galleryBlock`'s verbatim-re-render attr, captured from the original WordPress figure) — DOM whitespace-node collapsing during Tiptap's parse can leave zero characters between one image figure's closing `<!-- /wp:image -->` and the next image's opening `<!-- wp:image -->`. With no `\n` boundary, `[^\n]*` greedily matched past the *first* comment's own `-->` all the way to the *last* `-->` in the string, deleting every image figure in between — this is what caused a gallery's images to silently disappear after any visual edit (the `toWordPressHTML(editor.getHTML())` call on every debounced save re-triggers the strip). Fixed by making the attrs group non-greedy (`[\s\S]*?-->`), which always stops at the nearest `-->` regardless of surrounding whitespace. Use `[\s\S]*?`, not `.*?` — JS `.` excludes all line-terminator characters (`\n`, `\r`, U+2028, U+2029), not just `\n`, so a `.*?` group fails to match at all (leaving the comment unstripped) if a stray `\r` ever lands inside a comment's attrs before its own `-->`. Regression tests: `Scripts/test-editor.js`'s `'stripping pre-existing wp:image comments does not consume the images between them'` and `'stripping a pre-existing wp:gallery comment works even with a CR before its closing -->'`.
- **Edit tool corrupts quotes in JS test files** — when the Edit tool's `old_string` spans a region containing curly Unicode quotes (U+2018/U+2019), it can replace straight ASCII `'` delimiters with curly ones in the output, producing `SyntaxError: Invalid or unexpected token` in Node.js. If you see that error after editing `Scripts/test-editor.js`, the fix is a targeted Python byte-level replacement — do NOT use the Edit tool again to fix it, as it will re-introduce the same corruption. The existing unicode test on line 277 intentionally contains U+2019 as *content* (not delimiters) and must be left alone.
- **`test-editor-keyboard.js`: the first `setContent(figureHTML)` right after an `extendMarkRange('link')`-over-an-existing-mark call silently no-ops** — confirmed via `git stash` to reproduce on unmodified `editor.html`, so it's a pre-existing jsdom/Tiptap interaction, not caused by any one feature's code: `editor.chain().extendMarkRange('link').setLink(...).run()` over an *existing* link mark poisons exactly the next `setContent(...)` call, which produces an empty `<p></p>` instead of parsing the given HTML (only that one call — the next one parses fine). Reproduces with any figure/image HTML, not just linked images; never root-caused past "ProseMirror's stored marks/selection mapping through the full-doc `replaceWith` is the suspect." If a new `describe()` block's first test calls `setContent` with block-level HTML and lands right after a test exercising `extendMarkRange`, add a throwaway `editor.commands.setContent('<p></p>', false)` in a `before()` hook to absorb the one-shot quirk (see the `'image link-to-full-size'` describe block for the pattern).

