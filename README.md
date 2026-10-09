# Quill

A native macOS app for writing and managing WordPress content.

Quill connects to any self-hosted WordPress site through the built-in REST API and Application Passwords. No plugin, no third-party service, no subscription.

**[Download, documentation and changelog → quill.siolon.com](https://quill.siolon.com)**

![Quill editing an Accordion block, with the block settings row under the toolbar](site/images/blocks-view.webp)

## Requirements

- macOS 27 or later
- A self-hosted WordPress site running WordPress 7.0 or later, served over HTTPS
- WordPress.com is not supported

## Build

Building needs Swift 6.3.1 and a full Xcode install. `build.sh` compiles the asset catalog with `actool`, which the Command Line Tools alone do not provide.

```bash
./build.sh && open Quill.app
```

The test suite needs `node` and `jsdom` installed in `Scripts/`, not in the project root.

```bash
./test.sh
```

## Architecture

Start with [CLAUDE.md](CLAUDE.md). It maps `Sources/QuillKit`, records the key design decisions, and indexes the per-directory gotcha files. Longer notes live in [docs/](docs/).

## License

Quill is **not** open source. Under the [license](LICENSE.md) you may use Quill for any purpose, including paid work, and change and build the source for your own use or your organization's. You may not sell or redistribute Quill or anything built from it, or present it as your own work.

Third-party components are listed in [NOTICES](NOTICES.md).
