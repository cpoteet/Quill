#!/bin/zsh
# Report-only: prints what each dependency is pinned at, what is newer, and npm audit results.
set -u
cd "$(dirname "$0")/.."

section() { print "\n== $1" }

npm_report() {
  local dir=$1
  section "$dir"
  node -e '
    const { execSync } = require("child_process")
    const pkg = require(process.argv[1] + "/package.json")
    const lock = require(process.argv[1] + "/package-lock.json").packages
    const deps = { ...pkg.dependencies, ...pkg.devDependencies }
    for (const name of Object.keys(deps)) {
      const pinned = lock["node_modules/" + name]?.version ?? deps[name]
      const major = pinned.split(".")[0]
      const view = range => { try { return JSON.parse(execSync(`npm view ${name}@"${range}" version --json`, { stdio: ["ignore", "pipe", "ignore"] }).toString()) } catch { return null } }
      const inMajor = [view(major === "0" ? `~${pinned}` : `^${pinned}`)].flat().filter(Boolean).at(-1) ?? pinned
      const latest = view("latest")
      const flag = name.startsWith("@wordpress/") ? "  pinned to the WordPress release, see below"
        : latest !== pinned ? (inMajor !== pinned ? "  UPDATE AVAILABLE" : "  newer major only") : ""
      console.log(`  ${name.padEnd(48)} ${pinned.padEnd(10)} in-range ${String(inMajor).padEnd(10)} latest ${latest}${flag}`)
    }
  ' "$PWD/$dir"
  (cd "$dir" && npm audit --package-lock-only 2>/dev/null | grep -E "vulnerabilit" | tail -1 | sed 's/^/  audit: /')
}

npm_report Scripts/tiptap-bundle
npm_report Scripts/marked-bundle
npm_report Scripts

section "ProseMirror inside the Tiptap bundle"
node -e '
  const { execSync } = require("child_process")
  const lock = require("./Scripts/tiptap-bundle/package-lock.json").packages
  for (const key of Object.keys(lock).filter(k => /^node_modules\/prosemirror-[a-z-]+$/.test(k))) {
    const name = key.slice("node_modules/".length)
    const latest = execSync(`npm view ${name} version`).toString().trim()
    if (latest !== lock[key].version) console.log(`  ${name.padEnd(48)} ${lock[key].version.padEnd(10)} latest ${latest}`)
  }
'

section "WordPress release the @wordpress test packages must match"
WP=$(curl -s https://api.wordpress.org/core/version-check/1.7/ | python3 -c "import sys,json; print(json.load(sys.stdin)['offers'][0]['current'])")
SHA=$(curl -s "https://raw.githubusercontent.com/WordPress/wordpress-develop/$WP/package.json" | python3 -c "import sys,json; print(json.load(sys.stdin)['gutenberg']['sha'])")
print "  WordPress $WP (Gutenberg $SHA)"
for p in block-serialization-default-parser blocks block-library block-editor components compose data private-apis rich-text; do
  want=$(curl -s "https://raw.githubusercontent.com/WordPress/gutenberg/$SHA/packages/$p/package.json" | python3 -c "import sys,json; print(json.load(sys.stdin)['version'])")
  have=$(node -p "require('./Scripts/package-lock.json').packages['node_modules/@wordpress/$p']?.version ?? '-'")
  [[ $want == $have ]] && mark="" || mark="  MISMATCH"
  print "  @wordpress/${(r:42:)p} have ${(r:10:)have} release ${want}${mark}"
done

section "Swift packages"
node -e '
  const { execSync } = require("child_process")
  for (const pin of JSON.parse(require("fs").readFileSync("Package.resolved", "utf8")).pins) {
    const tags = execSync(`git ls-remote --tags ${pin.location}`).toString().split("\n")
      .map(l => l.split("refs/tags/")[1]).filter(t => t && /^\d+\.\d+\.\d+$/.test(t))
      .sort((a, b) => a.localeCompare(b, undefined, { numeric: true }))
    console.log(`  ${pin.identity.padEnd(48)} ${pin.state.version.padEnd(10)} latest ${tags.at(-1)}`)
  }
'
