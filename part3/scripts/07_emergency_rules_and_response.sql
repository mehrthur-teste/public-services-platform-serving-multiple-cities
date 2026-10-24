-- EMERGENCY_RULES_AND_RESPONSE | native PostgreSQL / psql script
-- Run from the project root in numeric order. All changes use a local SQL transaction.
\set ON_ERROR_STOP on
\if :{?operational_db}
\else
\set operational_db srsp_operational
\endif
\connect :operational_db
SET TIME ZONE 'UTC';
BEGIN;


CREATE SCHEMA IF NOT EXISTS emergency_rules_and_response;
CREATE TABLE IF NOT EXISTS emergency_rules_and_response.response_rules (
 rule_id UUID PRIMARY KEY, name TEXT NOT NULL, description TEXT NOT NULL,
 source_context TEXT NOT NULL CHECK(source_context IN ('transportation_sensors','environmental_monitoring','citizen_service_requests')),
 city_id UUID REFERENCES road_and_facility_locations.cities(city_id), zone_id UUID,
 is_active BOOLEAN NOT NULL DEFAULT true,
 created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
 FOREIGN KEY(zone_id,city_id) REFERENCES road_and_facility_locations.service_zones(zone_id,city_id),
 CHECK(zone_id IS NULL OR city_id IS NOT NULL)
);
CREATE TABLE IF NOT EXISTS emergency_rules_and_response.rule_versions (
 rule_version_id UUID PRIMARY KEY, rule_id UUID NOT NULL REFERENCES emergency_rules_and_response.response_rules(rule_id),
 version_number INTEGER NOT NULL CHECK(version_number>0), conditions JSONB NOT NULL,
 priority TEXT NOT NULL CHECK(priority IN ('low','normal','high','urgent')),
 target_department_ref TEXT NOT NULL, escalation_after_seconds INTEGER CHECK(escalation_after_seconds>0),
 approval_status TEXT NOT NULL CHECK(approval_status IN ('draft','approved','retired')),
 approved_by_ref TEXT, effective_from TIMESTAMPTZ NOT NULL, effective_to TIMESTAMPTZ,
 UNIQUE(rule_id,version_number),
 CHECK(effective_to IS NULL OR effective_to>effective_from),
 CHECK(approval_status<>'approved' OR approved_by_ref IS NOT NULL),
 CHECK(jsonb_typeof(conditions)='object' AND conditions ?& ARRAY['metric','operator','threshold','unit']),
 CHECK(jsonb_typeof(conditions->'metric')='string' AND jsonb_typeof(conditions->'unit')='string'
  AND jsonb_typeof(conditions->'threshold')='number' AND conditions->>'operator' IN ('>','>=','<','<=','='))
);
CREATE TABLE IF NOT EXISTS emergency_rules_and_response.alerts (
 alert_id UUID PRIMARY KEY, rule_version_id UUID NOT NULL REFERENCES emergency_rules_and_response.rule_versions(rule_version_id),
 source_context TEXT NOT NULL CHECK(source_context IN ('transportation_sensors','environmental_monitoring','citizen_service_requests')),
 source_event_id TEXT NOT NULL, deduplication_key TEXT NOT NULL UNIQUE,
 priority TEXT NOT NULL CHECK(priority IN ('low','normal','high','urgent')),
 status TEXT NOT NULL CHECK(status IN ('open','acknowledged','in_progress','closed')),
 triggered_at TIMESTAMPTZ NOT NULL, closed_at TIMESTAMPTZ,
 CHECK((status='closed' AND closed_at IS NOT NULL AND closed_at>=triggered_at) OR (status<>'closed' AND closed_at IS NULL))
);
CREATE TABLE IF NOT EXISTS emergency_rules_and_response.alert_actions (
 action_id UUID PRIMARY KEY, alert_id UUID NOT NULL REFERENCES emergency_rules_and_response.alerts(alert_id),
 action_type TEXT NOT NULL CHECK(action_type IN ('acknowledged','team_dispatched','status_changed','closed')),
 performed_by_ref TEXT NOT NULL, performed_at TIMESTAMPTZ NOT NULL, note TEXT
);
CREATE TABLE IF NOT EXISTS emergency_rules_and_response.escalation_history (
 escalation_id UUID PRIMARY KEY, alert_id UUID NOT NULL REFERENCES emergency_rules_and_response.alerts(alert_id),
 from_department_ref TEXT NOT NULL, to_department_ref TEXT NOT NULL,
 reason TEXT NOT NULL, escalated_at TIMESTAMPTZ NOT NULL,
 CHECK(from_department_ref<>to_department_ref)
);
CREATE INDEX IF NOT EXISTS alert_queue_idx ON emergency_rules_and_response.alerts(status,triggered_at);
CREATE INDEX IF NOT EXISTS action_alert_time_idx ON emergency_rules_and_response.alert_actions(alert_id,performed_at);
CREATE OR REPLACE FUNCTION emergency_rules_and_response.validate_alert() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF NOT EXISTS (
   SELECT 1 FROM emergency_rules_and_response.rule_versions v
   JOIN emergency_rules_and_response.response_rules r ON r.rule_id=v.rule_id
   WHERE v.rule_version_id=NEW.rule_version_id AND v.approval_status='approved' AND r.is_active
   AND r.source_context=NEW.source_context AND v.priority=NEW.priority
   AND NEW.triggered_at>=v.effective_from AND (v.effective_to IS NULL OR NEW.triggered_at<v.effective_to)
 ) THEN RAISE EXCEPTION 'Alert requires an active approved effective rule with matching context and priority'; END IF;
 RETURN NEW;
