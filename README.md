# Smart Regional Services Platform

Group 3 working report for MCAI510 Take Home Assignment 1.

## Report and section guides

- [Word report — Parts 1–8](MCAI510_THA1_Group3_Report.docx)
- [Final PDF report](MCAI510_THA1_Group3_Report.pdf)
- [Parts 1 and 2 — Markdown review copy](docs/report-draft.md)
- [Part 3 — native database scripts and execution instructions](part3/README.md)
- [Part 3 — storage and retrieval table, justification and CRUD examples](part3/part3-section.md)
- [Part 3 — validation scope and results](part3/VALIDATION.md)
- [Part 3 — download the eight database scripts](part3/Part_3_Database_Scripts.zip)
- [Part 4 — indexing strategies guide](part4/README.md)
- [Part 4 — eight scenarios and retrieval queries](part4/part4-section.md)
- [Part 5 — trade-off evaluation guide](part5/README.md)
- [Part 5 — comparative table, justification and references](part5/part5-section.md)
- [Part 6 — specialised database models guide](part6/README.md)
- [Part 6 — seven-category table, justification and references](part6/part6-section.md)
- [Part 7 — processing paradigms guide](part7/README.md)
- [Part 7 — eight-paradigm comparison and explanation](part7/part7-section.md)
- [Part 8 — final strategy recommendation guide](part8/README.md)
- [Part 8 — final recommendation and implementation priorities](part8/part8-section.md)

The report contains requirements analysis, the architecture recommendation,
storage and retrieval strategies, the evaluation of storage/indexing trade-offs,
specialised database model recommendations, and a comparison of contemporary
data processing paradigms. Part 8 brings these decisions together in the final
database strategy recommendation, refining the analytical layer to S3, AWS Glue,
Amazon EMR and Amazon Redshift.
Part 3 supplies seven PostgreSQL SQL scripts and one native MongoDB script.
Part 5 compares relational PostgreSQL/PostGIS, MongoDB time-series collections,
and S3 multimedia files with PostgreSQL metadata. Part 6 explains specialised
approaches for all seven categories in the assignment. Part 7 compares all eight
listed paradigms and assigns each one a defined architectural role. Part 8 sets
priorities, identifies the two main trade-offs and outlines a phased rollout.

The Word file controls document formatting. Use the section Markdown files for
review comments. The Markdown copy under `docs/` covers Parts 1 and 2 only;
exported figures remain in `docs/figures`.

## Remaining group work

All eight numbered tasks, the Conclusion, group contribution and AI usage statements,
and student IDs are included. The final PDF is available above. Part 4 integrates
the group member’s eight operational indexing scenarios and retrieval queries. Database syntax checks are documented separately from
server-side execution; complete integration runs have not been claimed.

## Report appendices

The main report retains all eight tasks and their required tables and justifications.
Technical material follows References: Appendix A contains workflows, schemas and
data dictionaries; Appendix B contains relationship diagrams; Appendix C contains
implementation instructions, the linked scripts table and CRUD; Appendix D contains
the eight complete indexing retrieval queries. Internal links point to numbered
sections, tables and figures. Detailed schemas, diagrams and database examples are
retained in the appendices; selected main-text explanations have been condensed.
