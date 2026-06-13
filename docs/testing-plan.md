# Quill — Test Suite Reference

_Last updated: 2026-06-11 — 233 Swift tests + 93 JS editor tests, all passing._

This document is the authoritative reference for Quill's automated test suite and manual testing checklists. It covers how to run every test, what each test covers, and which manual checks to run before a release.

---

## Running the tests

### Full suite (recommended after every code change)

```bash
./test.sh
```

`test.sh` runs both test layers in sequence and prints a pass/fail summary:

1. **Swift tests** — `swift test` (all 233 tests across 18 suites)
2. **JS editor tests** — `node --test Scripts/test-editor.js` (93 tests via Node's built-in runner + jsdom)

If either layer fails, `test.sh` exits non-zero and reports which suite failed.

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

Requires `node` and the `jsdom` package (already installed in the project root via `npm install`).

---

## Swift test suite (233 tests, 18 suites)

Framework: `swift-testing`. Target: `Tests/QuillTests/`. Support files: `Tests/QuillTests/Support/`.

### Suite summary

| # | Suite | File | Tests | What it covers |
|---|---|---|---|---|
| 1 | `WPPostDecodingTests` | `WPPostDecodingTests.swift` | 13 | `WPPost` JSON decoding, optional-field defaults, `editorHTML` fallback, empty content from `_fields` list fetch |
| 2 | `WPMediaDecodingTests` | `WPMediaDecodingTests.swift` | 11 | `WPMedia`/`MediaDetails`/`MediaSize` float-dimensions gotcha, `thumbnailURL` fallback |
| 3 | `PostPayloadTests` | `PostPayloadTests.swift` | 11 | `PostPayload` encoding, scheduling key names, nil omission |
| 4 | `CredentialsTests` | `CredentialsTests.swift` | 4 | `Credentials.basicAuthHeader` base64 encoding |
| 5 | `WordPressClientTests` | `WordPressClientTests.swift` | 51 | URL construction, `_fields` filter, HTTP error mapping, `searchLinks`, auth headers, Content-Disposition escaping, media fetch/upload/delete/alt-text, streaming uploads |
| 6 | `JSONFileStoreTests` | `JSONFileStoreTests.swift` | 8 | Round-trip, chmod 600, atomic write, nil-on-absent |
| 7 | `CredentialsStoreTests` | `CredentialsStoreTests.swift` | 10 | Credentials persistence, `AppSupportDirectory`, `AISettingsStore` |
| 8 | `DraftStoreTests` | `DraftStoreTests.swift` | 13 | Local draft CRUD, ordering, unicode, non-existent ID safety |
| 9 | `AutosaveStoreTests` | `AutosaveStoreTests.swift` | 8 | Autosave CRUD, one-per-post, `serverModified`, `savedAt` ordering |
| 10 | `TaxonomyCacheTests` | `TaxonomyCacheTests.swift` | 12 | Category/tag cache, TTL boundary, replace semantics, collision guard |
| 11 | `AppDatabaseTests` | `AppDatabaseTests.swift` | 2 | Migration idempotency, old-schema `type` column backfill |
| 12 | `AIPromptBuilderTests` | `AIPromptBuilderTests.swift` | 24 | `parseGenerateResponse` edge cases, system prompt, all prompt builders |
| 13 | `AnthropicClientTests` | `AnthropicClientTests.swift` | 17 | Request headers, web search, multi-block joining, error handling |
| 14 | `PostItemTests` | `AppStateTests.swift` | 10 | `PostItem.id`, `.title`, `.statusBadge` computed properties |
| 15 | `SidebarSectionTests` | `AppStateTests.swift` | 8 | `SidebarSection.icon` and `.shortTitle` for all cases |
| 16 | `AppStateFilteredItemsTests` | `AppStateTests.swift` | 10 | `AppState.filteredItems` per section, search filtering |
| 17 | `EditorCoordinatorTests` | `EditorCoordinatorTests.swift` | 7 | `isAllowedExternalURL` URL scheme allowlist |
| 18 | `PostEditorHelpersTests` | `PostEditorHelpersTests.swift` | 14 | `previewURL` query/fragment handling; status helpers (`publishButtonTitle`, `toastMessage`, `statusDidChange` for future/private/pending); `PostStats` reading time |

---

### 1. Model decoding — `WPPostDecodingTests` (13 tests)

File: `Tests/QuillTests/WPPostDecodingTests.swift`

Guards the `WPPost` decoding path, which contains `decodeIfPresent` defaults that have caused production bugs.

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
| `missingContentAndExcerptDefaultToEmpty` | No `content`/`excerpt` keys (list fetch with `_fields`) → both default to empty `RenderedString` without throwing |

---

### 2. Model decoding — `WPMediaDecodingTests` (11 tests)

File: `Tests/QuillTests/WPMediaDecodingTests.swift`

Guards the float-dimensions gotcha: WordPress returns `width`/`height` as JSON floats (`2560.0`) which Swift's `Int` decoder rejects without the try-Int-then-Double fallback. Also covers `altText` and `thumbnailURL`.

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

---

### 3. Model encoding — `PostPayloadTests` (11 tests)

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

### 5. Networking — `WordPressClientTests` (51 tests)

File: `Tests/QuillTests/WordPressClientTests.swift`
Support: `Tests/QuillTests/Support/MockURLProtocol.swift`

`@Suite(.serialized)` — runs sequentially because `MockURLProtocol.requestHandler` is a shared static. Uses `URLSessionConfiguration.ephemeral` with `MockURLProtocol` as the protocol class.

#### URL & request construction (14 tests)

| Test | What it checks |
|---|---|
| `fetchPostsDecodesList` | `fetchPosts` decodes a list of posts |
| `fetchPostsIncludesRequiredQueryParams` | `per_page`, `page`, `context=edit`, `status=…` all present |
| `fetchPagesHitsPagesEndpoint` | `/wp-json/wp/v2/pages`, not `/posts` |
| `createPostUsesPostMethodWithJsonContentType` | `POST /posts`, `Content-Type: application/json` |
| `updatePostUsesPutMethodOnPostsId` | `PUT /posts/{id}` |
| `createPageUsesPostMethodOnPagesEndpoint` | `POST /pages` |
| `updatePageUsesPutMethodOnPagesId` | `PUT /pages/{id}` |
| `authorizationHeaderIncludedInRequests` | `Authorization: Basic …` on all requests |
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

#### Error mapping (7 tests)

| Test | What it checks |
|---|---|
| `fetchPostsThrowsOnHTTPError` | Non-2xx → `APIError.httpError` |
| `trashPostThrowsOnHTTPError` | DELETE non-2xx → error |
| `httpErrorPreservesStatusCode` | Status code in `APIError.httpError(statusCode:body:)` |
| `httpErrorPreservesBodyString` | Body string preserved in error |
| `nonUtf8ResponseBodyBecomesEmptyString` | Non-UTF8 body → `body = ""`, no crash |
| `successWithMalformedJsonThrowsDecodingError` | 200 + garbage JSON → `APIError.decodingError` (not `httpError`) |
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

#### `searchLinks` (7 tests)

| Test | What it checks |
|---|---|
| `searchLinksReturnsMergedResults` | All three sub-requests succeed → merged list |
| `searchLinksIgnoresSubrequestFailures` | Media/term failure → others still returned |
| `searchLinksAllSubrequestsFailReturnsEmptyArray` | All fail → `[]`, no throw |
| `searchLinksPostsFailWhileTermsSucceed` | Posts sub-request fails → terms/media still returned |
| `searchLinksPageSubtypeMapsToPageType` | `subtype == "page"` → `.page` result type |
| `searchLinksTagSubtypeMapsToTagType` | `subtype == "tag"` → `.tag` result type |
| `searchLinksUnknownTermSubtypeFallsToCategory` | Unknown term subtype → `.category` |

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

### 8. Storage — `DraftStoreTests` (13 tests)

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

---

### 9. Storage — `AutosaveStoreTests` (8 tests)

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

### 11. Storage — `AppDatabaseTests` (2 tests)

File: `Tests/QuillTests/AppDatabaseTests.swift`

| Test | What it checks |
|---|---|
| `migrationIsIdempotent` | Running `migrate()` twice on same schema doesn't throw |
| `typeColumnMigratedFromOldSchema` | Old DB (without `type` column) → migrate adds it; existing rows default to `"post"` |

---

### 12. AI — `AIPromptBuilderTests` (24 tests)

File: `Tests/QuillTests/AIPromptBuilderTests.swift`

Pure function tests — no network, no async. `parseGenerateResponse` has been patched twice for real production bugs; these tests pin every edge case.

#### `parseGenerateResponse` (11 tests)

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

#### `systemPrompt` (3 tests)

| Test | What it checks |
|---|---|
| `systemPromptWithoutStyleGuide` | `nil` guide → no style block |
| `systemPromptWithEmptyStyleGuideExcludesStyleBlock` | Empty string guide → same as nil |
| `systemPromptWithStyleGuideIncludesIt` | Non-empty guide appended to prompt |

#### `generatePostPrompt` & `operationPrompt` (6 tests)

| Test | What it checks |
|---|---|
| `generatePostPromptNamesHTMLElements` | Prompt contains `<h2>`, `<h3>`, `<p>`, `<ul>`, `<li>` (prevents headings-only-p regression) |
| `generatePostPromptIncludesUserPrompt` | User's prompt string embedded |
| `operationPromptIncludesSelectedHTML` | Selected HTML embedded after "Content to transform:" |
| `makeLongerInstructionPresent` | "longer" in `makeLonger` operation prompt |
| `makeShorterInstructionPresent` | "shorter" in `makeShorter` operation prompt |
| `convertToTableMentionsTableTags` | Table-related tags in `convertToTable` prompt |
| `convertToListMentionsListTags` | List-related tags in `convertToList` prompt |

#### `styleGuideGenerationPrompt` (3 tests)

| Test | What it checks |
|---|---|
| `styleGuidePromptNumbersSamples` | `--- Sample 1 ---` / `--- Sample 2 ---` numbering |
| `styleGuidePromptWithEmptySamples` | 0 samples → no crash, empty content |
| `styleGuidePromptWordLimit` | 150-word limit mentioned in prompt |

---

### 13. AI — `AnthropicClientTests` (17 tests)

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

#### Response handling (7 tests)

| Test | What it checks |
|---|---|
| `singleTextBlockReturnsText` | Single `type:"text"` block → its text |
| `multipleTextBlocksAreJoinedInOrder` | Multiple text blocks → joined in order (web-search fragmentation gotcha) |
| `nonTextBlocksExcludedFromJoin` | `server_tool_use` and `web_search_tool_result` blocks excluded |
| `allNonTextBlocksThrowsNoTextContent` | All non-text blocks → `AnthropicError.noTextContent` |
| `truncatedTrueWhenStopReasonIsMaxTokens` | `stop_reason: "max_tokens"` → `truncated: true` |
| `truncatedFalseWhenStopReasonIsEndTurn` | `stop_reason: "end_turn"` → `truncated: false` |
| `nonOkStatusThrowsHttpError` | Non-200 → `AnthropicError.httpError(code, body)` |

#### Error handling (3 tests)

| Test | What it checks |
|---|---|
| `httpErrorPreservesBodyString` | Error body string preserved |
| `malformedJsonThrows` | Garbage JSON → decoding throws |
| `networkFailureThrows` | `URLError` from mock → error surfaced |

---

### 14. View-model — `PostItemTests` (10 tests)

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

### 16. View-model — `AppStateFilteredItemsTests` (10 tests)

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

### 17. Security — `EditorCoordinatorTests` (7 tests)

File: `Tests/QuillTests/EditorCoordinatorTests.swift`

Guards the `isAllowedExternalURL` scheme allowlist. Linked to the S2 security finding: clicked links in the editor must not be handed to `NSWorkspace.shared.open` with arbitrary schemes.

| Test | What it checks |
|---|---|
| `httpURLIsAllowed` | `http://` → allowed |
| `httpsURLIsAllowed` | `https://` → allowed |
| `mailtoURLIsAllowed` | `mailto:` → allowed |
| `fileURLIsNotAllowed` | `file:///` → blocked |
| `javascriptURLIsNotAllowed` | `javascript:` → blocked |
| `ftpURLIsNotAllowed` | `ftp://` → blocked |
| `schemeCheckIsCaseInsensitive` | `HTTPS://` → allowed (lowercased before compare) |

---

### 18. Editor helpers — `PostEditorHelpersTests` (14 tests)

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

---

## JS editor tests (93 tests)

File: `Scripts/test-editor.js`
Transforms file: `Sources/QuillKit/Resources/editor-transforms.js`

Tests run under Node's built-in test runner with jsdom for DOM support. They test `toWordPressHTML`, `extractAlignment`, `formatHTML`, `countStats`, `findMatches`, `detectEmbedProvider`, and `embedClassFor` from `editor-transforms.js`.

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

### `toWordPressHTML` — lists (3 tests)

| Test | What it checks |
|---|---|
| `ul gains wp-block-list` | `<ul>` → `wp-block-list` |
| `ol gains wp-block-list` | `<ol>` → `wp-block-list` |
| `task list does NOT gain wp-block-list` | `data-type="taskList"` → no class added |

### `toWordPressHTML` — list item `<p>` unwrapping (3 tests)

| Test | What it checks |
|---|---|
| `single-child <p> inside <li> is unwrapped` | `<li><p>text</p></li>` → `<li>text</li>` |
| `multi-child <li> is left untouched` | Two `<p>` in one `<li>` → unchanged |
| `task item div>p is unwrapped` | Task item inner `<p>` stripped to `<div>text</div>` |

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

### `toWordPressHTML` — tables (5 tests)

| Test | What it checks |
|---|---|
| `table is wrapped in figure.wp-block-table` | `<table>` → `<figure class="wp-block-table">` |
| `all-th first row is promoted from tbody to thead` | All-`<th>` row moves to `<thead>` |
| `mixed th/td first row is NOT promoted to thead` | Mixed `<th>`/`<td>` → no promotion |
| `table already having thead is not modified` | Pre-existing `<thead>` → untouched |
| `table already inside wp-block-table is not double-wrapped` | Idempotency: one `wp-block-table` after two passes |

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

### `formatHTML` — nested block elements (3 tests)

| Test | What it checks |
|---|---|
| `list items are indented inside ul` | `<li>` indented one level inside `<ul>` |
| `table cells are indented under their row and section` | `<td>` indented inside `<tr>` inside `<tbody>` |
| `blockquote with p and cite each on their own indented lines` | `<p>` and `<cite>` inside `<blockquote>` each on own indented line |

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

### `detectEmbedProvider` (5 tests)

| Test | What it checks |
|---|---|
| `youtube.com URL detected as youtube` | `https://www.youtube.com/watch?v=…` → `"youtube"` |
| `youtu.be short URL detected as youtube` | `https://youtu.be/…` → `"youtube"` |
| `vimeo.com URL detected as vimeo` | `https://vimeo.com/…` → `"vimeo"` |
| `x.com and twitter.com detected as twitter` | Both `x.com` and `twitter.com` → `"twitter"` |
| `unknown host returns null` | `https://example.com/…` → `null` |
| `invalid URL returns null` | `"not a url"` → `null` |

### `embedClassFor` (3 tests)

| Test | What it checks |
|---|---|
| `youtube produces full class string` | `embedClassFor("youtube", "video")` → `"wp-block-embed is-type-video is-provider-youtube wp-block-embed-youtube"` |
| `twitter rich type` | `embedClassFor("twitter", "rich")` → includes `is-type-rich is-provider-twitter` |
| `unknown provider produces bare wp-block-embed` | `embedClassFor(null, null)` → `"wp-block-embed"` |

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
| `footnote markers numbered in document order` | First `<sup data-fn>` gets `[1]`, second gets `[2]`, etc. |
| `footnote renumbering is idempotent` | Running `toWordPressHTML` twice does not change numbers |
| `sup without data-fn is not renumbered` | Plain `<sup>` not treated as footnote marker |
| `footnotes list does not get wp-block-list` | `<ol class="wp-block-footnotes">` → no `wp-block-list` added |
| `ordinary ol still gets wp-block-list` | Regular `<ol>` without `wp-block-footnotes` still receives `wp-block-list` |

### `toWordPressHTML` — footnote backrefs (3 tests)

| Test | What it checks |
|---|---|
| `marker sup gains id="ref-fn-UUID"` | Each `<sup data-fn="UUID">` gets `id="ref-fn-UUID"` added so backref anchors can target it |
| `footnote list item gains backref link` | Each `<li>` in `<ol class="wp-block-footnotes">` gets `<a href="#ref-fn-…" class="footnote-backref">↩</a>` appended |
| `backref is idempotent — not added twice on double transform` | Running `toWordPressHTML` twice does not add a second backref link |

---

## Manual / functional test checklists

These cover SwiftUI/AppKit behavior, WKWebView interaction, and end-to-end flows that aren't economically unit-testable. Run against a **real WordPress test site** (or a local `wp-env`/Docker WordPress) using an Application Password. Build with `./build.sh` and `open Quill.app` before each pass.

> Recommendation: keep a disposable WordPress instance so destructive tests (delete, trash, publish) don't pollute a real site.

### 7.1 Authentication & onboarding

- [ ] First launch with no credentials → preferences/login prompt shown.
- [ ] Valid site URL + username + app password → connects, lists load.
- [ ] **Edge:** site URL without scheme (`example.com`) → app normalizes it or shows a clear error (no silent failure or crash).
- [ ] **Edge:** site URL with trailing slash, with subdirectory install (`example.com/blog`), with non-standard port.
- [ ] **Edge:** wrong password → `401` surfaced as a readable error, not a silent failure.
- [ ] **Edge:** site that isn't WordPress / REST API disabled → clear error.
- [ ] App password with spaces pasted verbatim → auth succeeds (ties to §4).
- [ ] No keychain prompt appears during normal network use (ephemeral-session gotcha).
- [ ] Credentials persist across relaunch; changing the site URL updates the lists and (per gotcha) clears AI sample post IDs.

### 7.2 Sidebar, lists, navigation

- [ ] Posts / Pages / Local Drafts / Media sections each load and render.
- [ ] Selection highlight uses the custom (non-blue) style — confirms the `ScrollView+LazyVStack` (not `List`) gotcha holds.
- [ ] Search filters the current section case-insensitively; clearing restores.
- [ ] **Empty states:** empty Posts, empty Pages, empty Drafts, empty Media each show the right placeholder; editor empty state says "post"/"page"/"draft" per active section.
- [ ] Switching to Media hides the post list/search/toolbar and shows the thumbnail grid (the `else` branch gotcha).
- [ ] Pagination in Posts and Media loads more on scroll; `hasMore` stops at the end.
- [ ] No `NavigationSplitView`/`HSplitView` chrome (no drag cursor on the divider) — visual confirm of the layout gotcha.

### 7.3 Editor — content & Gutenberg round-trip

- [ ] Load an existing remote post → content renders identically to WordPress.
- [ ] **Post loading state:** clicking a post shows the editor briefly with "Start writing..." while the individual fetch completes, then content renders — this is expected from the `_fields` list-fetch optimization. Confirm content is correct after load, not truncated.
- [ ] Type formatting: bold, italic, strike, inline code, links, headings (h1–h6), bullet/ordered/task lists, blockquote, code block, table.
- [ ] Save → fetch `content.raw` via REST (`?context=edit`) → matches the Gutenberg expected output table in `CLAUDE.md` (heading classes, list classes, figure-wrapped tables/images, thead promotion).
- [ ] **Round-trip stability:** load → save without editing → diff is empty (no drift). Then load again → still identical.
- [ ] Multi-paragraph list items survive the save unchanged (don't get collapsed).
- [ ] Task list checkboxes round-trip.
- [ ] **Blockquote attribution (`<cite>`):**
  - [ ] Toggling blockquote **on** auto-appends an empty cite line (subdued, right-aligned).
  - [ ] Typing in the cite line then saving → `<cite>` persists inside the blockquote and renders as a `<cite>` on WordPress.
  - [ ] Leaving the cite **blank** → the empty `<cite>` is **not** saved (no empty cite litters the published HTML).
  - [ ] **Enter** inside the cite exits the blockquote into a new paragraph after it (doesn't add a newline inside the cite).
  - [ ] **Backspace** in an empty cite deletes the cite node (doesn't delete the whole quote).
  - [ ] Toggling blockquote **off** removes the quote and its cite cleanly.
- [ ] Curly quotes / emoji / non-Latin scripts survive save→reload byte-exact.
- [ ] Very long post (10k+ words) — editor stays responsive; save succeeds.
- [ ] Paste from Word/Google Docs/Safari → reasonable HTML, no script injection.

### 7.4 Editor — images

- [ ] Insert image via media picker at caret → appears at correct position.
- [ ] **Hit-testing:** clicking a thumbnail in the picker grid selects the intended item.
- [ ] Drag image file from Finder onto editor → uploads, inserts, toast shown.
- [ ] **Edge:** drag a non-image file → ignored (the `isFileURL`/mime guard).
- [ ] **Edge:** drag multiple images at once → all upload and insert.
- [ ] **Edge:** upload failure (offline) → error surfaced, editor not corrupted.
- [ ] **Large file upload:** drag a file ≥ 10 MB onto the editor → UI stays responsive during upload (editor not frozen); same check via the Media tab upload button. Regression guard for H4 streaming-upload fix.
- [ ] Resize handles appear on select; drag resizes; aspect ratio respected.
- [ ] **Resize handles align to the image, not the caption** — with a caption present, the bottom handles should sit at the image's bottom edge, not at the bottom of the caption. Confirm all four handles hug the image frame.
- [ ] Named WordPress sizes (thumbnail/medium/large/full) offered when the image has a `mediaId` and the media item is loaded; hidden otherwise (`setMediaSizes(id, null)` path).
- [ ] **Reset button** — click Reset on an image that has WordPress media sizes loaded → src switches to the full-size URL, width/height restore to the original full dimensions. On an image with no media sizes, Reset clears the explicit constraints without changing src.
- [ ] Image alignment left/center/right → wraps text correctly and saves as `figure.wp-block-image alignXXX`.
- [ ] Image toolbar repositions on scroll and hides on deselect (the `_scrollHandler` cleanup + 80ms deselect delay gotchas).
- [ ] Clicking a toolbar input doesn't dismiss the toolbar (80ms delay).
- [ ] Mime detection: insert `.jpg/.png/.gif/.webp/.heic/.tiff` → correct content type sent.
- [ ] **Insert-image picker is image-only:** open the editor image picker (insert image button in toolbar) → file dialog only shows/accepts image files; PDFs and movies are greyed out or absent.
- [ ] **Media tab still accepts PDFs and movies:** open the Media tab, use the upload button there → file dialog accepts images, PDFs, and movies.

### 7.5 Editor — links

- [ ] Link button opens the popover anchored to the **selection rect** (not the toolbar button) when text is selected; anchored to the button when nothing selected.
- [ ] Typing a query searches posts/pages/categories/tags/media; results render (the `ObservableObject` re-render gotcha).
- [ ] Popover **grows** as results appear without clipping (the `.preferredContentSize` sizing gotcha).
- [ ] Selecting a result inserts the link; manual URL entry works.
- [ ] **Edge:** no results → empty state, no crash.
- [ ] **Edge:** search while offline → handled gracefully.
- [ ] **Link click scheme check:** insert `http://` and `https://` links via the link picker → clicking them opens the system browser. Insert a `mailto:` link → clicking opens Mail. Insert a `file:///` or `javascript:alert(1)` URL via code view → clicking does **nothing** (S2 scheme-allowlist guard).

### 7.6 Editor — code view

- [ ] `</>` button appears in the toolbar's utility group (left of the image "Add" button).
- [ ] Clicking `</>` switches to the code textarea; all other toolbar buttons are disabled while in code view; the `</>` button shows the active state.
- [ ] HTML in the textarea is pretty-printed: block elements on their own lines, inline elements (`<strong>`, `<a>`, etc.) stay on the same line as their parent, `<li>` items indented inside `<ul>`/`<ol>`, table rows/cells nested, `<pre>` content left verbatim. Top-level blocks separated by a blank line.
- [ ] Clicking `</>` again switches back to visual mode; all toolbar buttons re-enable; edited HTML round-trips correctly into Tiptap.
- [ ] **Edit in code view, switch back:** make a change in the textarea (e.g. add a word), switch to visual — the edit is reflected in the editor.
- [ ] **Save from code view:** with code view active, use ⌘S — the saved content matches what was in the textarea (not stale Tiptap state).
- [ ] **Save without exiting code view:** make a change in the code view textarea, do NOT click `</>` to exit, then ⌘S — the edit is pushed to WordPress (not the pre-edit content).
- [ ] **Block comments preserved:** open a block-based page/post that has blocks Quill doesn't natively support (e.g. a Gallery or Columns block). Enter code view — WordPress block comments (`<!-- wp:gallery -->`, etc.) should be visible in the textarea.
- [ ] **Block comments survive visual edits:** open a block-based post, make a visual edit (e.g. fix a typo in a paragraph), then enter code view — block comments for unsupported blocks are still present in the textarea.
- [ ] **Load new post while in code view:** select a different post — code view exits automatically and the new post loads in visual mode.
- [ ] **Dark mode:** code textarea background and text color match the editor background (no light flash or mis-colored panel).
- [ ] **Special characters round-trip:** write a paragraph containing `5 < 10`, `a & b`, and a `"quoted"` word. Enter code view — the HTML should show `&lt;`, `&amp;`, `&quot;` correctly. Switch back to visual — the original text is intact. Save and reload — still intact. (C1 entity-escaping regression guard.)

### 7.7 Save / publish / draft / schedule

- [ ] **Local draft, Save Draft** → persists locally only, **no** network call (verify via proxy/network log); toast shows "Saved locally".
- [ ] **Local draft, Publish** → creates remote post, **local copy disappears immediately** from the Drafts list, selection moves to the new remote item, section switches to Posts/Pages.
- [ ] Page draft publishes to `/pages`, post draft to `/posts`.
- [ ] **Remote post, ⌘S** → updates WordPress (status `draft` stays draft).
- [ ] **Remote post, ⌘⇧P / Publish** → publishes; button label reflects state (`Publish` / `Update` / `Publish Draft` / `Schedule`).
- [ ] **Scheduling:** set a future date → status `future`, post scheduled; verify on the server the scheduled time matches (UTC `date_gmt`, **not** site-local `date` — the scheduling gotcha). Test a timezone-offset site.
- [ ] Reopening a scheduled post shows the correct future date in the panel (the `parseWPDate` round-trip, incl. the no-timezone-suffix fallback).
- [ ] Inline new category/tag names → created on save, IDs attached, appear in `appState.categories/tags` and the panel (the deferred-creation gotcha).
- [ ] **Edge:** taxonomy creation fails → save aborts with an error, content not lost.
- [ ] Slug: blank slug on a new item stays blank (doesn't inherit previous item's slug); editing slug then save sends it; blank slug on update **omits** `slug` so the server value is preserved.
- [ ] Featured image set/clear; `featured_media: 0` clears it.
- [ ] Comment status open/closed round-trips.
- [ ] Page parent picker excludes the page itself; saving sets `parent`.

### 7.8 Conflict detection

- [ ] Open a remote post in Quill. Edit it on the server (or via another client) so `modified` changes. Save in Quill → **Conflict Detected** alert.
  - [ ] "Keep Local" → force-saves, overwrites server.
  - [ ] "Use Server" → reloads server content, discards local edits.
  - [ ] "Cancel" → keeps editing, no data lost.
- [ ] **False-conflict guard:** open a post, immediately save without server changes → **no** conflict alert.
- [ ] **Preview-induced baseline refresh:** preview a draft post, then save → **no** spurious conflict.
- [ ] **Preview URL on plain-permalink site:** on a site using `Settings → Permalinks → Plain` (URLs like `/?p=123`), click Preview → browser opens the correct preview URL with `&preview=true` (not `?preview=true` appended after the existing `?`).
- [ ] **Preview URL on pretty-permalink site:** same test with a pretty permalink (e.g. `https://example.com/my-post/`) → URL is `…/?preview=true`.

### 7.9 Autosave / unsaved-changes / navigation

- [ ] Edit a remote post, wait 30s → autosave stash written; navigate away and back → "Unsaved changes restored" toast and stashed content shown.
- [ ] **No spurious restore toast** when opening a server post that has no real local divergence.
- [ ] Navigate away from a dirty local draft → flushed to SQLite; reopening shows the latest content.
- [ ] **onDisappear flush — local draft to Media:** edit a local draft, immediately click the Media section (before the 30s autosave fires) → switch back to Drafts, reopen the draft → the edit is present.
- [ ] **onDisappear flush — remote post to Media:** edit a remote post, immediately click the Media section → reopen the post → "Unsaved changes restored" toast and the edit is shown.
- [ ] **onDisappear flush — no regression on item switch:** switch directly between two posts without going through Media → existing flush behavior still works, no duplicate autosave written.
- [ ] Navigate away from a dirty remote post → stashed; not pushed to WordPress.
- [ ] After a successful publish/update, the autosave stash for that post is **deleted** (so the next open doesn't falsely restore).
- [ ] Dirty indicator (amber dot) shows for local drafts when `isDirty`, hidden for remote.
- [ ] Rapid navigation between items → no autosave from item A lands on item B (the `expectedItemID` guard); no crash; cancelled load tasks don't throw.
- [ ] Quitting the app with unsaved local-draft edits → recovered on next launch.
- [ ] **Revert button:** open a remote post, make edits → **Revert** button appears in the header. Click it → "Revert to Server Version?" alert appears.
  - [ ] "Revert" → local autosave deleted, server content reloaded, dirty state cleared.
  - [ ] "Cancel" → editing continues, no data lost.
- [ ] Revert button is **hidden** for local drafts (only shown for remote posts).
- [ ] Revert button is **hidden** for a clean (unedited) remote post.

### 7.10 Delete / trash

- [ ] Trash a remote post → confirmation alert, then `force=false` (recoverable — appears in WordPress Trash, not gone).
- [ ] Trash a page → `/pages/{id}` trashed.
- [ ] Delete a local draft → removed from list and SQLite.
- [ ] Delete media → confirmation alert (permanent, `force=true`); after confirm it's gone from the grid and server.
- [ ] **Edge:** delete failure (permissions/offline) → `deleteError` alert; item stays.
- [ ] Cancel on any delete confirmation → nothing happens.

### 7.11 AI features (require an Anthropic API key configured)

- [ ] With no API key: ✦ toolbar button is **hidden** and the AI items are **absent** from the editor right-click menu (`aiEnabled == false`).
- [ ] Add a key in Settings → feature enables **without relaunch**.
- [ ] **Generate post:** ✦ on an empty editor opens the sheet directly; on a non-empty editor shows the "Replace Content?" alert first.
- [ ] Generate produces a title + structured HTML **with headings** (not just `<p>` — the prompt-structure gotcha).
- [ ] Generate with web search on → response reassembled correctly across fragmented blocks (the joining gotcha); citations don't break the TITLE/CONTENT parse.
- [ ] **Selection ops (right-click menu):** select text → right-click → Make Longer / Make Shorter / To Table / To List each appear (only when `aiEnabled && hasTextSelection`) and each works.
  - [ ] `hasTextSelection` updates correctly: the AI items appear only when there is a non-empty selection; collapse the selection → items gone on next right-click.
  - [ ] The AI menu items survive the AutoFill/Services re-filter (their selector strings are in `WebViewMenuFilter.allowed`).
- [ ] AI result inserts at **block boundaries** — no empty `<p>` fragments before/after, no blank paragraphs from inter-block whitespace. Verify the saved HTML has no stray empty paragraphs.
- [ ] Accept → content committed and `contentChanged` fires; Discard → original restored.
- [ ] **Accepted AI result is Gutenberg-transformed** — if the AI returns a table/list/heading, the saved HTML has `wp-block-*` classes and figure wrappers. Verify via `content.raw`.
- [ ] **Edge:** Claude error/timeout → original text restored, "couldn't complete" toast, editor not corrupted.
- [ ] The AI result bar (`AIResultPanel`) stays above Quill but **not** above other apps when you switch away (child-window gotcha); no rectangular shadow artifact (`hasShadow=false` gotcha); buttons visible in light mode (`.plain` style gotcha).
- [ ] Style guide: select sample posts in Settings → guide generated once; re-saving with unchanged samples makes **no** Claude call; changing the site URL clears samples and guide.
- [ ] **Panel survives sidebar re-renders:** trigger the AI result panel, then type in the sidebar search field — the panel stays visible and positioned correctly without disappearing or duplicating. (H1 regression guard: `@State` ensures one panel instance per view identity.)

### 7.12 Settings panel & preferences

- [ ] Post settings panel for **posts** shows categories, tags, slug, excerpt, discussion; for **pages** shows parent + slug + discussion only (no categories/tags/excerpt) — the `isPage` gotcha.
- [ ] Amber accent applied throughout settings.
- [ ] Preferences opens from both the menu and the in-app sheet; `PreferencesView` works in the separate `Settings` scene **without EnvironmentObject** — i.e. sample post picker is populated.

### 7.13 Window / appearance / chrome

- [ ] Light and dark mode: sidebar (`wpSidebarBg`), panels (`wpPanelBg`), title/breadcrumb bars render with correct tokens; **title/breadcrumb bars white in dark mode** (open TODO — verify current state).
- [ ] **Dark mode live toggle** — with the app open, toggle dark mode in System Settings → editor background, toolbar, and sidebar switch immediately without relaunch. (Tests the `viewDidChangeEffectiveAppearance` override in `DroppableWebView`.)
- [ ] **Surface components** — `SoftPanelBoundary` between sidebar/editor and editor/settings-panel renders as a subtle gradient boundary, not a hard `Divider()` line. `SoftHorizontalDivider` at the bottom of the sidebar tab strip and above the bottom toolbar. `PanelInteriorFade` fades the right edge of the sidebar scroll list and the left edge of the settings panel.
- [ ] Enter/exit full screen → title bar color stable (fixed — confirm).
- [ ] Title field + top border spacing correct (fixed — confirm).
- [ ] App icon/logo present in dock and about.
- [ ] Editor "Loading editor…" overlay shows then fades on `editorReady`; never sticks if the bundle loads.

### 7.14 Context menus (AppKit specifics)

- [ ] Right-click in the **editor (WKWebView)** → Cut/Copy/Paste present and correctly enabled/disabled; **no AutoFill/Services leakage** (the `willOpenMenu` + `NSMenuDelegate` re-filter gotcha).
- [ ] Right-click in the **title field** → only Cut/Copy/Paste; no AutoFill (the `RestrictedTextView` gotcha).
- [ ] Right-click a misspelled word → up to 8 spelling suggestions appear above Cut/Copy/Paste with a separator; clicking a suggestion replaces the word correctly.
- [ ] **Emoji adjacency:** right-click a misspelled word immediately next to an emoji (e.g. `"speling 🎉"`) → the suggestion replaces only the misspelled word without corrupting the emoji or surrounding text. (C3 `posAtDOM` regression guard.)

### 7.15 Spell check

- [ ] "ABC" toolbar button highlights misspellings via decorations; highlights clear on first edit.
- [ ] No `NSUndefinedKeyException` crash on macOS 26 (the `continuousSpellCheckingEnabled` KVC gotcha) — launch and run spell check on the current OS.

### 7.16 Stats panel

- [ ] Stats panel (settings panel footer or dedicated area) shows word count, character count, and reading time.
- [ ] Counts update live as the user types (debounced).
- [ ] Counts freeze correctly when code view is active and refresh when returning to visual mode.
- [ ] Reading time shows "1 min" for short posts; rounds up for longer ones.

### 7.17 Publish status helpers

- [ ] Publish button label is correct for each status: draft → "Publish", published → "Update", future → "Schedule", pending → "Submit for Review", private → "Publish Privately".
- [ ] Toast message after save reflects the correct status change.
- [ ] Setting a future date switches status to `future` and button to "Schedule".
- [ ] Setting visibility to Private switches status to `private` and button to "Publish Privately".

### 7.18 Find & replace

- [ ] Find & replace bar opens (⌘F or toolbar button) and closes (Escape or close button).
- [ ] Typing in the Find field highlights all matches in the editor with a yellow decoration.
- [ ] Match counter shows "1 of N" and updates as the query changes.
- [ ] Next/Previous buttons navigate between matches; wraps around at ends.
- [ ] Replace field + Replace button replaces the current match and advances to the next.
- [ ] Replace All button replaces every match in one operation.
- [ ] Case-sensitive toggle works: lowercase query matches differently with toggle on vs off.
- [ ] Find bar is hidden in code view; decorations do not appear in the textarea.

### 7.19 Embeds

- [ ] Insert an embed by pasting a YouTube/Vimeo/Twitter URL → displays as a static embed card in the editor with the provider name and URL visible.
- [ ] Save → fetch `content.raw` via REST → output is a valid Gutenberg `wp-block-embed` block with correct provider classes (`is-type-video is-provider-youtube wp-block-embed-youtube` etc.).
- [ ] Reload the post in Quill → embed card renders correctly (round-trip stable).
- [ ] View the post on the live WordPress site → embed renders as the expected oEmbed widget.
- [ ] Unknown URL (not a recognised provider) → saves as a generic `wp-block-embed` block without provider-specific classes.
- [ ] Embed figure is not misidentified as an image figure (no `wp-block-image` class, no resize handles).

### 7.20 Footnotes

- [ ] Insert Footnote via right-click context menu → a numbered superscript `[1]` appears at the cursor and a matching entry appears in the footnotes list at the bottom of the document.
- [ ] Add a second footnote → numbered `[2]`; numbers update in document order.
- [ ] Delete a footnote marker → its entry is removed from the footnotes list automatically (`FootnoteSync`).
- [ ] Type text in a footnote list entry → text is preserved on save.
- [ ] Click a footnote number in the list → cursor jumps to the corresponding marker in the body.
- [ ] Click the ↩ button at the end of a footnote list entry → cursor jumps to the corresponding marker in the body (`FootnoteItemNodeView` back-arrow).
- [ ] Save → fetch `content.raw` → footnote markers are `<sup id="ref-fn-…" data-fn="…" class="fn"><a href="#…">[N]</a></sup>` and each list item has `<a href="#ref-fn-…" class="footnote-backref">↩</a>` appended.
- [ ] Reload the post in Quill → footnotes render and are editable (round-trip stable); back-arrow button still present in each list item.
- [ ] View on the live WordPress site → footnote numbers are clickable links to the footnote list; back-links (`↩`) jump back to the correct inline marker.
- [ ] Footnote list `<ol>` does **not** get `wp-block-list` class (excluded by design).

---

## Non-functional & resilience

- **Offline / flaky network:** every network action degrades gracefully with a user-visible error, never a hang or crash.
- **Slow network:** saves show the saving state and disable buttons (`isSaving`); no double-submit on rapid clicks.
- **Large media library:** Media grid with 500+ items — scrolling stays smooth, pagination works, memory bounded.
- **File permissions:** `credentials.json` and `ai_settings.json` are chmod 600 (guarded by `JSONFileStoreTests.savedFileHasChmod600`).
- **Crash recovery:** force-quit mid-edit → local draft / autosave stash recovered on relaunch.
- **Performance:** `toWordPressHTML` runs on a 500ms debounce on every edit — on a large document it should not block typing.
- **Security:** pasted/loaded HTML with `<script>` or `onerror=` attributes is not executed; AI-returned HTML is inserted as content, not evaluated.
- **Thumbnail bandwidth:** media grid cells load small thumbnail images (a few KB each), not full-resolution originals — confirming `WPMedia.thumbnailURL` is used in `AsyncImage`. Verify with a network proxy on a grid of large images.
- **Taxonomy cache persistence:** on second app launch with unchanged site URL, a network proxy shows no `/categories` or `/tags` requests (served from 24-hour SQLite cache). Changing the site URL should trigger a fresh fetch.

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
| 36 | Stats freeze in code view; refresh on exit | ✅ `countStats` (8 JS tests) + 👁 §7.16 |
| 37 | Find & replace decorations don't re-fire `update` | ✅ `findMatches` (7 JS tests) + 👁 §7.18 |
| 38 | Embed figure passes through, not treated as image | ✅ JS embed tests + 👁 §7.19 |
| 39 | Footnote markers renumbered by `toWordPressHTML` | ✅ JS footnote tests + 👁 §7.20 |
| 40 | Footnotes list excluded from `wp-block-list` | ✅ JS `footnotes list does not get wp-block-list` |
| 41 | `FootnotesList`/`FootnoteItem`/`FootnoteMarker` parse priority | 👁 §7.20 (load existing post with footnotes) |
| 42 | `FootnoteSync` deletes list entry when marker removed | 👁 §7.20 |
| 43 | Footnote backref: `sup` gets `id="ref-fn-…"`, list item gets `<a class="footnote-backref">` | ✅ `toWordPressHTML — footnote backrefs` (3 JS tests) + 👁 §7.20 |

---

## What's not yet automated

The automatable Swift and JS layers are covered. The remaining gaps require a live WordPress site or SwiftUI UI test infrastructure and cannot be run headlessly:

- **onDisappear flush (§7.9):** The `onDisappear` closure fires in the SwiftUI view lifecycle, which can't be triggered from Swift Testing. Manual steps cover local-draft-to-Media and remote-post-to-Media scenarios.
- **Preview URL on plain-permalink sites (§7.8):** `previewURL` logic is fully unit-tested; the manual step verifies the resulting URL actually loads in the browser on a real site.
- **Insert-image picker file filter (§7.4):** `NSOpenPanel.allowedContentTypes` is an AppKit call; the panel itself can only be verified by running the app.
- **UI flows, SwiftUI/AppKit rendering, WKWebView bridge interactions, conflict detection, autosave restoration, AI result panel visual correctness:** Documented in §7, run before each release.
