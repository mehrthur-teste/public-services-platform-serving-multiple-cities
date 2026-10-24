-- FACILITY_MAINTENANCE | native PostgreSQL / psql script
-- Run from the project root in numeric order. All changes use a local SQL transaction.
\set ON_ERROR_STOP on
\if :{?operational_db}
\else
\set operational_db srsp_operational
\endif
\connect :operational_db
SET TIME ZONE 'UTC';
BEGIN;


CREATE SCHEMA IF NOT EXISTS facility_maintenance;
CREATE TABLE IF NOT EXISTS facility_maintenance.teams (
 team_id UUID PRIMARY KEY, department_id UUID NOT NULL REFERENCES citizen_service_requests.departments(department_id),
 name TEXT NOT NULL, specialty TEXT NOT NULL, is_active BOOLEAN NOT NULL DEFAULT true
);
CREATE TABLE IF NOT EXISTS facility_maintenance.inspections (
 inspection_id UUID PRIMARY KEY, facility_id UUID NOT NULL REFERENCES road_and_facility_locations.facilities(facility_id),
 inspector_ref TEXT NOT NULL, inspected_at TIMESTAMPTZ NOT NULL,
 inspection_type TEXT NOT NULL CHECK(inspection_type IN ('routine','issue_assessment','completion_verification')),
 outcome TEXT NOT NULL CHECK(outcome IN ('satisfactory','action_required','follow_up')),
 findings TEXT NOT NULL, UNIQUE(inspection_id,facility_id)
);
CREATE TABLE IF NOT EXISTS facility_maintenance.work_orders (
 work_order_id UUID PRIMARY KEY, facility_id UUID NOT NULL REFERENCES road_and_facility_locations.facilities(facility_id),
 source_request_id UUID REFERENCES citizen_service_requests.service_requests(request_id),
 source_inspection_id UUID, completion_inspection_id UUID,
 team_id UUID REFERENCES facility_maintenance.teams(team_id), description TEXT NOT NULL,
 maintenance_type TEXT NOT NULL CHECK(maintenance_type IN ('preventive','corrective')),
 priority TEXT NOT NULL CHECK(priority IN ('low','normal','high','urgent')),
 status TEXT NOT NULL CHECK(status IN ('open','assigned','in_progress','awaiting_verification','completed','cancelled')),
 scheduled_for TIMESTAMPTZ, completed_at TIMESTAMPTZ,
 created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
 FOREIGN KEY(source_inspection_id,facility_id) REFERENCES facility_maintenance.inspections(inspection_id,facility_id),
 FOREIGN KEY(completion_inspection_id,facility_id) REFERENCES facility_maintenance.inspections(inspection_id,facility_id),
 CHECK(status NOT IN ('assigned','in_progress','awaiting_verification') OR team_id IS NOT NULL),
 CHECK(status<>'completed' OR (completion_inspection_id IS NOT NULL AND completed_at IS NOT NULL)),
 CHECK(completed_at IS NULL OR completed_at>=created_at)
);
CREATE TABLE IF NOT EXISTS facility_maintenance.work_order_status_history (
 history_id UUID PRIMARY KEY, work_order_id UUID NOT NULL REFERENCES facility_maintenance.work_orders(work_order_id),
 from_status TEXT CHECK(from_status IN ('open','assigned','in_progress','awaiting_verification','completed','cancelled')),
 to_status TEXT NOT NULL CHECK(to_status IN ('open','assigned','in_progress','awaiting_verification','completed','cancelled')),
 changed_by_ref TEXT NOT NULL, changed_at TIMESTAMPTZ NOT NULL DEFAULT now(), note TEXT
);
CREATE TABLE IF NOT EXISTS facility_maintenance.work_order_costs (
 cost_id UUID PRIMARY KEY, work_order_id UUID NOT NULL REFERENCES facility_maintenance.work_orders(work_order_id),
 cost_category TEXT NOT NULL CHECK(cost_category IN ('labour','materials','equipment','external_service')),
 description TEXT NOT NULL, amount NUMERIC(14,2) NOT NULL CHECK(amount>=0),
 currency_code CHAR(3) NOT NULL CHECK(currency_code ~ '^[A-Z]{3}$'), recorded_at TIMESTAMPTZ NOT NULL
);
CREATE TABLE IF NOT EXISTS facility_maintenance.equipment_usage (
 usage_id UUID PRIMARY KEY, work_order_id UUID NOT NULL REFERENCES facility_maintenance.work_orders(work_order_id),
 equipment_ref TEXT NOT NULL, started_at TIMESTAMPTZ NOT NULL, ended_at TIMESTAMPTZ,
 note TEXT, CHECK(ended_at IS NULL OR ended_at>=started_at)
);
CREATE TABLE IF NOT EXISTS facility_maintenance.inspection_media (
 inspection_id UUID NOT NULL REFERENCES facility_maintenance.inspections(inspection_id),
 media_id UUID NOT NULL REFERENCES multimedia.media_assets(media_id), evidence_role TEXT NOT NULL,
 PRIMARY KEY(inspection_id,media_id)
);
CREATE INDEX IF NOT EXISTS work_facility_time_idx ON facility_maintenance.work_orders(facility_id,created_at DESC);
CREATE INDEX IF NOT EXISTS work_status_idx ON facility_maintenance.work_orders(status,scheduled_for);
CREATE INDEX IF NOT EXISTS cost_work_time_idx ON facility_maintenance.work_order_costs(work_order_id,recorded_at);
CREATE INDEX IF NOT EXISTS inspection_facility_time_idx ON facility_maintenance.inspections(facility_id,inspected_at DESC);
CREATE OR REPLACE FUNCTION facility_maintenance.check_work_order() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF NEW.source_request_id IS NOT NULL AND NOT EXISTS (
   SELECT 1 FROM citizen_service_requests.service_requests r
   JOIN road_and_facility_locations.facilities f ON f.facility_id=NEW.facility_id
   WHERE r.request_id=NEW.source_request_id AND r.city_id=f.city_id AND (r.facility_id IS NULL OR r.facility_id=NEW.facility_id)
 ) THEN RAISE EXCEPTION 'Request and work-order facility must be compatible'; END IF;
 IF NEW.team_id IS NOT NULL AND NOT EXISTS (
   SELECT 1 FROM facility_maintenance.teams t
   JOIN citizen_service_requests.departments d ON d.department_id=t.department_id
   JOIN road_and_facility_locations.facilities f ON f.facility_id=NEW.facility_id
   WHERE t.team_id=NEW.team_id AND d.city_id=f.city_id
 ) THEN RAISE EXCEPTION 'Team must belong to the facility city'; END IF;
 IF NEW.status='completed' AND NOT EXISTS(
   SELECT 1 FROM facility_maintenance.inspections WHERE inspection_id=NEW.completion_inspection_id
   AND inspection_type='completion_verification' AND outcome='satisfactory'
 ) THEN RAISE EXCEPTION 'Completion requires a satisfactory verification inspection'; END IF;
 RETURN NEW;
