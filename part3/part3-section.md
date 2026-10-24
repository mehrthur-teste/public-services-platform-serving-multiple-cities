# Part 3 – Develop a Storage and Retrieval Strategy

| Data Source | Data Stored | Creation / Update Frequency | Retrieval Method | Retrieval Frequency / Timing | Primary Storage Purpose | Storage / Retrieval Strategy | Performance Risk |
| --- | --- | --- | --- | --- | --- | --- | --- |
| ROAD_AND_FACILITY_LOCATIONS | Cities, roads, facilities, service zones; geometries and optional attributes. | On infrastructure changes; occasional attribute corrections. | By UUID, city, distance, or zone intersection. | Frequent map and operational lookups. | Operational processing. | PostGIS geometries; matching GiST indexes; city indexes. Optional MongoDB documents share UUIDs. | Full spatial scans; mismatched index expressions; dangling cross-store references. |
| MULTIMEDIA | Images/videos in S3; SQL metadata, checksum, upload state and evidence links. | Per upload; state changes after verification; occasional corrections. | Metadata by media or business-record ID; authorised object retrieval by bucket/key. | On demand; older evidence retrieved occasionally. | Long-term archiving and evidence access. | S3 files plus PostgreSQL catalogue; PK/unique bucket-key; verify upload before availability. | Large transfers delay access; database BLOB growth; metadata/object inconsistency. |
| TRANSPORTATION_SENSORS | Installations, sensors, readings, transit arrivals, captures and media links. | Readings every few seconds; configuration updated occasionally. | By sensor and time range; join installation to road; transit by stop/time. | Frequent monitoring and historical extraction. | Operational processing. | PostgreSQL; sensor/time indexes; source-event deduplication; JSONB configuration. Evaluate partitioning as volume grows. | Write amplification; unbounded history scans; duplicate ingestion. |
| ENVIRONMENTAL_MONITORING | Device documents, metric/unit readings, quality flags and observed events. | Continuous readings; occasional configuration/event updates. | By device, metric and time; devices by geographic proximity. | Near-real-time monitoring and historical trends. | Operational processing. | MongoDB regular device/event collections; time-series readings indexed by device/time; application validation. | Oversized scans; poor bucketing; duplicate readings; unsupported time-series update patterns. |
| CITIZEN_SERVICE_REQUESTS | Requests, departments, priorities, assignments, status history and media links. | Each citizen report; updates during triage and resolution. | By request UUID/tracking number; queues by city, status and department. | Frequent during service delivery. | Operational processing. | PostgreSQL transactions; PK/unique tracking number; queue index; row lock and atomic status/history changes. | Slow queues; lost updates; inconsistent current state and history. |
| FACILITY_MAINTENANCE | Inspections, work orders, teams, costs, equipment usage and evidence links. | Per inspection/order; updated during work; costs as incurred. | By facility, order, team, status or period; costs by currency. | Frequent operations; occasional facility-history reviews. | Operational processing. | PostgreSQL FKs across shared schemas; facility/time and status indexes; transactional progress history. | Slow joins; contention; orphaned costs; incorrect totals across currencies. |
| EMERGENCY_RULES_AND_RESPONSE | Policies, immutable approved versions, alerts, actions and escalation history. | Rules change occasionally; alerts/actions arrive on events. | Effective approved rules by scope; alerts by status/time; history by alert ID. | Event-driven, with prompt queue retrieval. | Operational processing. | PostgreSQL versioned rules and unique evaluation keys; external evaluation service; indexed alert queue. | Duplicate alerts; burst backlog; evaluating stale/unapproved rules. |
| HISTORICAL_PLANNING | Date/city/facility dimensions; daily traffic, environmental, service and cost facts. | Scheduled daily refresh; rerun affected dates for corrections. | By reporting period, city, road, category, facility, metric/unit or currency. | Scheduled dashboards and occasional historical analysis. | Analytical processing. | Separate PostgreSQL database; load dimensions first; unique fact grains and idempotent upserts. | Reporting competes with operations if combined; duplicated facts; stale or incomparable aggregates. |

## Storage and Retrieval Justification

We selected all eight sources because the platform combines structured transactions, temporal observations, geographic searches, files and historical analysis. Each source requires a storage approach that matches how records arrive and how applications retrieve them. We retain the technologies chosen in Part 2: PostgreSQL for operational records, PostGIS for geographic data, MongoDB for environmental information and optional location attributes, S3 for files, and a separate PostgreSQL analytical database.

