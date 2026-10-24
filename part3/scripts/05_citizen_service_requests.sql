-- CITIZEN_SERVICE_REQUESTS | native PostgreSQL / psql script
-- Run from the project root in numeric order. All changes use a local SQL transaction.
\set ON_ERROR_STOP on
\if :{?operational_db}
\else
\set operational_db srsp_operational
\endif
\connect :operational_db
SET TIME ZONE 'UTC';
BEGIN;


CREATE SCHEMA IF NOT EXISTS citizen_service_requests;
CREATE TABLE IF NOT EXISTS citizen_service_requests.departments (
 department_id UUID PRIMARY KEY, city_id UUID NOT NULL REFERENCES road_and_facility_locations.cities(city_id),
 parent_department_id UUID, name TEXT NOT NULL, is_active BOOLEAN NOT NULL DEFAULT true,
 UNIQUE(department_id,city_id),
 FOREIGN KEY(parent_department_id,city_id) REFERENCES citizen_service_requests.departments(department_id,city_id),
 CHECK(parent_department_id IS NULL OR parent_department_id<>department_id)
);
CREATE TABLE IF NOT EXISTS citizen_service_requests.service_requests (
 request_id UUID PRIMARY KEY, tracking_number TEXT NOT NULL UNIQUE, submitted_by_ref TEXT,
 city_id UUID NOT NULL REFERENCES road_and_facility_locations.cities(city_id), road_id UUID, facility_id UUID,
 department_id UUID, category TEXT NOT NULL CHECK(category IN ('pothole','broken_streetlight','missed_waste_collection','snow_removal','accessibility','public_safety')),
 description TEXT NOT NULL, location geometry(Point,4326) NOT NULL,
 priority TEXT NOT NULL CHECK(priority IN ('low','normal','high','urgent')),
 status TEXT NOT NULL CHECK(status IN ('submitted','triaged','assigned','in_progress','resolved','closed')),
 resolved_at TIMESTAMPTZ, created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
 FOREIGN KEY(road_id,city_id) REFERENCES road_and_facility_locations.roads(road_id,city_id),
 FOREIGN KEY(facility_id,city_id) REFERENCES road_and_facility_locations.facilities(facility_id,city_id),
 FOREIGN KEY(department_id,city_id) REFERENCES citizen_service_requests.departments(department_id,city_id),
 CHECK(resolved_at IS NULL OR resolved_at>=created_at),
 CHECK(status NOT IN ('resolved','closed') OR resolved_at IS NOT NULL),
 CHECK(status NOT IN ('assigned','in_progress') OR department_id IS NOT NULL)
);
CREATE TABLE IF NOT EXISTS citizen_service_requests.request_status_history (
 history_id UUID PRIMARY KEY, request_id UUID NOT NULL REFERENCES citizen_service_requests.service_requests(request_id),
 from_status TEXT CHECK(from_status IN ('submitted','triaged','assigned','in_progress','resolved','closed')),
 to_status TEXT NOT NULL CHECK(to_status IN ('submitted','triaged','assigned','in_progress','resolved','closed')),
 changed_by_ref TEXT NOT NULL, changed_at TIMESTAMPTZ NOT NULL DEFAULT now(), note TEXT
);
CREATE TABLE IF NOT EXISTS citizen_service_requests.request_media (
 request_id UUID NOT NULL REFERENCES citizen_service_requests.service_requests(request_id),
 media_id UUID NOT NULL REFERENCES multimedia.media_assets(media_id), evidence_role TEXT NOT NULL,
 PRIMARY KEY(request_id,media_id)
);
CREATE INDEX IF NOT EXISTS request_queue_idx ON citizen_service_requests.service_requests(city_id,status,department_id,created_at);
CREATE INDEX IF NOT EXISTS request_history_idx ON citizen_service_requests.request_status_history(request_id,changed_at);
-- Serialise department mutations in this example to prevent concurrent cycle creation.
CREATE OR REPLACE FUNCTION citizen_service_requests.no_department_cycle() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 PERFORM pg_advisory_xact_lock(510003);
 IF NEW.parent_department_id IS NOT NULL AND EXISTS(
   WITH RECURSIVE ancestors AS (
     SELECT department_id,parent_department_id FROM citizen_service_requests.departments WHERE department_id=NEW.parent_department_id
     UNION
     SELECT d.department_id,d.parent_department_id FROM citizen_service_requests.departments d JOIN ancestors a ON d.department_id=a.parent_department_id
   ) SELECT 1 FROM ancestors WHERE department_id=NEW.department_id
 ) THEN RAISE EXCEPTION 'Department hierarchy cannot contain a cycle'; END IF;
 RETURN NEW;
