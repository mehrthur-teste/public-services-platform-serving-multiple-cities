# Part 4 – Index Selection and Validation

Table 1 presents indexing strategies for eight Smart Regional Services Platform retrieval scenarios. We reuse matching Part 3 indexes and propose targeted additions for an ordered citizen backlog, geometry containment, environmental threshold searches and an urgent alert queue. Each recommendation connects an access pattern with its retrieval benefit and maintenance cost.

Table 1

Recommended Indexing Strategies for the Smart Regional Services Platform

| Retrieval scenario | Table / collection | Search condition / access pattern | Recommended index fields | Supported access type | Retrieval benefit | Trade-off / maintenance cost |
| --- | --- | --- | --- | --- | --- | --- |
| 1. Find open citizen requests in a city, showing creation date/time, oldest first. | service_requests (PostgreSQL) | Match city_id and status IN ('submitted', 'triaged', 'assigned', 'in_progress'). Return created_at; ORDER BY created_at ASC, request_id ASC. | Propose partial B-tree (city_id, created_at, request_id) WHERE status IN the four active values. Existing request_queue_idx supports filtering with a separate sort. | Equality on city; active-status subset; chronological retrieval. | The partial index groups active requests by city in creation order and supports stable timestamp ties. It can avoid the global sort needed with the existing city/status/department/date index. | Add only if backlog retrieval is frequent and selective. Extra storage and writes accompany inserts/deletes and transitions into or out of active statuses. Retain the general queue index for its separate workload. |
| 2. Retrieve one traffic sensor’s readings during a selected period, newest first. | traffic_readings (PostgreSQL) | Match sensor_id; recorded_at >= :start_time AND recorded_at < :end_time. ORDER BY recorded_at DESC. | Reuse traffic_sensor_time_idx: composite B-tree (sensor_id, recorded_at DESC). | Equality; temporal range; ordered retrieval. | Locates one sensor’s entries and scans the requested time interval in descending order. Reduces irrelevant history scans and can avoid a separate sort. | Each incoming reading adds an index entry, increasing storage and ingestion work. Time partitioning remains an option to evaluate, rather than an implemented feature. |
| 3. Find facilities in a selected zone, nearest to farthest from a selected or incident location. | facilities; service_zones (PostGIS) | Match zone_id/city; ST_Covers(z.boundary, f.location). Calculate ST_Distance using geography and the selected point. Return metres; sort by distance, then facility_id. | Add GiST (location) on facilities. Reuse the service_zones primary-key B-tree (zone_id) to select the zone. | Equality; spatial containment; distance-ordered retrieval. | The zone key and proposed geometry GiST reduce containment candidates before exact checks. Distances are calculated for matching facility points, then explicitly sorted (PostGIS Project, n.d.-b, n.d.-c). | The geometry index adds storage and location-update work. Distance calculation and sorting still cost CPU/memory; the containment index does not remove that sort. Existing geography indexing serves other distance patterns. |
| 4. Retrieve a facility’s work orders created during the last two years, newest first. | work_orders (PostgreSQL) | Match facility_id; created_at >= :as_of minus two years AND created_at <= :as_of. ORDER BY created_at DESC. Include all work-order statuses. | Reuse work_facility_time_idx: composite B-tree (facility_id, created_at DESC). | Equality; temporal range; ordered retrieval. | Narrows retrieval to one facility and the required creation-date interval. Can return matching work orders newest first without a separate sort. | Consumes storage and requires maintenance for inserts, deletes and indexed-field changes. Completion-date or inspection-date searches require a separately matched access path. |
| 5. Retrieve available multimedia evidence attached to one citizen request. | request_media; media_assets (PostgreSQL); files in S3 | Match request_id; join on media_id; filter upload_status = 'available'. Use the returned bucket/key for authorised S3 retrieval. | Reuse primary-key B-trees: request_media (request_id, media_id) and media_assets (media_id). No additional index is required. | Equality; indexed join; availability filtering. | Finds attachment links by request and supports direct metadata lookups by media ID. Checks availability on matching assets before returning file references. | Existing key indexes consume storage and require maintenance on inserts/deletes. Their reuse adds no new index cost. S3 transfer time and metadata/object reconciliation remain separate concerns. |
| 6. Find valid environmental readings above a threshold for one metric and unit in a city during a selected period. | environmental_ readings (MongoDB time-series) | Match metadata.city_id, metadata.metric and metadata.unit; recorded_at in [start, end); value > :threshold; quality_status = 'valid'. | Propose compound index: metadata.city_id: 1; metadata.metric: 1; metadata.unit: 1; recorded_at: -1. Retain device_time_idx for per-device retrieval. | Metadata equality; temporal range; threshold filtering. | Narrows candidate buckets by city, metric, unit and time before checking individual values and quality. Threshold and quality remain residual filters (MongoDB, Inc., n.d.-d). | An additional index increases bucket-index storage and ingestion work. Large time windows still examine many readings; confirm selectivity before adoption. It does not enforce reading uniqueness. |
| 7. Retrieve unacknowledged urgent emergency alerts, oldest first, for prompt operator attention. | alerts (PostgreSQL) | status = 'open' AND priority = 'urgent'; ORDER BY triggered_at ASC LIMIT :page_size. Keep these two status/priority values explicit in the query. | Propose partial B-tree on (triggered_at) WHERE status = 'open' AND priority = 'urgent'. Existing alert_queue_idx supports the general status queue. | Equality on status/priority; ordered retrieval from a partial index. | If open urgent alerts are a small subset, indexes only that queue and supports oldest-first retrieval without scanning other priorities. The query must imply the index predicate (PostgreSQL Global Development Group, n.d.-e). | Adopt only for a frequent, selective urgent queue. Status/priority changes add or remove entries; bursts can reduce selectivity. The general queue index still needs maintenance. |
| 8. Locate active environmental monitoring devices near an incident, nearest first. | monitoring_ devices (MongoDB regular collection) | Use location.$near with a GeoJSON incident point and $maxDistance in metres; filter status = 'active'; limit results. Coordinates use longitude, latitude. | Reuse device_location_geo: {location: '2dsphere'}. The index covers device positions, not the time-series readings. | Spatial proximity; distance-ordered retrieval; status filtering. | Supports spherical proximity search and nearest-first results, then retains active devices. Reuses a different spatial access method from PostGIS zone containment (MongoDB, Inc., n.d.-a, n.d.-e). | Consumes storage and requires maintenance when devices move or are inserted/deleted. Status is a residual filter; many nearby inactive devices can increase work. Missing locations have no spatial index entry. |

