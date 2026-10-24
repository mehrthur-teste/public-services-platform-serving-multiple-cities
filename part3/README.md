# Part 3 – Develop a Storage and Retrieval Strategy

These are **native database scripts**, with no Python runtime or drivers required:
**seven PostgreSQL `.sql` files and one MongoDB `.js` file**, covering all eight
sources. The MongoDB file also implements the optional road/facility attribute
collections, so the package still has exactly eight numbered scripts.

## Run in order

Use PostgreSQL 16+ with PostGIS 3.5 and MongoDB 8.0+. Start in the **project root**:

```sh
psql -X -d postgres -f part3/scripts/01_road_and_facility_locations.sql
psql -X -d postgres -f part3/scripts/02_multimedia.sql
psql -X -d postgres -f part3/scripts/03_transportation_sensors.sql
mongosh "$MONGODB_URI" --file part3/scripts/04_environmental_monitoring.js
psql -X -d postgres -f part3/scripts/05_citizen_service_requests.sql
psql -X -d postgres -f part3/scripts/06_facility_maintenance.sql
psql -X -d postgres -f part3/scripts/07_emergency_rules_and_response.sql
psql -X -d postgres -f part3/scripts/08_historical_planning.sql
```

Configure PostgreSQL using `PGHOST`, `PGPORT`, `PGUSER`, `PGPASSWORD` or a password
file, and `PGSSLMODE` where required. Set `MONGODB_URI` to the intended MongoDB
connection string. Do not commit credentials. Use dedicated coursework databases.
The bootstrap account needs database/extension creation permission; provision the
databases and PostGIS first if using a more restricted runtime account.

These SQL files target **psql**. Its `\connect`, `\gexec`, `\gset` and `\copy`
commands handle database creation, switching, identifier lookup and local file
transfer. They are not SQL statements accepted by every graphical query editor.
There is no Python execution step. In pgAdmin, connect to the matching database
and run the SQL sections separately; use psql for the complete reproducible run.

## Databases and dependencies

| Script | Database / schema | Dependencies |
|---|---|---|
| 01 locations | `srsp_operational.road_and_facility_locations` | PostGIS |
| 02 multimedia | `srsp_operational.multimedia` | SQL metadata only; S3 service handles files |
| 03 transportation | `srsp_operational.transportation_sensors` | 01, 02 |
| 04 environment | MongoDB `srsp_environment` and `srsp_location_attributes` | Export from 01 |
| 05 citizen requests | `srsp_operational.citizen_service_requests` | 01, 02 |
| 06 maintenance | `srsp_operational.facility_maintenance` | 01, 02, 05 |
| 07 emergency | `srsp_operational.emergency_rules_and_response` | 01, 03, 05 |
| 08 historical | separate `srsp_analytics.historical_planning` | SQL and MongoDB data from earlier scripts |

The operational schemas share one PostgreSQL database. Fully qualified foreign
keys between them are actual constraints. The analytical database is separate:
source UUIDs there are lineage identifiers, not cross-database FKs. Pass custom
names consistently with `psql -v operational_db=NAME -v analytics_db=NAME ...`.
MongoDB database names are explicit in script 04.

## Creation, IDs and CRUD

- `CREATE SCHEMA/TABLE/INDEX IF NOT EXISTS` protects existing SQL structures.
  PostgreSQL has no `CREATE DATABASE IF NOT EXISTS`: scripts 01/08 query
  `pg_database` and use `\gexec` outside a transaction. Run bootstrap serially.
- `IF NOT EXISTS` does not migrate an incompatible table. Such changes require an
  explicit migration. Trigger definitions use `CREATE OR REPLACE`.
- Operational IDs are UUIDs. MongoDB uses their canonical string representation.
  Each SQL table has explicit INSERT, SELECT, UPDATE and DELETE examples with
  concrete IDs. Compound keys use all columns in their WHERE clauses.
- Shared deterministic seeds use `ON CONFLICT DO NOTHING`. Separate disposable
  rows demonstrate CRUD, then are deleted, preserving shared parents. No DROP
  DATABASE/TABLE/COLLECTION or blanket cascading deletion is used.
- City/entity composite FKs prevent mismatched municipalities. Work-order
  inspections must reference the same facility; team/request compatibility is
  checked. Department hierarchies reject cycles. A constrained `camera_type`
  implementation column enforces that camera references identify camera sensors.
- Deleting a referenced parent fails; remove/unlink children first. Current state
  and status history are changed within one transaction and protected by a row
  lock. Published rule versions reject updates; draft versions demonstrate CRUD.
- MongoDB creates missing collections and applies JSON Schema to regular ones.
  Script 01 exports a SQL identifier snapshot to `part3/.runtime/`; script 04
  checks it before creating cross-store references. This is not an atomic
  cross-store constraint: production needs reconciliation and retirement rules.
- MongoDB time-series collections do not support JSON Schema validators or unique
  indexes. Script 04 validates each reading in JavaScript; updates only metadata
  with `updateMany`, and deletes a disposable series. Regular collections use
  insert/update/find/delete. Serial duplicate checks are not concurrent ingestion
  guarantees. Production ingestion needs an idempotency protocol.
- Multimedia SQL performs catalogue CRUD only. Seed metadata remains **pending**;
  no upload is claimed. S3 PutObject/GetObject/DeleteObject belong to the upload
  service, which verifies content and checksum before marking metadata available.
- Script 08 exports SQL sources with client-side `\copy`, and imports staging
  data into the analytical database. Script 04 exports MongoDB summaries to CSV.
  Dimensions load before facts; local FKs and unique fact grains prevent orphans
  and duplicate summaries. Upserts recompute counts rather than adding them again.
- The historical example refreshes 23 October 2026 using America/Toronto dates.
  Metric/unit and currency groups stay separate; missing values remain NULL.
  Production integration also needs watermarks, late arrivals and deletion
  reconciliation. Temporary exports can contain platform data: handle them under
  the same access policy as their sources. They are ignored by Git.
- Sensor/time B-trees and PostGIS GiST indexes are implemented. Time partitioning,
  retention periods and latency targets remain workload/stakeholder decisions.

## References

- [PostgreSQL CREATE SCHEMA](https://www.postgresql.org/docs/16/sql-createschema.html)
- [MongoDB 8 time-series limitations](https://www.mongodb.com/docs/v8.0/core/timeseries/timeseries-limitations/)
- [PostGIS ST_DWithin](https://postgis.net/docs/ST_DWithin.html)

See [VALIDATION.md](VALIDATION.md) for actual test coverage and results.
