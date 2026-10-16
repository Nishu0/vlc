# Figma reference cache and request budget

Access was restored on 2026-10-16. The connected account now has a Dev seat on the Professional team, and the previously blocked playback-inspector request for `2238:9432` succeeded. No reconnect was needed.

Figma currently publishes a Professional Full/Dev allowance of up to 200 reads/day and 10/minute. These are service limits, not a promise of unlimited access. See the [official access documentation](https://developers.figma.com/docs/figma-mcp-server/rate-limits-access/). Other activity on the account may consume allowance too; our local records are not an authoritative Figma usage meter.

## Cache first

Before requesting Figma data, inspect `build-macos-baseline/figma-reference-cache.json` and the existing inventories under `doc/redesign/`. These references are local build/research output and remain ignored by Git.

- `design-context/full/<node-id>.json`: full text context, styles, instructions, and a local render reference.
- `design-context/<node-id>.txt`: generated reference code for quick searches.
- `design-reference/context/<node-id>.png`: the screenshot returned with that context.
- `design-assets-manifest.json`: source node, original asset URL, and local asset path.
- `design-assets/<node-id>/`: downloaded original files. Use the local files in implementation; temporary URLs are not runtime assets.

Nineteen successful contexts and their nineteen renders are preserved. A cache hit requires the needed context, render, and non-empty assets. Missing customization assets are recorded as incomplete rather than silently accepted. A local checksum verifies saved data, but does not prove that the remote design is unchanged: the tool responses do not supply a dependable file-version identifier here.

## Request discipline

1. Reuse a saved context for implementation and visual comparisons. Run and inspect the local app without spending another Figma call.
2. Inspect shared controls/tokens once and reuse that reference across screens. Fetch a distinct variant when its layout, styling, or behavior actually differs.
3. Fetch only the next uncached screen/component needed for implementation. Avoid prefetching all 103 frames or repeatedly requesting the whole page. If a large context is sparse, inspect its metadata and request the relevant children as required by the design-to-code skill.
4. Keep the screenshot returned by `get_design_context`; do not immediately request the same screenshot separately. Request a separate render only when the supplied image is absent, inadequate for the detail under review, or stale.
5. Save new context, its render, and original assets immediately, before temporary URLs expire. Check downloads locally and retry failed transfers without refetching the design when its URLs still work.
6. Use supported batching only. The currently connected `get_design_context` and `download_assets` schemas each accept a single node; concurrent individual requests still count separately.
7. Refresh a cached node when the user reports a design change or evidence shows it is stale. Record that refresh explicitly. Do not poll the file to look for changes.

## Conservative local budget

Use no more than six read attempts in a rolling minute and a working target of at most 100 project read attempts per day, leaving headroom under the published limits. Count attempted read calls, including failures, conservatively. `whoami` is documented as exempt and can diagnose account/seat issues without a design-read probe.

Record future attempts in `build-macos-baseline/figma-read-ledger.json`. Earlier research calls predate that ledger, so its historical count is explicitly incomplete. Do not represent it as the account's remaining allowance or assume Figma's reset boundary.

If a rate-limit response occurs, honor any supplied retry/reset information and stop repeated probes. Continue independent implementation from saved references. Do not create extra accounts, reconnect repeatedly, or switch tools merely to evade the provider's quota.

This workflow reduces consumption; it cannot guarantee that the account will never reach a server-enforced limit.
