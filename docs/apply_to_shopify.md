# Apply to Shopify — spec

Turn StorePilot from an advisor into an operator: let a merchant push a
StorePilot-drafted fix straight into their Shopify store with one click, then
mark the audit action done and verify the change is live.

The values to apply already exist — `Ai::AuditExampleGenerator` writes them to
`audit_result.details["examples"]`. This spec adds the write path.

## Scope

MVP (ships on existing `write_products` scope):

| Finding (`rule_key`) | Example field | Shopify target |
| --- | --- | --- |
| `seo_gap` | `meta_title` | `product.seo.title` |
| `seo_gap` | `meta_description` | `product.seo.description` |
| `product_quality` | `product_title` | `product.title` |
| `product_quality` | `product_description` | `product.descriptionHtml` |

Later / gated:

- `seo_gap` → `image_alt`: requires the **`write_files`** scope (merchant
  re-consent) via `fileUpdate`. Sequence after the scope bump.
- `review_gap` → `review_request`: not a product write. Sends through an
  email/reviews integration (Klaviyo, a reviews app) — separate track.
- `bundle_opportunity`, dead-stock promo: **create** operations
  (`productCreate` / `collectionCreate` / `discountCodeBasicCreate`), not
  `productUpdate` — separate track.

## Shopify API (validated against 2026-04)

Single mutation covers all MVP fields; one call per product regardless of how
many fields change. `productUpdate(input:)` is deprecated — use `product:`.

```graphql
mutation ApplyProductFields($product: ProductUpdateInput!) {
  productUpdate(product: $product) {
    product { id title descriptionHtml seo { title description } }
    userErrors { field message }
  }
}
```

`ProductUpdateInput` = `{ id, title, descriptionHtml, seo: { title, description } }`.
Required scope: `write_products` (already granted). Always inspect
`userErrors` — `productUpdate` returns HTTP 200 with per-field errors.

Image alt (later):

```graphql
mutation ApplyImageAlt($files: [FileUpdateInput!]!) {
  fileUpdate(files: $files) { files { id alt } userErrors { field message } }
}
```

Required scope: `write_files` (NOT granted — needs re-auth).

## Prerequisite: make examples targetable

`details["examples"].items` currently store `{ title, fields:[{label,value}] }`.
Apply needs the product GID and a machine key per field. Extend
`Ai::AuditExampleGenerator` to emit:

```json
{
  "product_id": "gid://shopify/Product/123",
  "title": "Seasonal Candle",
  "fields": [
    { "key": "meta_title", "label": "Meta title", "value": "…", "applicable": true }
  ]
}
```

`key` maps to the Shopify target via a fixed table (see Scope). Keep `label`
for display. Do not match by title — always target by `product_id`.

## Components

1. **`Shopify::Apply::ProductFields`** (new service). Input: store + change set
   `[{ product_id, seo_title?, seo_description?, title?, description_html? }]`.
   Builds one `ProductUpdateInput` per product, calls it through the existing
   `Shopify::Admin::GraphqlClient.new(shop:, access_token:)`, returns per-product
   results `{ product_id, applied: {field=>value}, errors: [...] }`.

2. **`Shopify::ApplyJob`** (new job, `queue_as :default`). Runs the service
   async (batches + rate limits), records the outcome on the result/action,
   completes the `AuditAction` on full success, and enqueues a targeted re-sync
   of the touched products to confirm.

3. **`DashboardController#apply_audit_result`** (new action) + route:
   `POST /dashboard/audit_results/:id/apply` (mirrors the existing
   `generate_win_back_email_draft` pattern). Params: which item/field values to
   apply (merchant may have edited them). Guards `current_store`, builds the
   change set, enqueues `ApplyJob`, redirects with a notice.

4. **Model changes** on `AuditAction` (or a small `applied_changes` jsonb on the
   result): `applied_at:datetime`, `applied_changes:jsonb`, and an
   `application_status` (`pending` → `applied` / `partial` / `failed`). Store the
   previous Shopify value alongside the new one to enable Revert.

## End-to-end flow (SEO example)

1. Audit runs → `seo_gap` result → `AuditExampleGenerator` drafts values
   (product_id + fields).
2. Dashboard renders each example field as an **editable** input with a checkbox
   and an **Apply to Shopify** button on the finding.
3. Merchant edits/approves → clicks Apply → `POST …/apply` with the selected
   values.
4. Controller builds the change set (only checked, non-blank fields) →
   `ApplyJob.perform_later(result_id, changeset)` → redirect
   "Applying 4 products to Shopify…".
5. Job → `Shopify::Apply::ProductFields.call(store, changeset)` → one
   `productUpdate` per product.
6. On success: record `applied_at` + `applied_changes` (old + new), set the
   `AuditAction` complete with note "Applied by StorePilot", enqueue re-sync of
   those product IDs.
7. UI reflects: finding shows "Applied ✓ — live in Shopify", moves to Activity →
   Completed actions; next audit no longer flags those products, health score
   ticks up (visible ROI).

## Safety & correctness

- **Approval-first.** Never auto-apply. Values are editable; Apply is explicit.
- **Idempotency.** Re-read the current Shopify value before writing; skip if the
  merchant already set it (don't clobber manual edits). Guard double-clicks with
  the `application_status` state.
- **Scope check.** Verify `write_products` before SEO/catalog; for alt text,
  detect missing `write_files` and prompt reconnect instead of failing.
- **Rate limits.** Shopify GraphQL is cost-throttled — one job, sequential per
  product, exponential backoff on `THROTTLED`. Batch size cap (e.g. 50/run).
- **userErrors.** Treat any `userErrors[]` as a per-product failure; report
  partial success ("3 applied, 1 failed: <reason>").
- **Audit trail + Undo.** `applied_changes` stores old→new per field so a
  "Revert" re-applies the previous value.
- **Least privilege.** Only touch the fields StorePilot flagged; never write
  fields it didn't surface.

## UX states

`idle` → `applying…` (button disabled, spinner) → `applied ✓ (n products)` /
`partial (n ok, m failed)` / `failed (reason)`. Surface the live value after
re-sync ("now live in Shopify").

## Testing

- Service unit tests with a stubbed `GraphqlClient`: success, `userErrors`,
  `THROTTLED` backoff.
- Controller test: enqueues `ApplyJob` with the right change set; guards no-store.
- Job test: updates `AuditAction`, records `applied_changes`, handles partial.
- E2E against a dev store: apply → re-sync → assert `seo.title/description`
  populated and the gap clears on the next audit.

## Rollout order

1. SEO `seo.title` / `seo.description` — cleanest, single mutation, existing scope. **MVP.**
2. Catalog `title` / `descriptionHtml` — same mutation, same scope.
3. Image `alt` — after adding `write_files` scope + re-consent.
4. Reviews — via email/reviews integration (not a product write).
5. Bundles / discounts — create mutations, separate track.
