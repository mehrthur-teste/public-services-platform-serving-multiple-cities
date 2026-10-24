# Part 5 – Evaluate Storage and Indexing Trade-Offs

| Recommended Strategy | What It Improves | Cost or Limitation | Most Suitable Workload | Impact on Scalability | Future Maintenance |
| --- | --- | --- | --- | --- | --- |
| Relational PostgreSQL with conventional and PostGIS spatial indexes | PKs/FKs preserve relationships among requests, departments, facilities and work orders. Transactions coordinate status/history updates. Indexes accelerate ID, status, date and location searches. | Indexes consume storage and add write overhead. Constraints, joins and concurrent transactions add processing and possible lock contention. | Mixed operational workloads; spatial searches mainly favour reads. | Targeted indexes reduce scans as records grow. Higher write volumes still require capacity and concurrency planning; an index alone does not distribute writes. | Review query plans and index usage; maintain statistics, valid geometries and consistent coordinate systems; plan schema migrations. |
| MongoDB time-series collections for environmental readings | Organises observations by device and time, supporting efficient storage and bounded temporal retrieval. Regular collections retain device configurations and observed events. | Time-series updates and validation are restricted. PostgreSQL identifiers are logical references requiring application checks, not cross-database FKs. | Write-heavy ingestion with time-based reads; measurements seldom change. | Growing observation volumes can use appropriate retention and distribution. Shard keys must suit device/time access and avoid uneven ingestion. | Validate incoming readings; handle duplicates and corrections; review indexes, retention and distribution; reconcile external references. |
| S3 multimedia files with PostgreSQL metadata | Keeps images/videos outside operational tables while retaining searchable metadata and links to requests, inspections and captures. | Object uploads and database updates can fail independently. Downloads add transfer latency and possible request/transfer costs. | Mixed uploads, metadata searches and file retrieval; older evidence is accessed occasionally. | Object storage grows independently of relational processing. Metadata queries and network throughput remain separate capacity concerns. | Track upload states, verify checksums, control access and coordinate retention; reconcile missing objects and unreferenced files. |

## Evaluation of Storage and Indexing Choices

We evaluate three choices from the Part 3 architecture: indexed relational PostgreSQL, MongoDB time-series storage, and S3 files linked to PostgreSQL metadata. These choices serve different access patterns, so their effectiveness depends on the workload. Our comparison considers retrieval improvements, write and coordination costs, scalability, and future maintenance rather than treating any technology as universally preferable.

Relational PostgreSQL suits citizen requests and maintenance because primary and foreign keys preserve relationships, while transactions coordinate changes such as a current status and its history (PostgreSQL Global Development Group, n.d.-a, n.d.-f). Conventional indexes support identifier, status and date filters; PostGIS indexes support location searches using compatible functions (PostGIS Project, n.d.-a). These benefits fit mixed operational workloads and frequent spatial reads. However, indexes occupy space and must be updated when indexed records change, adding write overhead (PostgreSQL Global Development Group, n.d.-b). We therefore favour indexes aligned with actual queries, rather than indexing every field. As volumes grow, query-plan reviews, statistics maintenance, geometry validation and controlled schema migrations remain necessary.

MongoDB time-series collections suit environmental observations arriving continuously from devices. Time and stable metadata organise the series for efficient storage (MongoDB, Inc., n.d.-b). We use device-and-time retrieval to limit the observations examined. The trade-off is reduced flexibility for correcting measurements: time-series collections restrict updates and do not support schema validation rules (MongoDB, Inc., n.d.-c). Consequently, our ingestion service validates readings before insertion, while regular collections retain device configuration and observed events. This is appropriate for a write-heavy workload where measurements rarely change. Retention and suitable shard keys can support growth, but distribution requires planning around ingestion and query patterns. Maintenance also includes duplicate handling, correction procedures and reconciliation of city or facility identifiers owned by PostgreSQL.

S3 separates large multimedia objects from searchable relational metadata. Its object-storage and management capabilities support independent growth of the file repository (Amazon Web Services, n.d.-d). Applications retrieve metadata by media or business-record identifier before requesting the associated object. This fits mixed uploads, searches and downloads, while avoiding large file contents in operational tables. The limitation is coordination across stores. AWS describes the general dual-write risk: one operation can succeed while another fails, creating inconsistent state (Amazon Web Services, n.d.-a). Applied to our file-and-catalogue workflow, this motivates pending, available and failed upload states, checksum verification, retries and reconciliation. Metadata capacity, download throughput and transfer costs must still be monitored.

The three strategies are complementary, but each earns its place through a different trade-off. PostgreSQL prioritises related-record integrity and selective operational retrieval; MongoDB prioritises ongoing temporal ingestion; S3 separates file growth from relational processing. Future maintenance should track query performance, write overhead, storage growth and failed integrations. Capacity and retention targets require workload evidence. These comparisons evaluate effectiveness in the platform’s specific scenarios, directly addressing CLO6 while supporting the storage/indexing and specialised-data objectives in CLO1 and CLO3.

## References

Amazon Web Services. (n.d.-a). *Transactional outbox pattern*. [https://docs.aws.amazon.com/prescriptive-guidance/latest/cloud-design-patterns/transactional-outbox.html](https://docs.aws.amazon.com/prescriptive-guidance/latest/cloud-design-patterns/transactional-outbox.html)

Amazon Web Services. (n.d.-d). *What is Amazon S3?* [https://docs.aws.amazon.com/AmazonS3/latest/userguide/Welcome.html](https://docs.aws.amazon.com/AmazonS3/latest/userguide/Welcome.html)

Fowler, M. (2011, November 16). *Polyglot persistence*. [https://martinfowler.com/bliki/PolyglotPersistence.html](https://martinfowler.com/bliki/PolyglotPersistence.html)

MongoDB, Inc. (n.d.-b). *Time series*. [https://www.mongodb.com/docs/v8.0/core/timeseries-collections/](https://www.mongodb.com/docs/v8.0/core/timeseries-collections/)

MongoDB, Inc. (n.d.-c). *Time series collection limitations*. [https://www.mongodb.com/docs/v8.0/core/timeseries/timeseries-limitations/](https://www.mongodb.com/docs/v8.0/core/timeseries/timeseries-limitations/)

PostGIS Project. (n.d.-a). *How do I use spatial indexes?* [https://postgis.net/documentation/faq/spatial-indexes/](https://postgis.net/documentation/faq/spatial-indexes/)

PostgreSQL Global Development Group. (n.d.-a). *Constraints*. PostgreSQL 16 documentation. [https://www.postgresql.org/docs/16/ddl-constraints.html](https://www.postgresql.org/docs/16/ddl-constraints.html)

PostgreSQL Global Development Group. (n.d.-b). *Introduction*. PostgreSQL 16 documentation. [https://www.postgresql.org/docs/16/indexes-intro.html](https://www.postgresql.org/docs/16/indexes-intro.html)

PostgreSQL Global Development Group. (n.d.-f). *Transactions*. PostgreSQL 16 documentation. [https://www.postgresql.org/docs/16/tutorial-transactions.html](https://www.postgresql.org/docs/16/tutorial-transactions.html)

Vazquez, C. E., & Simões, G. S. (2016). *Engenharia de requisitos*. Brasport.
