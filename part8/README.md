# Part 8 – Final Database Strategy Recommendation

[Read the final recommendation](part8-section.md).

The recommendation is written for a technical manager and contains 845 words.
It integrates architecture, storage/indexing priorities, specialised models,
scalability, retrieval, diverse data types, two principal trade-offs and phased
implementation priorities. It refines the earlier PostgreSQL analytical database recommendation to an AWS
analytical layer: S3 for the data lake, Glue for catalogue and routine integration,
EMR for heavier Spark processing, and Redshift for SQL reporting. New AWS sources
are included in the report's unified References section.

Task 4 still belongs to another group member; align its final indexing choices with
this recommendation. The standalone Conclusion and other submission components
remain separate from Task 8. No measured benchmark or deployment result is claimed.
