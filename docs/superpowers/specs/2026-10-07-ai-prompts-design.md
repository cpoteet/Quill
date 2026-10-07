# Rewriting the AI prompts for current models

_Design, 2026-10-07. Draft: the prompts below are being tested, and this file records decisions as they are made._

## Problem

Quill's prompts (Evaluate, Generate Post, Make Longer / Make Shorter) were written for Claude Haiku 4.5 and work around its limits: a capped list of mechanical findings, word-count scaffolding, a line-based response format. The default model is now Claude Haiku 5.5 (see `2026-10-02-ai-model-selection-design.md`), which follows instructions and copies text far more reliably, so the prompts can ask for more and constrain less.

The biggest problems are in what the prompts are given, not their wording:

- Evaluate strips all HTML, so headings and list items look like paragraphs, and captions are deleted outright (two sample posts have caption typos Evaluate can never see). It has no date, so Claude Haiku 4.5 called "2020 to 2026" a typo.
- Make Longer / Make Shorter receive the selection as plain text (`beginAIOperation` uses `textBetween`), so every rewrite loses its links, emphasis and footnote markers. They get no surrounding text, so Make Longer can repeat the next paragraph or invent facts to fill the length.
- Generate Post asks for nothing beyond HTML structure, so with a long style guide it writes invented first-person experience in the author's voice.
- The system prompt says "Write in this author's style" for every task, including Evaluate, which writes nothing.

## Decisions

