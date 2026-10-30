# Umami migration specimens

Unmodified SQL and MIT license from `umami-software/umami`, commit `559e3c607c23d2c72d9bd4f6481bda428255323c`:

- `indexes.sql`: https://github.com/umami-software/umami/blob/559e3c607c23d2c72d9bd4f6481bda428255323c/prisma/migrations/03_metric_performance_index/migration.sql
- `mixed.sql`: https://github.com/umami-software/umami/blob/559e3c607c23d2c72d9bd4f6481bda428255323c/prisma/migrations/09_update_hostname_region/migration.sql
- `umami.LICENSE`: https://github.com/umami-software/umami/blob/559e3c607c23d2c72d9bd4f6481bda428255323c/LICENSE

The 17 ordinary index statements demonstrate real migration preflight. All nine mixed-migration statements are now assessed: VARCHAR addition, UPDATE FROM, index removal, column rename/removal and index creation. The optional PostgreSQL harness executes this unmodified mixed SQL on a matching disposable test schema and checks its effects. This is not a claim that the sample runs on arbitrary databases, or that the full upstream deployment/schema has been verified.
