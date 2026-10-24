# Part 8 – Final Database Strategy Recommendation

We recommend a cloud-hosted platform combining PostgreSQL, PostGIS and MongoDB for operations with an AWS analytical layer using S3, Glue, EMR and Redshift. This final recommendation refines the earlier PostgreSQL analytical database proposal. PostgreSQL remains the operational foundation; shared schemas preserve relationships without requiring a server per department. Complementary technologies should follow workload needs and integration costs (Kleppmann, 2017).

Operational PostgreSQL schemas should share stable UUIDs for cities, roads, facilities, requests, work orders and evidence. Within the shared operational database, primary keys, unique constraints and foreign keys preserve relationships across schemas. Transactions must coordinate related changes, especially current status and its history (PostgreSQL Global Development Group, n.d.-a, n.d.-f). Services should validate permitted state transitions, apply city-scoped access controls and expose authorised retrieval through APIs. MongoDB identifiers and analytical lineage identifiers reference their authoritative sources through validated integration contracts; they are not cross-database foreign keys. This ownership model supports accountable municipal operations and consistent retrieval.

The most important retrieval choices are indexes aligned with recurring searches. Use primary and unique indexes for record identifiers and public tracking numbers, composite indexes for city/status/department queues, sensor/time indexes for bounded observation periods, and facility/time indexes for maintenance histories. PostGIS GiST indexes should match the spatial expressions used for proximity, containment and intersection searches (PostGIS Project, n.d.-a). Query parameters should include relevant identifiers and time boundaries, while list endpoints use pagination. Introduce additional indexes only when representative query plans justify them, because indexes consume storage and add work during writes (PostgreSQL Global Development Group, n.d.-b).

Different data types require complementary management approaches. PostGIS stores geometry and coordinate-system information. Normalised request and maintenance tables retain operational relationships, with recursive queries for department hierarchies and controlled JSONB extensions only where variable attributes justify them. MongoDB regular collections hold environmental devices and observed events; time-series collections hold measurements organised by device and time. The ingestion service must validate metrics, units and quality flags and handle repeated deliveries, since time-series collection restrictions require explicit correction and validation policies (MongoDB, Inc., n.d.-b, n.d.-c). Transportation observations retain the PostgreSQL design already selected.

Multimedia contents should remain in S3, with PostgreSQL storing metadata, checksums, upload states and evidence links. Applications search the catalogue before retrieving an authorised object. S3 supports scalable object storage, but upload completion and database availability must be coordinated (Amazon Web Services, n.d.-d). Maintain pending, available and failed states, and reconcile incomplete transfers. A separate rule-evaluation service should consume relevant events, select an approved effective policy version and record deduplicated alerts and response actions. Database triggers should enforce local invariants. Queues and workers support prompt ingestion and reactions.

For analytics, incremental extracts from PostgreSQL and MongoDB should land in a dedicated S3 data lake, separated from operational evidence files. Retain raw inputs and publish validated Parquet datasets partitioned by useful dates and cities. AWS Glue should catalogue schemas and run routine integration and cleansing jobs (Amazon Web Services, n.d.-e). Use Spark on Amazon EMR for heavier historical joins, sensor aggregation and reprocessing; assign each transformation to Glue or EMR to avoid duplicate work (Amazon Web Services, n.d.-b). Load curated dimensions and facts into Amazon Redshift for SQL reporting and BI access (Amazon Web Services, n.d.-c; Kimball & Ross, 2013). Display the latest successful refresh time and preserve source identifiers for traceability. Redshift serves analytical queries while operational APIs continue using their source databases.

Scalability should come from separating workloads and expanding the components under pressure. Ingestion workers can scale independently, queues buffer temporary bursts, and object storage grows separately from the metadata catalogue. Environmental distribution and transportation time partitioning should be evaluated against measured volumes and query patterns. S3 storage, EMR processing and Redshift query capacity should scale separately from operational workloads. Use scheduled jobs, suitable file sizes and measured Redshift query plans to control cost and retrieval latency. Shared identifiers, explicit fact grains and unit/currency separation preserve meaning as additional cities and devices join.

The first major trade-off is workload-specific storage versus integration complexity. The operational stores and AWS analytical services fit different workloads, but introduce independent failures, reference reconciliation, pipeline delays, cloud costs and additional operational expertise. Mitigate this through clear ownership, durable identifiers, idempotent consumers and monitored recovery procedures. The second is retrieval performance versus write and maintenance overhead. Indexes, derived summaries and potential partitions reduce selected retrieval costs, while increasing storage, refresh work and design responsibilities. Control this through selective indexing, bounded queries, retention policies and measured analytical refresh schedules. Neither trade-off is resolved by adding technology without measuring its effect.

If implementation capacity is limited, prioritise shared locations, operational PostgreSQL, requests and maintenance workflows, and the evidence catalogue with reliable S3 uploads. Establish access controls, backup restoration and essential monitoring alongside these foundations. Next, implement durable sensor ingestion, MongoDB environmental storage and governed emergency evaluation, prioritising the most consequential operational scenarios. Then establish S3 landing zones and the Glue catalogue, implement essential transformations, and load a small Redshift reporting model. Add EMR processing as heavier workloads emerge, after source identifiers, units and histories are reliable. Optional location documents, advanced content search, sharding and time partitioning should follow demonstrated needs.

## References

Amazon Web Services. (n.d.-b). [*What is Amazon EMR?*](https://docs.aws.amazon.com/emr/latest/ManagementGuide/emr-what-is-emr.html).

Amazon Web Services. (n.d.-c). [*What is Amazon Redshift?*](https://docs.aws.amazon.com/redshift/latest/mgmt/welcome.html).

Amazon Web Services. (n.d.-d). [*What is Amazon S3?*](https://docs.aws.amazon.com/AmazonS3/latest/userguide/Welcome.html).

Amazon Web Services. (n.d.-e). [*What is AWS Glue?*](https://docs.aws.amazon.com/glue/latest/dg/what-is-glue.html).

Kimball, R., & Ross, M. (2013). *The data warehouse toolkit: The definitive guide to dimensional modeling* (3rd ed.). Wiley.

Kleppmann, M. (2017). *Designing data-intensive applications: The big ideas behind reliable, scalable, and maintainable systems*. O’Reilly Media.

MongoDB, Inc. (n.d.-b). [*Time series*](https://www.mongodb.com/docs/v8.0/core/timeseries-collections/).

MongoDB, Inc. (n.d.-c). [*Time series collection limitations*](https://www.mongodb.com/docs/v8.0/core/timeseries/timeseries-limitations/).

PostGIS Project. (n.d.-a). [*How do I use spatial indexes?*](https://postgis.net/documentation/faq/spatial-indexes/).

PostgreSQL Global Development Group. (n.d.-a). [*Constraints*](https://www.postgresql.org/docs/16/ddl-constraints.html). PostgreSQL 16 documentation.

PostgreSQL Global Development Group. (n.d.-b). [*Introduction*](https://www.postgresql.org/docs/16/indexes-intro.html). PostgreSQL 16 documentation.

PostgreSQL Global Development Group. (n.d.-f). [*Transactions*](https://www.postgresql.org/docs/16/tutorial-transactions.html). PostgreSQL 16 documentation.
