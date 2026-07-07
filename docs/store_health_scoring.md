# Store Health Scoring

StorePilot stores a health score on each `AuditRun` after audit results are
persisted.

Each tracked category starts at 100. Opportunities reduce category scores by
priority:

- High priority: 25 points
- Medium priority: 15 points
- Low priority: 7 points

The overall score is the rounded average of category scores for SEO, inventory,
product quality, and revenue. Category scores never go below 0.

When a previous completed audit run has an `overall_score`, the latest run stores
`previous_score_delta` as `current overall score - previous overall score`.