Note. GiST = Generalized Search Tree; DESC = descending order; S3 = Amazon Simple Storage Service.

## Index Design Rationale

Composite key order follows the query: equality fields lead the time range in scenarios 2 and 4. In scenario 1, the existing city/status queue index filters active requests but does not supply a global creation-date order. The proposed partial index leads with city and creation time and adds request_id for stable ties; adopt it when workload evidence justifies another index (PostgreSQL Global Development Group, n.d.-d, n.d.-e). Scenario 5 reuses primary-key indexes (PostgreSQL Global Development Group, n.d.-a). In scenario 3, GiST supports containment filtering, while geographic distance in metres is calculated and sorted separately. Neither query requires an index on every returned field.

Validate proposed additions with representative city sizes, time windows and write rates. Compare query plans, rows or buckets examined, sorting, index size and ingestion cost. Use PostgreSQL EXPLAIN (ANALYZE, BUFFERS) for read queries and MongoDB explain("executionStats"). Retain additions only when retrieval gains justify maintenance; broad result sets may favour scans. These are design recommendations, not measured performance results. The scenarios use operational stores; the final Redshift analytical recommendation requires its own physical design.

## Example Retrieval Queries

The six SQL and two mongosh examples use replaceable sample inputs. SQL targets srsp_operational; MongoDB targets srsp_environment. The queries and proposed indexes require server-side validation.

## Scenario 1: Open Requests in a City From Oldest to Newest

```sql
SELECT
    request_id,
    tracking_number,
    status,
    department_id,
    created_at
FROM citizen_service_requests.service_requests
WHERE city_id = UUID '00000000-0000-0000-0000-000000000001'
  AND status IN (
      'submitted',
      'triaged',
      'assigned',
      'in_progress'
  )
ORDER BY created_at ASC, request_id ASC;
```

Returns creation date/time; request_id breaks timestamp ties. The existing queue index filters but needs a global sort. The proposed active-request partial index (city_id, created_at, request_id) can support the requested order when justified by workload.

## Scenario 2: Sensor Readings During a Period

```sql
SELECT
    reading_id,
    recorded_at,
    measurement_type,
    numeric_value,
    unit
FROM transportation_sensors.traffic_readings
WHERE sensor_id = UUID '00000000-0000-0000-0000-000000000015'
  AND recorded_at >= TIMESTAMPTZ '2026-10-23 00:00:00+00'
  AND recorded_at <  TIMESTAMPTZ '2026-10-24 00:00:00+00'
ORDER BY recorded_at DESC;
```

Matches traffic_sensor_time_idx(sensor_id, recorded_at DESC). The exclusive end avoids overlap between consecutive periods.

## Scenario 3: Facilities in a Zone From Nearest to Farthest

```sql
SELECT
    f.facility_id,
    f.name,
    f.facility_type,
    ST_Distance(
        f.location::geography,
        'SRID=4326;POINT(-79.3832 43.6532)'::geography
    ) AS distance_metres
FROM road_and_facility_locations.service_zones AS z
JOIN road_and_facility_locations.facilities AS f
    ON f.city_id = z.city_id
   AND ST_Covers(z.boundary, f.location)
WHERE z.zone_id = UUID '00000000-0000-0000-0000-000000000005'
ORDER BY distance_metres ASC, f.facility_id ASC;
```

