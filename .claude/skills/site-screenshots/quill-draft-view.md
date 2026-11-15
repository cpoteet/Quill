Writing for WordPress in a browser tab has always felt like a compromise to me. The admin area is busy, the editor lives among dashboards and notifications, and the whole thing depends on a connection you may not have at the moment you want to write. A native app for the Mac is a better tool for that job, and [Quill](https://quill.siolon.com/) is one of the more convincing examples I have seen. Here is why it deserves a look.

## A real Mac app, not another browser window

Quill is a native macOS app for writing and managing a self-hosted WordPress site. It connects directly to your site through the built-in REST API and Application Passwords, so there is no plugin to install on the WordPress side and no third-party service in the middle. The project's [repository on GitHub](https://github.com/cpoteet/Quill) spells out the basics: no plugin, no third-party service, and no subscription.

The requirements are narrow, and you should know them before you download anything. The current release needs macOS 27 or later and a self-hosted site running WordPress 7.0 or later, reachable over HTTPS. WordPress.com sites aren't supported. Those limits will rule some people out, but for a self-hosted site on a recent Mac, they are reasonable.

## Drafts that wait for you

A new post starts as a local draft on your Mac and stays there until you send it to WordPress. Quill autosaves every 30 seconds, brings back unsaved changes the next time you open it, and warns you if the post changed on the site while you were away.