END $$;
CREATE OR REPLACE TRIGGER work_validation BEFORE INSERT OR UPDATE ON facility_maintenance.work_orders
 FOR EACH ROW EXECUTE FUNCTION facility_maintenance.check_work_order();


-- Shared, deterministic seed records
INSERT INTO "facility_maintenance"."teams"
 ("team_id", "department_id", "name", "specialty", "is_active")
VALUES ('00000000-0000-0000-0000-000000000028', '00000000-0000-0000-0000-00000000001e', 'Demo Electrical Team', 'electrical', TRUE)
ON CONFLICT DO NOTHING;
INSERT INTO "facility_maintenance"."inspections"
 ("inspection_id", "facility_id", "inspector_ref", "inspected_at", "inspection_type", "outcome", "findings")
VALUES ('00000000-0000-0000-0000-000000000029', '00000000-0000-0000-0000-000000000003', 'demo-inspector', '2026-10-23T12:00:00+00:00', 'issue_assessment', 'action_required', 'Exterior light requires replacement')
ON CONFLICT DO NOTHING;
INSERT INTO "facility_maintenance"."work_orders"
 ("work_order_id", "facility_id", "source_request_id", "source_inspection_id", "team_id", "description", "maintenance_type", "priority", "status", "created_at", "updated_at")
