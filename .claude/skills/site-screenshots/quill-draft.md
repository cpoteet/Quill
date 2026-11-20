Quill is a [native macOS app for writing and managing WordPress content](https://quill.siolon.com/). It connects to a self-hosted WordPress site through the built-in REST API and Application Passwords, so there's no plugin to install on the site, no third-party service in the middle, and no subscription. The setup is more ordinary than it sounds: [download the ZIP, move Quill.app to Applications, and enter your site's address](https://quill.siolon.com/docs.html#requirements--installation). Your browser then opens WordPress's approval page, or the app asks for an application password if the site has browser approval turned off.

## Writing without a connection

I think a writing tool should not depend on Wi-Fi, and Quill doesn't. [Local drafts are stored in SQLite, so you can write with no internet connection](https://quill.siolon.com/docs.html#saving--publishing), and the app autosaves every 30 seconds. Unsaved changes come back on the next launch, which matters more than it sounds like it should. When you're ready, you can push a draft to WordPress, schedule it, or publish directly. If the post was edited on the site in the meantime, Quill's conflict detection flags it rather than quietly overwriting someone's work.

Bars in the right margin mark every block that differs from the last save, so you can see what you changed before you send it anywhere.

## Blocks that edit like text

Headings, lists, tables, images, galleries, footnotes and embeds all work the way you'd expect. [Columns, Tabs, Accordions and Groups](https://quill.siolon.com/docs.html#working-with-blocks) edit inline like the rest of your text, and posts save in the block editor's format, so you can switch between Quill and the WordPress editor without losing anything.

## A second pair of eyes

Evaluate sends the post to Claude with your own API key and comes back with fixes, ideas and facts worth checking. Nothing changes until you apply a suggestion.