END $$;
CREATE OR REPLACE TRIGGER department_cycle BEFORE INSERT OR UPDATE ON citizen_service_requests.departments
 FOR EACH ROW EXECUTE FUNCTION citizen_service_requests.no_department_cycle();


-- Shared, deterministic seed records
INSERT INTO "citizen_service_requests"."departments"
 ("department_id", "city_id", "name", "is_active")
VALUES ('00000000-0000-0000-0000-00000000001e', '00000000-0000-0000-0000-000000000001', 'Demo Public Works', TRUE)
ON CONFLICT DO NOTHING;
INSERT INTO "citizen_service_requests"."service_requests"
 ("request_id", "tracking_number", "city_id", "facility_id", "department_id", "category", "description", "location", "priority", "status", "created_at", "updated_at")
VALUES ('00000000-0000-0000-0000-00000000001f', 'DEMO-2026-0001', '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-00000000001e', 'broken_streetlight', 'Light outside community centre is broken', ST_GeomFromEWKT('SRID=4326;POINT(-79.3832 43.6532)'), 'normal', 'submitted', '2026-10-23T12:00:00+00:00', '2026-10-23T12:00:00+00:00')
ON CONFLICT DO NOTHING;
INSERT INTO "citizen_service_requests"."request_status_history"
 ("history_id", "request_id", "from_status", "to_status", "changed_by_ref", "changed_at", "note")
VALUES ('00000000-0000-0000-0000-000000000020', '00000000-0000-0000-0000-00000000001f', NULL, 'submitted', 'demo-citizen', '2026-10-23T12:00:00+00:00', 'Initial registration')
ON CONFLICT DO NOTHING;
INSERT INTO "citizen_service_requests"."request_media"
 ("request_id", "media_id", "evidence_role")
VALUES ('00000000-0000-0000-0000-00000000001f', '00000000-0000-0000-0000-00000000000a', 'before')
ON CONFLICT DO NOTHING;

-- CRUD FOR EACH TABLE

-- DEPARTMENTS

-- CREATE a disposable example
INSERT INTO "citizen_service_requests"."departments"
 ("department_id", "city_id", "name", "is_active")
VALUES ('e8ca12d3-568d-488c-b35a-e9b820cb018b', '00000000-0000-0000-0000-000000000001', 'Demo Public Works', TRUE);

-- READ by the full primary key
SELECT * FROM "citizen_service_requests"."departments" WHERE "department_id" = 'e8ca12d3-568d-488c-b35a-e9b820cb018b';

-- UPDATE the disposable example
UPDATE "citizen_service_requests"."departments" SET "name" = 'Demo Public Works reviewed'
WHERE "department_id" = 'e8ca12d3-568d-488c-b35a-e9b820cb018b';

-- DELETE only the disposable example (shared seed records remain)
DELETE FROM "citizen_service_requests"."departments" WHERE "department_id" = 'e8ca12d3-568d-488c-b35a-e9b820cb018b';

-- SERVICE_REQUESTS

-- CREATE a disposable example
INSERT INTO "citizen_service_requests"."service_requests"
 ("request_id", "tracking_number", "city_id", "facility_id", "department_id", "category", "description", "location", "priority", "status", "created_at", "updated_at")
VALUES ('305eeadf-cfda-4acc-86f0-a7bb4a906da4', 'DEMO-f1bd0864-fbb5-4305-8fc9-2860101565f3', '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-00000000001e', 'broken_streetlight', 'Light outside community centre is broken', ST_GeomFromEWKT('SRID=4326;POINT(-79.3832 43.6532)'), 'normal', 'submitted', '2026-10-23T12:00:00+00:00', '2026-10-23T12:00:00+00:00');

-- READ by the full primary key
SELECT * FROM "citizen_service_requests"."service_requests" WHERE "request_id" = '305eeadf-cfda-4acc-86f0-a7bb4a906da4';

-- UPDATE the disposable example
UPDATE "citizen_service_requests"."service_requests" SET "description" = 'Reviewed description', "updated_at" = '2026-10-23T12:00:00+00:00'
WHERE "request_id" = '305eeadf-cfda-4acc-86f0-a7bb4a906da4';