VALUES ('00000000-0000-0000-0000-00000000002a', '00000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-00000000001f', '00000000-0000-0000-0000-000000000029', '00000000-0000-0000-0000-000000000028', 'Repair exterior light', 'corrective', 'normal', 'open', '2026-10-23T12:00:00+00:00', '2026-10-23T12:00:00+00:00')
ON CONFLICT DO NOTHING;
INSERT INTO "facility_maintenance"."work_order_status_history"
 ("history_id", "work_order_id", "from_status", "to_status", "changed_by_ref", "changed_at", "note")
VALUES ('00000000-0000-0000-0000-00000000002b', '00000000-0000-0000-0000-00000000002a', NULL, 'open', 'demo-planner', '2026-10-23T12:00:00+00:00', 'Initial registration')
ON CONFLICT DO NOTHING;
INSERT INTO "facility_maintenance"."work_order_costs"
 ("cost_id", "work_order_id", "cost_category", "description", "amount", "currency_code", "recorded_at")
VALUES ('00000000-0000-0000-0000-00000000002c', '00000000-0000-0000-0000-00000000002a', 'materials', 'Replacement lamp', 45.5, 'CAD', '2026-10-23T12:00:00+00:00')
ON CONFLICT DO NOTHING;
INSERT INTO "facility_maintenance"."equipment_usage"
 ("usage_id", "work_order_id", "equipment_ref", "started_at", "note")
VALUES ('00000000-0000-0000-0000-00000000002d', '00000000-0000-0000-0000-00000000002a', 'demo-lift-001', '2026-10-23T12:00:00+00:00', 'Lift reserved')
ON CONFLICT DO NOTHING;
INSERT INTO "facility_maintenance"."inspection_media"
 ("inspection_id", "media_id", "evidence_role")
VALUES ('00000000-0000-0000-0000-000000000029', '00000000-0000-0000-0000-00000000000a', 'before')
ON CONFLICT DO NOTHING;

-- CRUD FOR EACH TABLE

-- TEAMS

-- CREATE a disposable example
INSERT INTO "facility_maintenance"."teams"
 ("team_id", "department_id", "name", "specialty", "is_active")
VALUES ('905f6d02-f871-4208-b113-66133ffb4dd9', '00000000-0000-0000-0000-00000000001e', 'Demo Electrical Team', 'electrical', TRUE);

-- READ by the full primary key
SELECT * FROM "facility_maintenance"."teams" WHERE "team_id" = '905f6d02-f871-4208-b113-66133ffb4dd9';

-- UPDATE the disposable example
UPDATE "facility_maintenance"."teams" SET "name" = 'Reviewed team'
WHERE "team_id" = '905f6d02-f871-4208-b113-66133ffb4dd9';

-- DELETE only the disposable example (shared seed records remain)
DELETE FROM "facility_maintenance"."teams" WHERE "team_id" = '905f6d02-f871-4208-b113-66133ffb4dd9';

-- INSPECTIONS

-- CREATE a disposable example
INSERT INTO "facility_maintenance"."inspections"
 ("inspection_id", "facility_id", "inspector_ref", "inspected_at", "inspection_type", "outcome", "findings")
VALUES ('ec08019d-c2f5-4e9d-bdfa-3f02e11b185e', '00000000-0000-0000-0000-000000000003', 'demo-inspector', '2026-10-23T12:00:00+00:00', 'issue_assessment', 'action_required', 'Exterior light requires replacement');

-- READ by the full primary key
SELECT * FROM "facility_maintenance"."inspections" WHERE "inspection_id" = 'ec08019d-c2f5-4e9d-bdfa-3f02e11b185e';

-- UPDATE the disposable example
UPDATE "facility_maintenance"."inspections" SET "findings" = 'Reviewed findings'
WHERE "inspection_id" = 'ec08019d-c2f5-4e9d-bdfa-3f02e11b185e';