Locations provide shared identifiers for the other operational contexts. PostGIS stores points, road lines and service-zone polygons, while spatial indexes support nearby-facility and intersection queries. The distance example uses a geography expression index matching its query expression so distances are measured in metres. Optional MongoDB attribute documents reuse the relational UUID as their document identifier. The MongoDB script checks an exported SQL identifier snapshot before creating a document.

Citizen requests and maintenance records need reliable relationships and coordinated updates. Their schemas share the operational PostgreSQL database, allowing actual foreign keys between requests, departments, facilities, inspections and work orders. Composite references also check municipality or facility consistency where relevant. Status changes lock the current row and record the corresponding history within one transaction. Queue and facility-history indexes support common retrieval patterns, while monetary summaries remain separated by currency.

Transportation readings arrive much more often than device configurations change. We index sensor identifiers with observation timestamps and retrieve bounded time ranges, avoiding unnecessary scans of the complete history. Source-event uniqueness prevents repeated SQL ingestion. Monthly partitioning remains a volume-driven extension rather than an implemented requirement. Environmental readings use a MongoDB time-series collection, with regular collections for device configuration and observed events. Because time-series validation and updates have restrictions, the script validates measurements before insertion and demonstrates updates only to series metadata.

Multimedia separates large file contents from searchable metadata. S3 stores the objects, while PostgreSQL records identifiers, storage keys, checksums and upload states. Files become available only after successful transfer and verification. Request, inspection and capture linking tables preserve the business context. PostgreSQL and S3 cannot commit atomically together, so failures require visible states, retries and reconciliation. The same limitation applies to references crossing PostgreSQL and MongoDB; an application check is not a distributed foreign key.

Emergency response stores approved rule versions and links each alert to the exact version evaluated. An external service performs evaluation; unique evaluation keys prevent duplicate alerts. Historical planning instead loads shared dimensions before daily facts in a separate database. Idempotent upserts preserve each fact grain, reporting dates use one documented timezone, and environmental units remain explicit. This separation protects operational work from broad reporting scans. Native SQL and mongosh scripts demonstrate CRUD while retaining shared examples for later contexts. Retention periods, ingestion capacity and latency targets require stakeholder validation and workload measurements before production deployment.

## Script Repository and Execution Order