Replace the sample longitude/latitude with the selected or incident location. ST_Covers includes boundary points and the city condition preserves zone ownership. The proposed GiST(location) filters spatial candidates; ST_Distance on geography calculates spheroidal distance in metres, followed by an explicit sort. This is geographic distance, not driving distance. facility_id breaks distance ties consistently.

## Scenario 4: Facility Work Orders Over Two Years

```sql
SELECT
    work_order_id,
    status,
    maintenance_type,
    created_at
FROM facility_maintenance.work_orders
WHERE facility_id = UUID '00000000-0000-0000-0000-000000000003'
  AND created_at >=
      TIMESTAMPTZ '2026-10-24 00:00:00+00' - INTERVAL '2 years'
  AND created_at <= TIMESTAMPTZ '2026-10-24 00:00:00+00'
ORDER BY created_at DESC;
```

Matches work_facility_time_idx(facility_id, created_at DESC). The fixed as-of instant makes the example repeatable; replace both occurrences together. All statuses are included.

## Scenario 5: Available Evidence for a Request

```sql
SELECT
    m.media_id,
    rm.evidence_role,
    m.media_type,
    m.original_filename,
    m.storage_bucket,
    m.storage_key
FROM citizen_service_requests.request_media AS rm
JOIN multimedia.media_assets AS m
    ON m.media_id = rm.media_id
WHERE rm.request_id = UUID '00000000-0000-0000-0000-00000000001f'
  AND m.upload_status = 'available';
```

Reuses request_media(request_id, media_id) and media_assets(media_id) primary-key indexes. Availability is checked on matching metadata; the application authorises S3 access. Part 3 seed uploads remain pending, so an empty result is expected until verified uploads are available.

## Scenario 6: Environmental Readings Above a Threshold

```javascript
db.getSiblingDB("srsp_environment").environmental_readings.find(
  {
    "metadata.city_id": "00000000-0000-0000-0000-000000000001",
    "metadata.metric": "temperature",
    "metadata.unit": "degC",
    recorded_at: {
      $gte: ISODate("2026-10-23T00:00:00Z"),
      $lt: ISODate("2026-10-24T00:00:00Z")
    },
    value: { $gt: 20 },
    quality_status: "valid"
  },
  {
    _id: 0,
    reading_id: 1,
    recorded_at: 1,
    value: 1,
    metadata: 1
  }
);
```

Illustrates a temperature threshold of 20 degrees Celsius, not an emergency policy. The proposed city/metric/unit/time index narrows candidate buckets; value and quality remain residual filters.

## Scenario 7: Unacknowledged Urgent Alerts

```sql
SELECT
    alert_id,
    source_context,
    source_event_id,
    triggered_at
FROM emergency_rules_and_response.alerts
WHERE status = 'open'
  AND priority = 'urgent'
ORDER BY triggered_at ASC
LIMIT 50;
```

The literal status/priority conditions match the proposed partial index predicate. It supports the oldest-first queue when the subset is selective. LIMIT 50 gives one result batch; repeated polling requires application claim/acknowledgement handling.

## Scenario 8: Active Devices Near an Incident

```javascript
db.getSiblingDB("srsp_environment").monitoring_devices.find(
  {
    status: "active",
    location: {
      $near: {
        $geometry: {
          type: "Point",
          coordinates: [-79.3832, 43.6532]
        },
        $maxDistance: 2000
      }
    }
  },
  {
    _id: 1,
    city_id: 1,
    location: 1,
    status: 1
  }
).limit(20);
```

Reuses device_location_geo on location (2dsphere). The example returns at most 20 active devices within 2,000 metres, nearest first; no additional sort is needed. Status is not part of this index.

## References

References are consolidated in the main Word report. Date suffixes match that bibliography.

MongoDB, Inc. (n.d.-a). $near (query predicate operator). https://www.mongodb.com/docs/v8.0/reference/operator/query/near/
MongoDB, Inc. (n.d.-d). Time series indexes. https://www.mongodb.com/docs/v8.0/core/timeseries/timeseries-index/
MongoDB, Inc. (n.d.-e). 2dsphere indexes. https://www.mongodb.com/docs/v8.0/core/indexes/index-types/geospatial/2dsphere/
PostGIS Project. (n.d.-b). ST_Covers. https://postgis.net/docs/ST_Covers.html
PostGIS Project. (n.d.-c). ST_Distance. https://postgis.net/docs/ST_Distance.html
PostgreSQL Global Development Group. (n.d.-a). Constraints. PostgreSQL 16 documentation. https://www.postgresql.org/docs/16/ddl-constraints.html
PostgreSQL Global Development Group. (n.d.-d). Multicolumn indexes. PostgreSQL 16 documentation. https://www.postgresql.org/docs/16/indexes-multicolumn.html
PostgreSQL Global Development Group. (n.d.-e). Partial indexes. PostgreSQL 16 documentation. https://www.postgresql.org/docs/16/indexes-partial.html