-- DELETE only the disposable example (shared seed records remain)
DELETE FROM "facility_maintenance"."inspections" WHERE "inspection_id" = 'ec08019d-c2f5-4e9d-bdfa-3f02e11b185e';

-- WORK_ORDERS

-- CREATE a disposable example
INSERT INTO "facility_maintenance"."work_orders"
 ("work_order_id", "facility_id", "source_request_id", "source_inspection_id", "team_id", "description", "maintenance_type", "priority", "status", "created_at", "updated_at")
VALUES ('be4d2811-1287-4f9f-a103-1bff9cbbc25a', '00000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-00000000001f', '00000000-0000-0000-0000-000000000029', '00000000-0000-0000-0000-000000000028', 'Repair exterior light', 'corrective', 'normal', 'open', '2026-10-23T12:00:00+00:00', '2026-10-23T12:00:00+00:00');

-- READ by the full primary key
SELECT * FROM "facility_maintenance"."work_orders" WHERE "work_order_id" = 'be4d2811-1287-4f9f-a103-1bff9cbbc25a';

-- UPDATE the disposable example
UPDATE "facility_maintenance"."work_orders" SET "description" = 'Reviewed repair scope', "updated_at" = '2026-10-23T12:00:00+00:00'
WHERE "work_order_id" = 'be4d2811-1287-4f9f-a103-1bff9cbbc25a';

-- DELETE only the disposable example (shared seed records remain)
DELETE FROM "facility_maintenance"."work_orders" WHERE "work_order_id" = 'be4d2811-1287-4f9f-a103-1bff9cbbc25a';

-- WORK_ORDER_STATUS_HISTORY

-- CREATE a disposable example
INSERT INTO "facility_maintenance"."work_order_status_history"
 ("history_id", "work_order_id", "from_status", "to_status", "changed_by_ref", "changed_at", "note")
VALUES ('85837886-62f8-43af-a0b5-b1337d78d53d', '00000000-0000-0000-0000-00000000002a', NULL, 'open', 'demo-planner', '2026-10-23T12:00:00+00:00', 'Initial registration');

-- READ by the full primary key
SELECT * FROM "facility_maintenance"."work_order_status_history" WHERE "history_id" = '85837886-62f8-43af-a0b5-b1337d78d53d';

-- UPDATE the disposable example
UPDATE "facility_maintenance"."work_order_status_history" SET "note" = 'Corrected note'
WHERE "history_id" = '85837886-62f8-43af-a0b5-b1337d78d53d';

-- DELETE only the disposable example (shared seed records remain)
DELETE FROM "facility_maintenance"."work_order_status_history" WHERE "history_id" = '85837886-62f8-43af-a0b5-b1337d78d53d';

-- WORK_ORDER_COSTS

-- CREATE a disposable example
INSERT INTO "facility_maintenance"."work_order_costs"
 ("cost_id", "work_order_id", "cost_category", "description", "amount", "currency_code", "recorded_at")
VALUES ('f25a6ae9-c2a9-4d16-a70b-9948047a435a', '00000000-0000-0000-0000-00000000002a', 'materials', 'Replacement lamp', 45.5, 'CAD', '2026-10-23T12:00:00+00:00');

-- READ by the full primary key
SELECT * FROM "facility_maintenance"."work_order_costs" WHERE "cost_id" = 'f25a6ae9-c2a9-4d16-a70b-9948047a435a';

-- UPDATE the disposable example
UPDATE "facility_maintenance"."work_order_costs" SET "amount" = 46.0
WHERE "cost_id" = 'f25a6ae9-c2a9-4d16-a70b-9948047a435a';

-- DELETE only the disposable example (shared seed records remain)
DELETE FROM "facility_maintenance"."work_order_costs" WHERE "cost_id" = 'f25a6ae9-c2a9-4d16-a70b-9948047a435a';

-- EQUIPMENT_USAGE

