# Evaluate fixture

A post with every block Evaluate marks up, and what the editor searches when it applies a finding.

| File | What it is |
|---|---|
| `post.html` | The post as Quill saves it |
| `post.footnotes.json` | Its `footnotes` meta |
| `post.editor-text.txt` | The editor's search text for that post (`_editorSearchText().text`) |

`Scripts/test-editor-evaluate.js` fails if the editor's text stops matching `post.editor-text.txt`; `EvaluationPromptsTests.postTextMatchesEditorText` checks that every line of `EvaluationPrompts.postText` can be found in it.