The eight executable scripts are published in the [project repository](https://github.com/mehrthur-teste/public-services-platform-serving-multiple-cities), under [`part3/scripts`](https://github.com/mehrthur-teste/public-services-platform-serving-multiple-cities/tree/main/part3/scripts) on the `main` branch (mehrthur-teste, n.d.).

| Order | Context | Executable script |
| --- | --- | --- |
| 01 | Locations | [01_road_and_facility_locations.sql](https://github.com/mehrthur-teste/public-services-platform-serving-multiple-cities/blob/main/part3/scripts/01_road_and_facility_locations.sql) |
| 02 | Multimedia | [02_multimedia.sql](https://github.com/mehrthur-teste/public-services-platform-serving-multiple-cities/blob/main/part3/scripts/02_multimedia.sql) |
| 03 | Transportation | [03_transportation_sensors.sql](https://github.com/mehrthur-teste/public-services-platform-serving-multiple-cities/blob/main/part3/scripts/03_transportation_sensors.sql) |
| 04 | Environment | [04_environmental_monitoring.js](https://github.com/mehrthur-teste/public-services-platform-serving-multiple-cities/blob/main/part3/scripts/04_environmental_monitoring.js) |
| 05 | Citizen requests | [05_citizen_service_requests.sql](https://github.com/mehrthur-teste/public-services-platform-serving-multiple-cities/blob/main/part3/scripts/05_citizen_service_requests.sql) |
| 06 | Maintenance | [06_facility_maintenance.sql](https://github.com/mehrthur-teste/public-services-platform-serving-multiple-cities/blob/main/part3/scripts/06_facility_maintenance.sql) |
| 07 | Emergency response | [07_emergency_rules_and_response.sql](https://github.com/mehrthur-teste/public-services-platform-serving-multiple-cities/blob/main/part3/scripts/07_emergency_rules_and_response.sql) |
| 08 | Historical planning | [08_historical_planning.sql](https://github.com/mehrthur-teste/public-services-platform-serving-multiple-cities/blob/main/part3/scripts/08_historical_planning.sql) |

## Road and Facility Locations

PostGIS stores core geography; optional MongoDB attribute documents use the same UUID and are validated against SQL parents.

```sql
-- CREATE a facility linked to an existing city
INSERT INTO road_and_facility_locations.facilities
 (facility_id, city_id, name, facility_type, status, location)
VALUES (:facility_id, :city_id, 'Demo park', 'park',
 'operational', ST_SetSRID(ST_MakePoint(-79.38,43.65),4326));

-- READ facilities within 1 kilometre
SELECT facility_id, name
FROM road_and_facility_locations.facilities
WHERE ST_DWithin(location::geography,
 ST_SetSRID(ST_MakePoint(-79.38,43.65),4326)::geography,1000);

-- UPDATE descriptive information
UPDATE road_and_facility_locations.facilities
SET name='Reviewed park', updated_at=now()
WHERE facility_id=:facility_id;

-- DELETE only an unreferenced demonstration facility
DELETE FROM road_and_facility_locations.facilities
WHERE facility_id=:facility_id;
```

## Multimedia

The SQL script implements catalogue CRUD. Seed metadata remains pending because no object is uploaded by SQL. The upload service performs S3 PutObject, GetObject and DeleteObject, then verifies the checksum before marking a file available.

```sql
-- CREATE metadata before uploading the S3 object
INSERT INTO multimedia.media_assets
 (media_id,media_type,mime_type,original_filename,size_bytes,
 source_channel,storage_bucket,storage_key,upload_status)
VALUES (:media_id,'image','image/png','evidence.png',:size,
 'citizen_portal',:bucket,:object_key,'pending');

-- READ the catalogue entry
SELECT media_id,storage_bucket,storage_key,upload_status
FROM multimedia.media_assets WHERE media_id=:media_id;

-- UPDATE only after successful upload and checksum verification
UPDATE multimedia.media_assets
SET upload_status='available',checksum_sha256=:checksum
WHERE media_id=:media_id;

-- Before file deletion, mark unavailable and unlink consumers.
-- Delete the S3 object, then DELETE its disposable metadata.
DELETE FROM multimedia.media_assets WHERE media_id=:media_id;
```

## Transportation Sensors

A reading belongs to a sensor, which belongs to a monitoring unit and road. Source-event uniqueness prevents duplicate ingestion. The full script includes transit and camera evidence.

```sql
-- CREATE a reading for an existing sensor
INSERT INTO transportation_sensors.traffic_readings
 (reading_id,sensor_id,source_event_id,recorded_at,
 measurement_type,numeric_value,unit)
VALUES (:reading_id,:sensor_id,:source_event_id,:recorded_at,
 'speed',62.5,'km/h');

-- READ a bounded sensor history
SELECT recorded_at,numeric_value,unit
FROM transportation_sensors.traffic_readings
WHERE sensor_id=:sensor_id
 AND recorded_at>=:start_time AND recorded_at<:end_time
ORDER BY recorded_at DESC LIMIT 100;

-- UPDATE a corrected disposable reading
UPDATE transportation_sensors.traffic_readings
SET numeric_value=61.0 WHERE reading_id=:reading_id;

-- DELETE after removing any dependent capture links/events
DELETE FROM transportation_sensors.traffic_readings
WHERE reading_id=:reading_id;
```

## Environmental Monitoring

The native mongosh script creates and validates regular collections and creates the time-series collection. It implements device/event CRUD and reading insertion, bounded retrieval, metadata update and temporary-series deletion. Optional location-attribute CRUD is included in the same file.

```javascript
// CREATE a regular device document
const env = db.getSiblingDB('srsp_environment');
env.monitoring_devices.insertOne({
 _id: deviceId, city_id: cityId,
 location: {type:'Point',coordinates:[-79.3832,43.6532]},
 status:'active',
 configuration:{sampling_interval_seconds:10,
  metrics:[{metric:'temperature',unit:'degC'}]},
 updated_at:new Date()
});

// READ
 env.monitoring_devices.findOne({_id:deviceId});

// UPDATE
 env.monitoring_devices.updateOne({_id:deviceId},
  {$set:{status:'maintenance',updated_at:new Date()}});

// DELETE only after clearing reading/event references
 env.monitoring_devices.deleteOne({_id:deviceId});
```

## Citizen Service Requests

The full SQL script includes departments, requests, status history and media links. The demonstrated transition locks a disposable request and changes its expected previous state together with history in one transaction.

```sql
-- CREATE with existing city, department and optional facility
INSERT INTO citizen_service_requests.service_requests
 (request_id,tracking_number,city_id,department_id,
 category,description,location,priority,status)
VALUES (:request_id,:tracking_number,:city_id,:department_id,
 'broken_streetlight','Broken light',:point,'normal','submitted');

-- READ by public tracking reference
SELECT * FROM citizen_service_requests.service_requests
WHERE tracking_number=:tracking_number;

-- UPDATE state and history in one transaction after validation
BEGIN;
SELECT status FROM citizen_service_requests.service_requests
WHERE request_id=:request_id FOR UPDATE;
UPDATE citizen_service_requests.service_requests
SET status='triaged',updated_at=now() WHERE request_id=:request_id;
INSERT INTO citizen_service_requests.request_status_history
 (history_id,request_id,from_status,to_status,changed_by_ref)
VALUES (:history_id,:request_id,'submitted','triaged',:actor);
COMMIT;

-- DELETE a disposable child history before its parent
DELETE FROM citizen_service_requests.request_status_history
WHERE request_id=:request_id;
DELETE FROM citizen_service_requests.service_requests
WHERE request_id=:request_id;
```

## Facility Maintenance

Work orders can reference a request and source inspection; preventive orders may omit both. Completion needs a satisfactory verification inspection for the same facility. Status transitions also write history atomically.

```sql
-- CREATE with existing facility, team and optional request
INSERT INTO facility_maintenance.work_orders
 (work_order_id,facility_id,source_request_id,team_id,
 description,maintenance_type,priority,status)
VALUES (:work_order_id,:facility_id,:request_id,:team_id,
 'Repair light','corrective','normal','open');

-- READ a facility history
SELECT work_order_id,status,created_at
FROM facility_maintenance.work_orders
WHERE facility_id=:facility_id ORDER BY created_at DESC;

-- UPDATE the descriptive scope
UPDATE facility_maintenance.work_orders
SET description='Replace damaged light',updated_at=now()
WHERE work_order_id=:work_order_id;

-- DELETE a disposable unreferenced work order
-- Remove its costs, equipment usage and status history first.
DELETE FROM facility_maintenance.work_orders
WHERE work_order_id=:work_order_id;
```

## Emergency Rules and Response

Approved versions are immutable. The CRUD update uses a draft version; alerts retain a reference to an approved effective version. The service validates source events and responding departments.

```sql
-- CREATE an editable draft for an existing rule
INSERT INTO emergency_rules_and_response.rule_versions
 (rule_version_id,rule_id,version_number,conditions,priority,
 target_department_ref,approval_status,effective_from)
VALUES (:version_id,:rule_id,:version_number,
 '{"metric":"speed","operator":">","threshold":60,"unit":"km/h"}',
 'high',:department_ref,'draft',:effective_from);

-- READ the rule version
SELECT * FROM emergency_rules_and_response.rule_versions
WHERE rule_version_id=:version_id;

-- UPDATE only a draft; published versions require a new version
UPDATE emergency_rules_and_response.rule_versions
SET conditions=jsonb_set(conditions,'{threshold}','65')
WHERE rule_version_id=:version_id AND approval_status='draft';

-- DELETE an unreferenced disposable draft
DELETE FROM emergency_rules_and_response.rule_versions
WHERE rule_version_id=:version_id AND approval_status='draft';
```

## Historical Planning

Connect to srsp_analytics. Load dimensions before facts and map source UUIDs to local surrogate keys. No foreign key or SQL join crosses the operational and analytical databases.

```sql
-- CREATE a daily fact after loading its date/city dimensions
INSERT INTO historical_planning.fact_traffic_summary
 (date_key,city_key,source_road_id,speed_sample_count,
 average_speed_kmh,loaded_at)
VALUES (:date_key,:city_key,:road_id,100,45.5,now())
ON CONFLICT (date_key,city_key,source_road_id) DO NOTHING;

-- READ by reporting period and city
SELECT d.calendar_date,f.average_speed_kmh,f.loaded_at
FROM historical_planning.fact_traffic_summary f
JOIN historical_planning.dim_date d USING(date_key)
WHERE f.city_key=:city_key
 AND d.calendar_date BETWEEN :start_date AND :end_date;

-- UPDATE a recomputed daily value without duplicating its grain
UPDATE historical_planning.fact_traffic_summary
SET speed_sample_count=101,average_speed_kmh=45.7,loaded_at=now()
WHERE date_key=:date_key AND city_key=:city_key
 AND source_road_id=:road_id;

-- DELETE only the disposable demonstration fact
DELETE FROM historical_planning.fact_traffic_summary
WHERE date_key=:date_key AND city_key=:city_key
 AND source_road_id=:road_id;
```

## Repository Reference

mehrthur-teste. (n.d.). *Public services platform serving multiple cities* [Source code]. GitHub. https://github.com/mehrthur-teste/public-services-platform-serving-multiple-cities