-- CREATE a disposable example
INSERT INTO "facility_maintenance"."equipment_usage"
 ("usage_id", "work_order_id", "equipment_ref", "started_at", "note")
VALUES ('8ccc71bf-37f2-4244-8483-17923015e34b', '00000000-0000-0000-0000-00000000002a', 'demo-lift-001', '2026-10-23T12:00:00+00:00', 'Lift reserved');

-- READ by the full primary key
SELECT * FROM "facility_maintenance"."equipment_usage" WHERE "usage_id" = '8ccc71bf-37f2-4244-8483-17923015e34b';

-- UPDATE the disposable example
UPDATE "facility_maintenance"."equipment_usage" SET "note" = 'Lift reservation reviewed'
WHERE "usage_id" = '8ccc71bf-37f2-4244-8483-17923015e34b';

-- DELETE only the disposable example (shared seed records remain)
DELETE FROM "facility_maintenance"."equipment_usage" WHERE "usage_id" = '8ccc71bf-37f2-4244-8483-17923015e34b';

-- INSPECTION_MEDIA

-- CREATE a disposable example
INSERT INTO "facility_maintenance"."inspection_media"
 ("inspection_id", "media_id", "evidence_role")
VALUES ('00000000-0000-0000-0000-000000000029', '00000000-0000-0000-0000-00000000000b', 'before');

-- READ by the full primary key
SELECT * FROM "facility_maintenance"."inspection_media" WHERE "inspection_id" = '00000000-0000-0000-0000-000000000029' AND "media_id" = '00000000-0000-0000-0000-00000000000b';

-- UPDATE the disposable example
UPDATE "facility_maintenance"."inspection_media" SET "evidence_role" = 'supporting'
WHERE "inspection_id" = '00000000-0000-0000-0000-000000000029' AND "media_id" = '00000000-0000-0000-0000-00000000000b';

-- DELETE only the disposable example (shared seed records remain)
DELETE FROM "facility_maintenance"."inspection_media" WHERE "inspection_id" = '00000000-0000-0000-0000-000000000029' AND "media_id" = '00000000-0000-0000-0000-00000000000b';

-- Atomic assignment and status history
INSERT INTO "facility_maintenance"."work_orders"
 ("work_order_id", "facility_id", "source_request_id", "source_inspection_id", "team_id", "description", "maintenance_type", "priority", "status", "created_at", "updated_at")
VALUES ('35245196-f8a5-4ecb-8762-d3380c8b0a7c', '00000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-00000000001f', '00000000-0000-0000-0000-000000000029', '00000000-0000-0000-0000-000000000028', 'Repair exterior light', 'corrective', 'normal', 'open', '2026-10-23T12:00:00+00:00', '2026-10-23T12:00:00+00:00');
SELECT status FROM facility_maintenance.work_orders WHERE work_order_id='35245196-f8a5-4ecb-8762-d3380c8b0a7c' FOR UPDATE;
UPDATE facility_maintenance.work_orders SET status='assigned',updated_at=now()
WHERE work_order_id='35245196-f8a5-4ecb-8762-d3380c8b0a7c' AND status='open';
INSERT INTO facility_maintenance.work_order_status_history
 (history_id,work_order_id,from_status,to_status,changed_by_ref)
VALUES(gen_random_uuid(),'35245196-f8a5-4ecb-8762-d3380c8b0a7c','open','assigned','demo-planner');
DELETE FROM facility_maintenance.work_order_status_history WHERE work_order_id='35245196-f8a5-4ecb-8762-d3380c8b0a7c';
DELETE FROM facility_maintenance.work_orders WHERE work_order_id='35245196-f8a5-4ecb-8762-d3380c8b0a7c';
SELECT w.work_order_id,f.name,c.currency_code,SUM(c.amount) AS total
FROM facility_maintenance.work_orders w JOIN road_and_facility_locations.facilities f ON f.facility_id=w.facility_id
LEFT JOIN facility_maintenance.work_order_costs c ON c.work_order_id=w.work_order_id
GROUP BY w.work_order_id,f.name,c.currency_code;
COMMIT;