- **Evaluate** returns three parts: Corrections (spelling, grammar, punctuation, word choice, consistency of names and terms; every one, no cap), Suggestions (clarity, concision, flow, repetition, drift from the style guide; only those worth the author's time, keeping the author's wording outside the flagged span) and an overall review (what works, then the two or three changes that matter most to the title, opening, structure, headings or ending). Passive Voice is dropped as a category.
- **Evaluate fact-checks with web search on every run** when Web Search is on in Settings and the model supports it. Without search it skips fact-checking rather than judging facts from training data.
- **Evaluate's input keeps structure** with plain-text markers (`## Heading`, `- item`, `[Caption] …`) so anchors still match the editor text.
- **Generate Post makes no first-person claims** about the author's experience: no invented anecdotes and no placeholders.
- **Generate Post searches directly** (`allowed_callers: ["direct"]`), like Evaluate: dynamic filtering crashed, cost more and linked fewer sources (see Generate Post results).
- **Make Longer / Make Shorter send HTML and the paragraphs around the selection**, which changes `beginAIOperation` in `editor.html`. Make Longer must not add facts, figures, names or experiences the text and its context don't support.
- **Fact checks are shown as "Check this" items**, never as corrections: the claim, what the source says with its own sentence quoted, and a link, so the author can judge each in seconds.
- **Evaluate sends two requests at once:** corrections, suggestions and the review without search, and the fact-check with search. The first group appears as soon as it is ready; the fact checks fill in after.
- **Every correction and suggestion gets a one-click Apply**, which replaces its `original` with its `replacement`. The panel is option B in `2026-10-07-evaluate-panel-mockups.html`: a segmented control with Review, Fixes, Ideas and Facts tabs, opening on Review with a one-line count of what the other tabs hold.
- **Web search always uses the newest version the model accepts**; Evaluate's fact-check calls it directly (`allowed_callers: ["direct"]`), not through dynamic filtering.
- **Two new selection commands:** Fix Spelling & Grammar (corrections only, no rewording, links and formatting kept) and Rephrase (same meaning and length, in the author's voice).

## Later

Not in this round; deferred design decisions go in GitHub issues on `cpoteet/Quill`.

- **Match My Voice:** rewrite a selection (pasted text, a rough draft) to fit the style guide.
- **Simplify:** plainer words and shorter sentences, same content; suited to technical explainers.

## Baseline (current prompts, 2026-10-07)

Evaluate, unchanged, on three published posts with known errors:

| | Claude Haiku 4.5 | Claude Haiku 5.5 |
|---|---|---|
| Known errors caught | 4 of 9 | 9 of 9 |
| Wrong claims | "2020 to 2026" called a typo | none |
| Anchors that locate their text | 27/27 | 33/33 |
| Findings per post | 7–11 | 10–12 (at the prompt's cap) |

## Evaluate draft results (2026-10-07)

The draft asks for corrections, suggestions, a review and fact checks as JSON (`output_config.format`), with the post in the marked-up form above. Claude Haiku 5.5, default effort, four posts:

- **Corrections:** 10 of the 11 known errors, including both caption typos, plus real ones nothing else caught ("topics which has", "but it gives" for plural "numbers") and internal contradictions (a table marking two modules "Yes" where the bullet list says "matched items only").
- **`original` is reliable:** every quoted span (243 of 243 across all draft runs) matched the post exactly, so the separate ANCHOR field is no longer needed, and a finding could be applied with one click.
- **Fact checks found real problems** (Syntex renamed SharePoint Premium, Viva Topics retired, SAM licensing changed, "the only place" contradicted by the post's own table), but also misread an ambiguous Microsoft Learn sentence as contradicting an accurate claim. They have to be shown as things to check, with the source's own wording, not as corrections.
- **Web search tool:** `web_search_20260209` and later default to dynamic filtering: Claude calls search from Python it writes and filters the results before reading them, which the docs pitch at search-heavy requests. Evaluate makes two to four targeted lookups. Rerun with `max_uses` 10 for both, four posts, two runs each:

  | Tool | Fact checks per run | Searches | Cost | Time | Runs where its code crashed |
  |---|---|---|---|---|---|
  | `web_search_20250305` | 2.1 | 3.0 | $0.039 | 44 s | 0 of 8 |
  | `web_search_20260209` (dynamic filtering) | 1.2 | 7.4 | $0.081 | 55 s | 7 of 8 |

  The crash was the same each time: Haiku 5.5's code treats each search result as a dictionary, but they come back as strings, and every retry spends searches. Claude Sonnet 5.5 made the same mistake once per run and recovered (2.5 fact checks, $0.22, 80 s). `web_search_20260318` with `allowed_callers: ["direct"]`, the newest version without dynamic filtering, matched the basic tool on the two fact-heavy posts ($0.03–0.04, about 40 s).
- **Time:** 39–56 seconds per Evaluate with fact-checking.
- Fixed in the draft after the first run: the review referred to the author in the third person, treated the style guide as a checklist ("add a table and footnotes, which the author favors") and filed judgment calls as corrections.

## Evaluate: final design

Two requests sent at once. Neither uses the shared `systemPrompt(styleGuide:)`; each has its own. Both return JSON through `output_config.format`, and every finding's `original` must be found in the post before Quill offers Apply or jump-to: an `original` that does not match (2 of 793 in testing) is shown without either.

### The post as Claude sees it

Plain text whose characters match the editor's, so `original` can be found: `## ` before a heading (one `#` per level), `- ` before a list item, `| a | b |` for a table row, `[Caption] ` before an image caption, `[Footnote] ` before a footnote. Code blocks and embeds are left out, as now. After the title comes `Published: YYYY-MM-DD` for a published post, or `Status: draft, not yet published`.

### Review request (no tools)

System:

```text
You are an experienced editor reviewing a blog post for its author in Quill, a WordPress editor. Today's date is {date}. Write to the author as "you".

The author's style guide is below. Writing that follows it is intentional: don't correct the author's voice, word choices or habits toward a generic style. Use the guide to recognise the author's voice, not as a checklist: never suggest adding tables, footnotes, lists, asides or any other feature because the guide mentions it.

<style_guide>
{guide}
</style_guide>
```

The style-guide paragraph is left out when there is no guide. User:

```text
Review this post and report what would make it better. It is shown as plain text: "## " marks a heading, "- " a list item, "| … |" a table row, "[Caption]" an image caption and "[Footnote]" a footnote.

<post>
Title: {title}
{Published: … | Status: …}

{post}
</post>

Report three kinds of feedback. Someone else is checking facts, so don't judge whether claims are true.

Corrections are errors any copy editor would fix whatever the author's style: spelling, grammar, punctuation, a wrong or missing word, and inconsistent names, capitalization or terms. Report every one you find, in captions, footnotes and tables too. A spelling or style the author uses consistently is not an error, even where a style manual would differ. A judgment call is a suggestion, not a correction.

Suggestions are changes worth the author's time: a sentence that is hard to follow, wording that could lose words without losing meaning, an awkward transition, a repeated word or idea, or a passage that drifts from the style guide. Rewrite only the words that need it and keep the author's wording elsewhere. Skip changes that are a matter of taste. A short list of strong suggestions is better than a long one.

The review is your overall judgment: what works, then the two or three changes that would improve the post most, looking at the title, the opening, the order of sections, the headings and the ending.

For every correction and suggestion, "original" is the exact text it applies to, copied character for character from the post (without the markers), as short as it can be while still being unique in the post. "replacement" is the text to put in its place. If the fix is to delete the text, "replacement" is an empty string.
```

Schema: `review` {`strengths`, `priorities[]`}; `corrections[]` and `suggestions[]` of {`category`, `original`, `replacement`, `explanation`}. Correction categories: Spelling, Grammar, Punctuation, Word choice, Consistency. Suggestion categories: Clarity, Concision, Flow, Repetition, Voice, Structure. Quill drops any item whose `replacement` equals its `original` (one run returned one).

### Fact-check request (web search)

Sent only when Web Search is on and the model supports it. Newest web search version, `allowed_callers: ["direct"]`, `max_uses` 8. No style guide. System:

```text
You fact-check blog posts for their author in Quill, a WordPress editor. Today's date is {date}. Write to the author as "you". Your training data ends well before today's date. Product names, versions, release status, dates, prices, people's roles, rules and anything "latest" may have changed since then, so search for those before you judge them, even when you feel sure.
```

User:

```text
Fact-check this post. {same marker sentence}

<post>…</post>

Check claims a reader could verify against a public source, not the author's own experiences, plans or opinions. A published post is judged against its publish date: a claim that was true then is not an error, but if it has since changed, say so. Prefer the vendor's own documentation and announcements to blogs and forums. Search at most 8 times.

First list every checkable claim in "claims", each with its verdict: "confirmed", "wrong", "outdated", "needs qualifier" or "not checked". Search for every claim about something that can change before giving it a verdict; use "not checked" only when you ran out of searches. Group related claims into one search where you can.

Then, in "fact_checks", report each claim whose verdict is wrong, outdated or needs qualifier. For each one, "original" is … (as above). "explanation" says in one or two sentences what is wrong and what is true instead. "source_quote" is the sentence from the source that shows it, copied exactly, and "source_url" is that source. "replacement" is corrected wording for "original", or an empty string if the author should decide how to fix it.
```

Schema: `claims[]` of {`claim`, `verdict`}; `fact_checks[]` of {`original`, `explanation`, `source_quote`, `source_url`, `replacement`}. Listing every claim first was what made the fact-check thorough: without it Haiku 5.5 searched one to four times and caught the Viva Topics retirement in one run of three; with it, in both runs. The claim list also gives the panel a count ("Checked 9 claims").

### Results (Claude Haiku 5.5, default effort)

| | Review request | Fact-check request |
|---|---|---|
| Time | 14–24 s | 9–41 s |
| Cost | $0.002–0.003 | $0.02–0.09, mostly searches |
| Result | 9 of 11 known errors in every run | Viva Topics and Syntex caught 2 of 2 runs, each with the source sentence quoted |

High effort on either request changed nothing measurable, so both use the model's default. Things to check when building: an `original` that appears more than once (take the first match, as jump-to does now), and the "not checked" verdicts, which include claims Haiku could have skipped as opinion.

## Selection commands: final design

Make Longer, Make Shorter, Fix Spelling & Grammar and Rephrase share one request shape. (Convert to Table and Convert to List keep their instructions, but get the same HTML input.)

### What Quill sends

`beginAIOperation` returns, besides what it returns today:

- `html`: the selection serialized with ProseMirror's `DOMSerializer`, reduced so Claude never has to copy a URL or an ID: each link becomes `<a id="L1">…</a>`, each footnote marker `<sup id="F1"></sup>`, `<em>`, `<strong>`, `<code>` and `<s>` are kept bare, and every other attribute is dropped. The editor keeps the mapping (`L1` → the original link's attributes, `F1` → the original marker node) on the pending operation.
- `before` / `after`: the plain text of the selection's own paragraph on either side of it plus one paragraph further out, so a mid-paragraph selection sees the rest of its sentence.
- The post title.

`showAIResult` puts the attributes back by ID before inserting: a stub whose ID is not in the mapping is unwrapped to its text, and a footnote marker missing from the result is simply gone (its words were cut). Word counts for the length targets are taken from the selection's text, as now.

### Request

Thinking stays on at the model's default effort; JSON output `{"html": "…"}` through `output_config.format`, so no preamble or code fence can reach the editor. System:

```text
You edit part of a blog post for its author in Quill, a WordPress editor. You rewrite only the selected text; the text around it is there so your rewrite fits in its place.

Match the author's voice. The selected text is the best example of it; the style guide below describes it more broadly. Quoted words and phrases in the guide are examples of the author's habits, not phrases to reuse.

<style_guide>
{guide}
</style_guide>
```

User:

```text
<post_title>{title}</post_title>

<before>
{before}
</before>

<selection>
{html}
</selection>

<after>
{after}
</after>

{instruction}

The selection is HTML and may start or end mid-paragraph; your rewrite replaces it exactly, so it must fit between the text before and after. Keep each <a id="…">…</a>, <sup id="…"></sup>, <em>, <strong> and <code> with the words it belongs to, and drop one only when you remove all of its words. Don't add links, footnotes or formatting, and don't repeat what the text before or after already says. Put the rewritten selection in "html".
```

Instructions (`{w}` is the selection's word count; `{t}` and `{m}` are today's targets and ceilings, unchanged):

| Command | Instruction |
|---|---|
| Make Longer | Expand the selection from {w} words to about {t} words, and never more than {m}. Keep the author's sentences, and add new ones that explain the reasoning, spell out a consequence or give a general example of what the selection already says. Don't add facts, figures, names, dates or quotes that the selection and the text around it don't support, and don't describe anything the author did, saw or felt beyond what the text says. Keep the same number of paragraphs. |
| Make Shorter | Shorten the selection from {w} words to about {t} words, and never more than {m}. Cut the least important sentences and tighten the rest, keeping the author's own words where you can. Keep the meaning and the same number of paragraphs. |
| Fix Spelling & Grammar | Fix the spelling, grammar and punctuation errors in the selection, and nothing else. Keep every other word, the word order and the author's style, even where you would write it differently. If there is nothing to fix, return the selection unchanged. |
| Rephrase | Rephrase the selection so it reads more clearly and smoothly, with the same meaning and about the same length ({w} words). Keep the author's voice, and keep their wording wherever it already reads well. |

Lists and tables still send the whole container, now as reduced HTML; the list and table variants of each instruction need the same test before they ship.

### Results (2026-10-07)

Seven real selections: whole paragraphs with links, emphasis and a footnote, one mid-paragraph sentence, a 161-word paragraph, and three with known errors.

| | Current prompt, Haiku 4.5 | Current prompt, Haiku 5.5 | New prompt, Haiku 5.5 |
|---|---|---|---|
| Longer: length within 20% of target | 4/7 | 7/7 | 7/7 |
| Shorter: length within 20% of target | 4/7 | 7/7 | 6/7 |
| Links, footnotes and emphasis kept | 0–1 of 9 | 0 of 9 | 9 of 9, every command |
| Longer: time | 2.6 s | 8.9 s | 7–10 s |
| Shorter / Fix / Rephrase: time | 1.4 s | 6.2 s | 6.7 s / 3.1 s / 2.6 s |

- **Today's prompt loses every link and footnote** because the editor sends plain text, and on a mid-paragraph selection it returns a `<p>`, which splits the paragraph.
- **Make Longer invented the author's experience** under today's prompt ("I spent a good chunk of my first week poking at the settings menus"). The new instruction keeps the author's sentences word for word and adds reasoning and general examples; the first draft, which only said "don't add experiences they don't support", still invented some.
- **Make Shorter** keeps the author's words; today's prompt rewrote them in another voice ("Spending ages… kept bugging me").
- **Fix Spelling & Grammar** made 0–2 changes per selection, all real errors ("on on", "have already their", the commas around "not against"), and nothing else.
- **Effort:** low and default were indistinguishable in time, tokens and output. With thinking off, the commands ran two to four times faster, but Shorter hit its length 1 time in 7 and Longer went back to inventing experiences, so thinking stays on.
- Every command costs under $0.001.

## Generate Post: final design

One request with web search (when on and supported): newest version, `allowed_callers: ["direct"]`, `max_uses` 10. JSON output `{"title", "excerpt", "html"}`, which replaces the `TITLE:` / `CONTENT:` parsing and its preamble workaround; the excerpt fills the post's Excerpt field, which Quill already edits.

System:

```text
You write blog post drafts for an author in Quill, a WordPress editor. Today's date is {date}.

The author edits the draft and publishes it under their own name, so everything in it must be true of them, and you don't know their life. Don't write about what the author does, did, uses, tried, noticed or plans, and don't mention their work, clients or history, unless the description tells you about it. Give opinions as judgments about the subject ("Templates should…", "The better choice is…"), not as reports of the author's own habits or experience.

Write in the author's voice, following the style guide below. Its quoted words and phrases show the author's habits; don't copy them, because a copied phrase reads as a tic.

Your training data ends well before today's date. Records, office holders, prices, versions, rules and anything "latest" may have changed since then, so search for those before you write about them, even when you feel sure. Facts that can't change need no search.

<style_guide>
{guide}
</style_guide>
```

User:

```text
Write a blog post from this description:

<description>
{description}
</description>

Follow the style guide's length and structure unless the description asks for something else. Use only the HTML the post needs: <h2> for sections (<h3> under one only when a section needs it), <p>, <ul> or <ol> with <li>, <blockquote>, <em>, <strong>, and <table> with <thead>, <tbody>, <tr>, <th> and <td> for tabular data. No other tags, no attributes except href, no styles and no Markdown. Link each fact you took from a search to its source, with <a href="…"> on the words it supports, the way the author links inline.

Put the title, as plain text, in "title"; one or two sentences for the post's excerpt in "excerpt"; and the body in "html".
```

Without web search, the search paragraph and the linking sentence are left out.

### Results (2026-10-07)

Three descriptions in the author's subjects, each needing current facts (WordPress 7.x for long-form writers, SharePoint page templates, Claude Haiku 5.5 vs Sonnet 5.5):

| | Today (Haiku 4.5, current prompt, 163-word guide) | New prompt, direct search | New prompt, dynamic filtering |
|---|---|---|---|
| Source links | 0 | 4–17 per post | 2–8 |
| Time / cost | 21–31 s / $0.03–0.07 | 22–50 s / $0.02–0.06 | 37–129 s / $0.08–0.10 |
| Facts | Gave Haiku 4.5's price and context window for Haiku 5.5 | Correct prices and context window, linked | Code crashed 2–3 times per post |

- **Invented experience** was the main problem. With the 500-word guide and only "Opinions … are fine", the SharePoint post invented a routine ("every few months I open the gallery… and end up building the page from scratch anyway") and a section called "What I'm Doing in the Meantime". Asking for opinions as judgments about the subject removed nearly all of it; what remains is opinion ("I'd keep Sonnet for…") and the odd stray line ("The mistake I see most often…").
- **Copied guide phrases:** with "use them sparingly", the author's signature line appeared in two of three posts; with "don't copy them", in two of six. Instructions to hold back are followed only partly (see the style-guide Findings). If it matters in use, the next step is to send Generate the guide with its quoted phrases removed, which takes the choice away from the model.
- Search citations sometimes leave a space before punctuation ("honestly , they're"); `parseGenerateResponse`'s replacement should close it up.
- Effort and thinking were left at the model's defaults; not tested further.