END $$;
CREATE OR REPLACE TRIGGER alert_validation BEFORE INSERT ON emergency_rules_and_response.alerts
 FOR EACH ROW EXECUTE FUNCTION emergency_rules_and_response.validate_alert();
CREATE OR REPLACE FUNCTION emergency_rules_and_response.preserve_approved_version() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF OLD.approval_status IN ('approved','retired') THEN RAISE EXCEPTION 'Published rule versions are immutable; create a new version'; END IF;
 RETURN NEW;
END $$;
CREATE OR REPLACE TRIGGER immutable_rule_version BEFORE UPDATE ON emergency_rules_and_response.rule_versions
 FOR EACH ROW EXECUTE FUNCTION emergency_rules_and_response.preserve_approved_version();


-- Shared, deterministic seed records
INSERT INTO "citizen_service_requests"."departments"
 ("department_id", "city_id", "name", "is_active")
VALUES ('00000000-0000-0000-0000-000000000021', '00000000-0000-0000-0000-000000000001', 'Demo Emergency Operations', TRUE)
ON CONFLICT DO NOTHING;
INSERT INTO "emergency_rules_and_response"."response_rules"
 ("rule_id", "name", "description", "source_context", "city_id", "zone_id", "is_active", "created_at", "updated_at")
VALUES ('00000000-0000-0000-0000-000000000032', 'Demo high speed observation', 'Flag readings over 60 km/h for review', 'transportation_sensors', '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000005', TRUE, '2026-10-23T12:00:00+00:00', '2026-10-23T12:00:00+00:00')
ON CONFLICT DO NOTHING;
INSERT INTO "emergency_rules_and_response"."rule_versions"
 ("rule_version_id", "rule_id", "version_number", "conditions", "priority", "target_department_ref", "escalation_after_seconds", "approval_status", "approved_by_ref", "effective_from")
VALUES ('00000000-0000-0000-0000-000000000033', '00000000-0000-0000-0000-000000000032', 1, '{"metric": "speed", "operator": ">", "threshold": 60, "unit": "km/h"}'::jsonb, 'high', '00000000-0000-0000-0000-00000000001e', 300, 'approved', 'demo-supervisor', '2026-10-23T12:00:00+00:00')
ON CONFLICT DO NOTHING;
INSERT INTO "emergency_rules_and_response"."alerts"
 ("alert_id", "rule_version_id", "source_context", "source_event_id", "deduplication_key", "priority", "status", "triggered_at")
