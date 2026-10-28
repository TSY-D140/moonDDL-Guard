# Umami migration specimens

Unmodified SQL and MIT license from `umami-software/umami`, commit `559e3c607c23d2c72d9bd4f6481bda428255323c`:

- `indexes.sql`: https://github.com/umami-software/umami/blob/559e3c607c23d2c72d9bd4f6481bda428255323c/prisma/migrations/03_metric_performance_index/migration.sql
- `mixed.sql`: https://github.com/umami-software/umami/blob/559e3c607c23d2c72d9bd4f6481bda428255323c/prisma/migrations/09_update_hostname_region/migration.sql
- `umami.LICENSE`: https://github.com/umami-software/umami/blob/559e3c607c23d2c72d9bd4f6481bda428255323c/LICENSE

The 17 ordinary index statements demonstrate real migration preflight. The mixed migration now also assesses its VARCHAR column addition and two column removals. UPDATE and RENAME remain visible and incomplete, while its DROP/CREATE INDEX statements are still diagnosed. These samples are not executed against a database or advertised as a portable schema.
