#!/usr/bin/env -S deno run --allow-read
// Atlas — doc-tabs read shim for the live E2E (scripts/doc_tabs_e2e.py).
//
// Reads a `documents.get?includeTabsContent=true` JSON payload from the file
// path in argv[0] and prints `readTabs(doc)` as JSON to stdout. This makes the
// Python E2E derive each tab's markdown / writability with the EXACT same code
// the deployed edge functions use (no Python re-implementation to drift), so the
// round-trip assertion tests reader∘renderer == identity on real content.
//
//   deno run --allow-read scripts/doc_tabs_read_shim.ts <documents.get.json>

import { readTabs } from "../supabase/functions/_shared/doc_tabs.ts";

const path = Deno.args[0];
if (!path) {
  console.error("usage: doc_tabs_read_shim.ts <documents.get.json>");
  Deno.exit(2);
}
const doc = JSON.parse(await Deno.readTextFile(path));
console.log(JSON.stringify(readTabs(doc)));
