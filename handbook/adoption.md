# Independent adoption and publication

The library can be consumed from this checkout without database credentials or a CLI wrapper. Run from the repository root:

```sh
moon run --deny-warn checks/consumer.mbtx
moon package
```

`integrations/consumer` is a separate module importing `TSY-D140/moonddl_guard@0.21.0`. Its parent `moon.work` resolves that dependency to this checkout. It checks that adding NOT NULL to a virtual generated column creates PG520, round-trips a full report, and fails the new-risk gate. The script runs the same consumer on all three portable backends. This proves source-level public API adoption; it does not prove registry installation.

Workspace configuration follows the official [local module dependency guide](https://tour.moonbitlang.com/basics/module-and-package/index.html). The consumer source and harness are project-owned Apache-2.0, not copied upstream tests.

`moon package` builds `_build/publish/TSY-D140-moonddl_guard-0.21.0.zip` after checking the module; CI runs packaging on Windows, Ubuntu and macOS. This is a local release artifact, not a published Mooncakes release. Do not commit generated archives or credentials.

Mooncakes publication remains pending: the pinned toolchain has no registry login, and the global login is not the intended repository owner's account. After the owner logs in with `moon login`, verify `moon whoami`, run `moon publish --dry-run`, then `moon publish`. Verify the registry entry and run this consumer in a fresh module outside `integrations/moon.work` using the published dependency before claiming registry adoption. No registry installation or publication success is currently claimed.

The PostgreSQL harness additionally checks two live sessions: one holds ACCESS EXCLUSIVE, another UPDATE fails at a 200ms lock timeout, and a fresh UPDATE succeeds after the holder commits. It polls the actual granted lock before starting the contender. This requires the disposable PostgreSQL 18 CI service; portable tests alone cannot establish those lock semantics.
