# Shopify Refund and Return Signals

StorePilot currently uses Shopify order refund data as the foundation for return-rate analysis.

The Admin GraphQL order sync can read refund line items and their refunded quantities/amounts when Shopify exposes them on recent orders. This gives a practical product-level refund ratio:

- units sold: synced order line item quantity
- refunded units: synced refund line item quantity
- refund ratio: refunded units divided by units sold

Limitations:

- Refunds are not the same as all return workflows. A merchant can process exchanges, manual adjustments, partial refunds, or external returns in ways that do not map perfectly to a product return.
- Historical accuracy depends on the sync window and the store's Shopify data availability.
- The MVP flags unusually high refund ratios for review only. It does not automate product changes, price changes, or customer messaging.