VALUES ('00000000-0000-0000-0000-000000000034', '00000000-0000-0000-0000-000000000033', 'transportation_sensors', '00000000-0000-0000-0000-000000000017', '00000000-0000-0000-0000-000000000033:00000000-0000-0000-0000-000000000017', 'high', 'open', '2026-10-23T12:00:00+00:00')
ON CONFLICT DO NOTHING;
INSERT INTO "emergency_rules_and_response"."alert_actions"
 ("action_id", "alert_id", "action_type", "performed_by_ref", "performed_at", "note")
VALUES ('00000000-0000-0000-0000-000000000035', '00000000-0000-0000-0000-000000000034', 'acknowledged', 'demo-operator', '2026-10-23T12:00:00+00:00', 'Operator reviewed observation')
ON CONFLICT DO NOTHING;
INSERT INTO "emergency_rules_and_response"."escalation_history"
 ("escalation_id", "alert_id", "from_department_ref", "to_department_ref", "reason", "escalated_at")
VALUES ('00000000-0000-0000-0000-000000000036', '00000000-0000-0000-0000-000000000034', '00000000-0000-0000-0000-00000000001e', '00000000-0000-0000-0000-000000000021', 'Demonstration handover', '2026-10-23T12:00:00+00:00')
ON CONFLICT DO NOTHING;

-- CRUD FOR EACH TABLE

-- RESPONSE_RULES

-- CREATE a disposable example
INSERT INTO "emergency_rules_and_response"."response_rules"
 ("rule_id", "name", "description", "source_context", "city_id", "zone_id", "is_active", "created_at", "updated_at")
VALUES ('17534f59-4984-4b72-8239-492804ffb90b', 'Demo high speed observation', 'Flag readings over 60 km/h for review', 'transportation_sensors', '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000005', TRUE, '2026-10-23T12:00:00+00:00', '2026-10-23T12:00:00+00:00');

-- READ by the full primary key
SELECT * FROM "emergency_rules_and_response"."response_rules" WHERE "rule_id" = '17534f59-4984-4b72-8239-492804ffb90b';

-- UPDATE the disposable example
UPDATE "emergency_rules_and_response"."response_rules" SET "description" = 'Reviewed scope'
WHERE "rule_id" = '17534f59-4984-4b72-8239-492804ffb90b';

-- DELETE only the disposable example (shared seed records remain)
DELETE FROM "emergency_rules_and_response"."response_rules" WHERE "rule_id" = '17534f59-4984-4b72-8239-492804ffb90b';

-- RULE_VERSIONS

-- CREATE a disposable example
INSERT INTO "emergency_rules_and_response"."rule_versions"
 ("rule_version_id", "rule_id", "version_number", "conditions", "priority", "target_department_ref", "escalation_after_seconds", "approval_status", "approved_by_ref", "effective_from")
VALUES ('44346609-785f-4220-bc63-70d89886b7a9', '00000000-0000-0000-0000-000000000032', 1000000, '{"metric": "speed", "operator": ">", "threshold": 60, "unit": "km/h"}'::jsonb, 'high', '00000000-0000-0000-0000-00000000001e', 300, 'draft', NULL, '2026-10-23T12:00:00+00:00');

-- READ by the full primary key
SELECT * FROM "emergency_rules_and_response"."rule_versions" WHERE "rule_version_id" = '44346609-785f-4220-bc63-70d89886b7a9';

-- UPDATE the disposable example
UPDATE "emergency_rules_and_response"."rule_versions" SET "conditions" = '{"metric": "speed", "operator": ">", "threshold": 65, "unit": "km/h"}'::jsonb
WHERE "rule_version_id" = '44346609-785f-4220-bc63-70d89886b7a9';

-- DELETE only the disposable example (shared seed records remain)
DELETE FROM "emergency_rules_and_response"."rule_versions" WHERE "rule_version_id" = '44346609-785f-4220-bc63-70d89886b7a9';

-- ALERTS

-- CREATE a disposable example
INSERT INTO "emergency_rules_and_response"."alerts"
 ("alert_id", "rule_version_id", "source_context", "source_event_id", "deduplication_key", "priority", "status", "triggered_at")
