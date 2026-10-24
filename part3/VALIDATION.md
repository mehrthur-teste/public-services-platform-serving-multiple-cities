# Validation

Verified on 23 October 2026:

- Exactly eight native domain scripts: seven `.sql` files and one `.js` file.
- PostgreSQL syntax parsed with pglast 8.7: 310 SQL statements across seven files.
- All five PL/pgSQL trigger functions parsed successfully.
- All 34 relational tables have explicit INSERT, SELECT, UPDATE and DELETE examples.
- MongoDB JavaScript passed `node --check`; this checks syntax, not MongoDB behaviour.
- Relational primary/composite keys, dependency ordering, cross-schema references,
  temporary CRUD IDs and local analytical dimension references were reviewed.
- The report was rendered for layout review. Part 3 starts on page 110, before
  Conclusion, and includes the eight-source/eight-column table and a 457-word
  justification. Earlier source content is preserved.

Not verified by execution:

- Full runs and reruns against PostgreSQL/PostGIS and MongoDB servers.
- Runtime query plans, concurrency and workload performance.
- S3 uploads/downloads: native SQL intentionally handles metadata only.

The temporary Docker image downloads did not complete, so server-side integration
success is not claimed. Run the commands in README.md against dedicated databases
before using these examples as an executed demonstration.