-- DELETE only the disposable example (shared seed records remain)
DELETE FROM "citizen_service_requests"."service_requests" WHERE "request_id" = '305eeadf-cfda-4acc-86f0-a7bb4a906da4';

-- REQUEST_STATUS_HISTORY

-- CREATE a disposable example
INSERT INTO "citizen_service_requests"."request_status_history"
 ("history_id", "request_id", "from_status", "to_status", "changed_by_ref", "changed_at", "note")
VALUES ('956d370b-51d2-4c12-8b50-6adada91101e', '00000000-0000-0000-0000-00000000001f', NULL, 'submitted', 'demo-citizen', '2026-10-23T12:00:00+00:00', 'Initial registration');

-- READ by the full primary key
SELECT * FROM "citizen_service_requests"."request_status_history" WHERE "history_id" = '956d370b-51d2-4c12-8b50-6adada91101e';

-- UPDATE the disposable example
UPDATE "citizen_service_requests"."request_status_history" SET "note" = 'Corrected explanatory note'
WHERE "history_id" = '956d370b-51d2-4c12-8b50-6adada91101e';

-- DELETE only the disposable example (shared seed records remain)
DELETE FROM "citizen_service_requests"."request_status_history" WHERE "history_id" = '956d370b-51d2-4c12-8b50-6adada91101e';

-- REQUEST_MEDIA

-- CREATE a disposable example
INSERT INTO "citizen_service_requests"."request_media"
 ("request_id", "media_id", "evidence_role")
VALUES ('00000000-0000-0000-0000-00000000001f', '00000000-0000-0000-0000-00000000000b', 'before');

-- READ by the full primary key
SELECT * FROM "citizen_service_requests"."request_media" WHERE "request_id" = '00000000-0000-0000-0000-00000000001f' AND "media_id" = '00000000-0000-0000-0000-00000000000b';

-- UPDATE the disposable example
UPDATE "citizen_service_requests"."request_media" SET "evidence_role" = 'supporting'
WHERE "request_id" = '00000000-0000-0000-0000-00000000001f' AND "media_id" = '00000000-0000-0000-0000-00000000000b';

-- DELETE only the disposable example (shared seed records remain)
DELETE FROM "citizen_service_requests"."request_media" WHERE "request_id" = '00000000-0000-0000-0000-00000000001f' AND "media_id" = '00000000-0000-0000-0000-00000000000b';

-- Atomic status change plus history on a disposable request
INSERT INTO "citizen_service_requests"."service_requests"
 ("request_id", "tracking_number", "city_id", "facility_id", "department_id", "category", "description", "location", "priority", "status", "created_at", "updated_at")
VALUES ('06824e13-83b6-497e-87e6-afc69f4aeffb', 'DEMO-06824e13-83b6-497e-87e6-afc69f4aeffb', '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-00000000001e', 'broken_streetlight', 'Light outside community centre is broken', ST_GeomFromEWKT('SRID=4326;POINT(-79.3832 43.6532)'), 'normal', 'submitted', '2026-10-23T12:00:00+00:00', '2026-10-23T12:00:00+00:00');
SELECT status FROM citizen_service_requests.service_requests WHERE request_id='06824e13-83b6-497e-87e6-afc69f4aeffb' FOR UPDATE;
UPDATE citizen_service_requests.service_requests SET status='triaged',updated_at=now()
WHERE request_id='06824e13-83b6-497e-87e6-afc69f4aeffb' AND status='submitted';
INSERT INTO citizen_service_requests.request_status_history
 (history_id,request_id,from_status,to_status,changed_by_ref,note)
VALUES (gen_random_uuid(),'06824e13-83b6-497e-87e6-afc69f4aeffb','submitted','triaged','demo-officer','Validated initial triage');
DELETE FROM citizen_service_requests.request_status_history WHERE request_id='06824e13-83b6-497e-87e6-afc69f4aeffb';
DELETE FROM citizen_service_requests.service_requests WHERE request_id='06824e13-83b6-497e-87e6-afc69f4aeffb';
SELECT r.tracking_number,r.status,f.name AS facility,m.storage_key,m.upload_status
FROM citizen_service_requests.service_requests r
LEFT JOIN road_and_facility_locations.facilities f ON f.facility_id=r.facility_id
LEFT JOIN citizen_service_requests.request_media rm ON rm.request_id=r.request_id
LEFT JOIN multimedia.media_assets m ON m.media_id=rm.media_id
WHERE r.city_id='00000000-0000-0000-0000-000000000001' AND r.status='submitted' LIMIT 100;
COMMIT;