VALUES ('15ed4ba4-0b9d-4dc9-811a-0641fb8437e8', '00000000-0000-0000-0000-000000000033', 'transportation_sensors', '00000000-0000-0000-0000-000000000017', 'demo-e618efed-4acb-4f6f-a9d9-9ee4c9ef9f0b', 'high', 'open', '2026-10-23T12:00:00+00:00');

-- READ by the full primary key
SELECT * FROM "emergency_rules_and_response"."alerts" WHERE "alert_id" = '15ed4ba4-0b9d-4dc9-811a-0641fb8437e8';

-- UPDATE the disposable example
UPDATE "emergency_rules_and_response"."alerts" SET "status" = 'acknowledged'
WHERE "alert_id" = '15ed4ba4-0b9d-4dc9-811a-0641fb8437e8';

-- DELETE only the disposable example (shared seed records remain)
DELETE FROM "emergency_rules_and_response"."alerts" WHERE "alert_id" = '15ed4ba4-0b9d-4dc9-811a-0641fb8437e8';

-- ALERT_ACTIONS

-- CREATE a disposable example
INSERT INTO "emergency_rules_and_response"."alert_actions"
 ("action_id", "alert_id", "action_type", "performed_by_ref", "performed_at", "note")
VALUES ('7913a817-c4b4-4074-b05d-2feaa6763a1e', '00000000-0000-0000-0000-000000000034', 'acknowledged', 'demo-operator', '2026-10-23T12:00:00+00:00', 'Operator reviewed observation');

-- READ by the full primary key
SELECT * FROM "emergency_rules_and_response"."alert_actions" WHERE "action_id" = '7913a817-c4b4-4074-b05d-2feaa6763a1e';

-- UPDATE the disposable example
UPDATE "emergency_rules_and_response"."alert_actions" SET "note" = 'Corrected note'
WHERE "action_id" = '7913a817-c4b4-4074-b05d-2feaa6763a1e';

-- DELETE only the disposable example (shared seed records remain)
DELETE FROM "emergency_rules_and_response"."alert_actions" WHERE "action_id" = '7913a817-c4b4-4074-b05d-2feaa6763a1e';

-- ESCALATION_HISTORY

-- CREATE a disposable example
INSERT INTO "emergency_rules_and_response"."escalation_history"
 ("escalation_id", "alert_id", "from_department_ref", "to_department_ref", "reason", "escalated_at")
VALUES ('59e26673-7161-4376-b223-3ad9bb91ce13', '00000000-0000-0000-0000-000000000034', '00000000-0000-0000-0000-00000000001e', '00000000-0000-0000-0000-000000000021', 'Demonstration handover', '2026-10-23T12:00:00+00:00');

-- READ by the full primary key
SELECT * FROM "emergency_rules_and_response"."escalation_history" WHERE "escalation_id" = '59e26673-7161-4376-b223-3ad9bb91ce13';

-- UPDATE the disposable example
UPDATE "emergency_rules_and_response"."escalation_history" SET "reason" = 'Reviewed handover explanation'
WHERE "escalation_id" = '59e26673-7161-4376-b223-3ad9bb91ce13';

-- DELETE only the disposable example (shared seed records remain)
DELETE FROM "emergency_rules_and_response"."escalation_history" WHERE "escalation_id" = '59e26673-7161-4376-b223-3ad9bb91ce13';

-- Service boundary validation for this illustrative evaluation; no generic rule engine is claimed.
DO $$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM transportation_sensors.traffic_readings
 WHERE reading_id='00000000-0000-0000-0000-000000000017' AND measurement_type='speed'
 AND numeric_value>60 AND unit='km/h') THEN RAISE EXCEPTION 'Expected source observation missing'; END IF;
 IF NOT EXISTS(SELECT 1 FROM citizen_service_requests.departments
 WHERE department_id='00000000-0000-0000-0000-00000000001e')
 THEN RAISE EXCEPTION 'Responding department missing'; END IF;
END $$;
SELECT a.alert_id,a.status,v.version_number FROM emergency_rules_and_response.alerts a
JOIN emergency_rules_and_response.rule_versions v ON v.rule_version_id=a.rule_version_id
WHERE a.status='open' ORDER BY a.triggered_at LIMIT 100;
COMMIT;
