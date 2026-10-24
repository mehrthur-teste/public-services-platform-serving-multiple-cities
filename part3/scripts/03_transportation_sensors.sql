-- TRANSPORTATION_SENSORS | native PostgreSQL / psql script
-- Run from the project root in numeric order. All changes use a local SQL transaction.
\set ON_ERROR_STOP on
\if :{?operational_db}
\else
\set operational_db srsp_operational
\endif
\connect :operational_db
SET TIME ZONE 'UTC';
BEGIN;


CREATE SCHEMA IF NOT EXISTS transportation_sensors;
CREATE TABLE IF NOT EXISTS transportation_sensors.monitoring_units (
 unit_id UUID PRIMARY KEY, city_id UUID NOT NULL REFERENCES road_and_facility_locations.cities(city_id),
 road_id UUID, description TEXT NOT NULL, lane_number INTEGER CHECK(lane_number>0),
 location geometry(Point,4326) NOT NULL,
 status TEXT NOT NULL CHECK(status IN ('active','inactive','maintenance')),
 created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
 FOREIGN KEY(road_id,city_id) REFERENCES road_and_facility_locations.roads(road_id,city_id)
);
CREATE TABLE IF NOT EXISTS transportation_sensors.sensors (
 sensor_id UUID PRIMARY KEY, unit_id UUID NOT NULL REFERENCES transportation_sensors.monitoring_units(unit_id),
 sensor_type TEXT NOT NULL CHECK(sensor_type IN ('radar','camera','occupancy_detector')),
 status TEXT NOT NULL CHECK(status IN ('active','inactive','maintenance')),
 configuration JSONB NOT NULL DEFAULT '{}' CHECK(jsonb_typeof(configuration)='object'),
 created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
 UNIQUE(sensor_id,sensor_type),
 CHECK(NOT configuration ? 'sampling_interval_seconds' OR
   (jsonb_typeof(configuration->'sampling_interval_seconds')='number' AND (configuration->>'sampling_interval_seconds')::numeric>0)),
 CHECK(NOT configuration ? 'capture_mode' OR configuration->>'capture_mode' IN ('triggered','continuous'))
);
CREATE TABLE IF NOT EXISTS transportation_sensors.traffic_readings (
 reading_id UUID PRIMARY KEY, sensor_id UUID NOT NULL REFERENCES transportation_sensors.sensors(sensor_id),
 source_event_id TEXT NOT NULL, recorded_at TIMESTAMPTZ NOT NULL,
 measurement_type TEXT NOT NULL CHECK(measurement_type IN ('speed','occupancy','congestion_level')),
 numeric_value DOUBLE PRECISION, category_value TEXT, unit TEXT,
 lane_number INTEGER CHECK(lane_number>0), vehicle_track_id TEXT,
 UNIQUE(sensor_id,source_event_id),
 CHECK((measurement_type='speed' AND numeric_value IS NOT NULL AND numeric_value>=0 AND unit='km/h' AND category_value IS NULL)
 OR (measurement_type='occupancy' AND numeric_value IS NOT NULL AND numeric_value BETWEEN 0 AND 100 AND unit='percent' AND category_value IS NULL)
 OR (measurement_type='congestion_level' AND numeric_value IS NULL AND unit IS NULL AND category_value IS NOT NULL AND category_value IN ('low','moderate','high')))
);
CREATE TABLE IF NOT EXISTS transportation_sensors.transit_events (
 transit_event_id UUID PRIMARY KEY, stop_id UUID NOT NULL REFERENCES road_and_facility_locations.facilities(facility_id),
 route_id TEXT NOT NULL, vehicle_id TEXT NOT NULL, source_event_id TEXT NOT NULL,
 provider_id TEXT NOT NULL, scheduled_at TIMESTAMPTZ, occurred_at TIMESTAMPTZ NOT NULL,
 UNIQUE(provider_id,source_event_id)
);
CREATE TABLE IF NOT EXISTS transportation_sensors.capture_events (
 capture_id UUID PRIMARY KEY, reading_id UUID NOT NULL REFERENCES transportation_sensors.traffic_readings(reading_id),
 camera_id UUID NOT NULL, camera_type TEXT NOT NULL DEFAULT 'camera' CHECK(camera_type='camera'),
 captured_at TIMESTAMPTZ NOT NULL, vehicle_track_id TEXT, plate_text TEXT,
 plate_confidence NUMERIC(5,4) CHECK(plate_confidence BETWEEN 0 AND 1),
 review_status TEXT NOT NULL CHECK(review_status IN ('pending','accepted','rejected')),
 FOREIGN KEY(camera_id,camera_type) REFERENCES transportation_sensors.sensors(sensor_id,sensor_type)
);
CREATE TABLE IF NOT EXISTS transportation_sensors.capture_media (
 capture_id UUID NOT NULL REFERENCES transportation_sensors.capture_events(capture_id),
 media_id UUID NOT NULL REFERENCES multimedia.media_assets(media_id), evidence_role TEXT NOT NULL,
 PRIMARY KEY(capture_id,media_id)
);
CREATE INDEX IF NOT EXISTS traffic_sensor_time_idx ON transportation_sensors.traffic_readings(sensor_id,recorded_at DESC);
CREATE INDEX IF NOT EXISTS sensor_unit_idx ON transportation_sensors.sensors(unit_id);
CREATE INDEX IF NOT EXISTS capture_reading_idx ON transportation_sensors.capture_events(reading_id);
CREATE INDEX IF NOT EXISTS transit_stop_time_idx ON transportation_sensors.transit_events(stop_id,occurred_at DESC);
-- Enforce the specialised stop relationship, beyond a generic facility FK.
CREATE OR REPLACE FUNCTION transportation_sensors.check_bus_stop() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF NOT EXISTS(SELECT 1 FROM road_and_facility_locations.facilities WHERE facility_id=NEW.stop_id AND facility_type='bus_stop')
 THEN RAISE EXCEPTION 'stop_id must identify a bus_stop'; END IF;
 RETURN NEW;
END $$;
CREATE OR REPLACE TRIGGER transit_bus_stop BEFORE INSERT OR UPDATE ON transportation_sensors.transit_events
 FOR EACH ROW EXECUTE FUNCTION transportation_sensors.check_bus_stop();


-- Shared, deterministic seed records
INSERT INTO "transportation_sensors"."monitoring_units"
 ("unit_id", "city_id", "road_id", "description", "location", "status")
VALUES ('00000000-0000-0000-0000-000000000014', '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000002', 'Demo monitoring point', ST_GeomFromEWKT('SRID=4326;POINT(-79.3832 43.6532)'), 'active')
ON CONFLICT DO NOTHING;
INSERT INTO "transportation_sensors"."sensors"
 ("sensor_id", "unit_id", "sensor_type", "status", "configuration")
VALUES ('00000000-0000-0000-0000-000000000015', '00000000-0000-0000-0000-000000000014', 'radar', 'active', '{"sampling_interval_seconds": 5, "measured_variables": ["speed_kmh"]}'::jsonb)
ON CONFLICT DO NOTHING;
INSERT INTO "transportation_sensors"."sensors"
 ("sensor_id", "unit_id", "sensor_type", "status", "configuration")
VALUES ('00000000-0000-0000-0000-000000000016', '00000000-0000-0000-0000-000000000014', 'camera', 'active', '{"capture_mode": "triggered", "resolution": {"width_px": 1920, "height_px": 1080}}'::jsonb)
ON CONFLICT DO NOTHING;
INSERT INTO "transportation_sensors"."traffic_readings"
 ("reading_id", "sensor_id", "source_event_id", "recorded_at", "measurement_type", "numeric_value", "category_value", "unit")
VALUES ('00000000-0000-0000-0000-000000000017', '00000000-0000-0000-0000-000000000015', 'demo-speed-001', '2026-10-23T12:00:00+00:00', 'speed', 62.5, NULL, 'km/h')
ON CONFLICT DO NOTHING;
INSERT INTO "transportation_sensors"."transit_events"
 ("transit_event_id", "stop_id", "route_id", "vehicle_id", "source_event_id", "provider_id", "scheduled_at", "occurred_at")
VALUES ('00000000-0000-0000-0000-000000000018', '00000000-0000-0000-0000-000000000004', '501', 'demo-bus', 'demo-arrival-001', 'demo-transit', '2026-10-23T12:00:00+00:00', '2026-10-23T12:00:00+00:00')
ON CONFLICT DO NOTHING;
INSERT INTO "transportation_sensors"."capture_events"
 ("capture_id", "reading_id", "camera_id", "captured_at", "review_status")
VALUES ('00000000-0000-0000-0000-000000000019', '00000000-0000-0000-0000-000000000017', '00000000-0000-0000-0000-000000000016', '2026-10-23T12:00:00+00:00', 'pending')
ON CONFLICT DO NOTHING;
INSERT INTO "transportation_sensors"."capture_media"
 ("capture_id", "media_id", "evidence_role")
VALUES ('00000000-0000-0000-0000-000000000019', '00000000-0000-0000-0000-00000000000a', 'supporting')
ON CONFLICT DO NOTHING;

-- CRUD FOR EACH TABLE

-- MONITORING_UNITS

-- CREATE a disposable example
INSERT INTO "transportation_sensors"."monitoring_units"
 ("unit_id", "city_id", "road_id", "description", "location", "status")
VALUES ('a1f8eb33-82fa-4041-94c0-302b2ad38fa8', '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000002', 'Demo monitoring point', ST_GeomFromEWKT('SRID=4326;POINT(-79.3832 43.6532)'), 'active');

-- READ by the full primary key
SELECT * FROM "transportation_sensors"."monitoring_units" WHERE "unit_id" = 'a1f8eb33-82fa-4041-94c0-302b2ad38fa8';

-- UPDATE the disposable example
UPDATE "transportation_sensors"."monitoring_units" SET "description" = 'Reviewed monitoring point'
WHERE "unit_id" = 'a1f8eb33-82fa-4041-94c0-302b2ad38fa8';

-- DELETE only the disposable example (shared seed records remain)
DELETE FROM "transportation_sensors"."monitoring_units" WHERE "unit_id" = 'a1f8eb33-82fa-4041-94c0-302b2ad38fa8';

-- SENSORS

-- CREATE a disposable example
INSERT INTO "transportation_sensors"."sensors"
 ("sensor_id", "unit_id", "sensor_type", "status", "configuration")
VALUES ('26622530-f683-4dac-88ed-489bb424068c', '00000000-0000-0000-0000-000000000014', 'radar', 'active', '{"sampling_interval_seconds": 5, "measured_variables": ["speed_kmh"]}'::jsonb);

-- READ by the full primary key
SELECT * FROM "transportation_sensors"."sensors" WHERE "sensor_id" = '26622530-f683-4dac-88ed-489bb424068c';

-- UPDATE the disposable example
UPDATE "transportation_sensors"."sensors" SET "status" = 'maintenance', "updated_at" = '2026-10-23T12:00:00+00:00'
WHERE "sensor_id" = '26622530-f683-4dac-88ed-489bb424068c';

-- DELETE only the disposable example (shared seed records remain)
DELETE FROM "transportation_sensors"."sensors" WHERE "sensor_id" = '26622530-f683-4dac-88ed-489bb424068c';

-- SENSORS

-- CREATE a disposable example
INSERT INTO "transportation_sensors"."sensors"
 ("sensor_id", "unit_id", "sensor_type", "status", "configuration")
VALUES ('2e90a005-40db-4471-97b6-a276660ba218', '00000000-0000-0000-0000-000000000014', 'camera', 'active', '{"capture_mode": "triggered", "resolution": {"width_px": 1920, "height_px": 1080}}'::jsonb);

-- READ by the full primary key
SELECT * FROM "transportation_sensors"."sensors" WHERE "sensor_id" = '2e90a005-40db-4471-97b6-a276660ba218';

-- UPDATE the disposable example
UPDATE "transportation_sensors"."sensors" SET "status" = 'maintenance'
WHERE "sensor_id" = '2e90a005-40db-4471-97b6-a276660ba218';

-- DELETE only the disposable example (shared seed records remain)
DELETE FROM "transportation_sensors"."sensors" WHERE "sensor_id" = '2e90a005-40db-4471-97b6-a276660ba218';

-- TRAFFIC_READINGS

-- CREATE a disposable example
INSERT INTO "transportation_sensors"."traffic_readings"
 ("reading_id", "sensor_id", "source_event_id", "recorded_at", "measurement_type", "numeric_value", "category_value", "unit")
VALUES ('81fcb421-7612-4552-8bc5-aab976880b4e', '00000000-0000-0000-0000-000000000015', 'demo-9d668276-b4c3-4d5d-b3e7-5f003f16275f', '2026-10-23T12:00:00+00:00', 'speed', 62.5, NULL, 'km/h');

-- READ by the full primary key
SELECT * FROM "transportation_sensors"."traffic_readings" WHERE "reading_id" = '81fcb421-7612-4552-8bc5-aab976880b4e';

-- UPDATE the disposable example
UPDATE "transportation_sensors"."traffic_readings" SET "numeric_value" = 61.0
WHERE "reading_id" = '81fcb421-7612-4552-8bc5-aab976880b4e';

-- DELETE only the disposable example (shared seed records remain)
DELETE FROM "transportation_sensors"."traffic_readings" WHERE "reading_id" = '81fcb421-7612-4552-8bc5-aab976880b4e';

-- TRANSIT_EVENTS

-- CREATE a disposable example
INSERT INTO "transportation_sensors"."transit_events"
 ("transit_event_id", "stop_id", "route_id", "vehicle_id", "source_event_id", "provider_id", "scheduled_at", "occurred_at")
VALUES ('aafbaaca-d446-4a16-9b88-100d5d8a1273', '00000000-0000-0000-0000-000000000004', '501', 'demo-bus', 'demo-7b2b4843-6124-4b93-8d01-7ce424de5a2f', 'demo-transit', '2026-10-23T12:00:00+00:00', '2026-10-23T12:00:00+00:00');

-- READ by the full primary key
SELECT * FROM "transportation_sensors"."transit_events" WHERE "transit_event_id" = 'aafbaaca-d446-4a16-9b88-100d5d8a1273';

-- UPDATE the disposable example
UPDATE "transportation_sensors"."transit_events" SET "route_id" = '502'
WHERE "transit_event_id" = 'aafbaaca-d446-4a16-9b88-100d5d8a1273';

-- DELETE only the disposable example (shared seed records remain)
DELETE FROM "transportation_sensors"."transit_events" WHERE "transit_event_id" = 'aafbaaca-d446-4a16-9b88-100d5d8a1273';

-- CAPTURE_EVENTS

-- CREATE a disposable example
INSERT INTO "transportation_sensors"."capture_events"
 ("capture_id", "reading_id", "camera_id", "captured_at", "review_status")
VALUES ('12e11714-e161-4acc-a222-e2b5abc76903', '00000000-0000-0000-0000-000000000017', '00000000-0000-0000-0000-000000000016', '2026-10-23T12:00:00+00:00', 'pending');

-- READ by the full primary key
SELECT * FROM "transportation_sensors"."capture_events" WHERE "capture_id" = '12e11714-e161-4acc-a222-e2b5abc76903';

-- UPDATE the disposable example
UPDATE "transportation_sensors"."capture_events" SET "review_status" = 'accepted'
WHERE "capture_id" = '12e11714-e161-4acc-a222-e2b5abc76903';

-- DELETE only the disposable example (shared seed records remain)
DELETE FROM "transportation_sensors"."capture_events" WHERE "capture_id" = '12e11714-e161-4acc-a222-e2b5abc76903';

-- CAPTURE_MEDIA

-- CREATE a disposable example
INSERT INTO "transportation_sensors"."capture_media"
 ("capture_id", "media_id", "evidence_role")
VALUES ('00000000-0000-0000-0000-000000000019', '00000000-0000-0000-0000-00000000000b', 'supporting');

-- READ by the full primary key
SELECT * FROM "transportation_sensors"."capture_media" WHERE "capture_id" = '00000000-0000-0000-0000-000000000019' AND "media_id" = '00000000-0000-0000-0000-00000000000b';

-- UPDATE the disposable example
UPDATE "transportation_sensors"."capture_media" SET "evidence_role" = 'reviewed'
WHERE "capture_id" = '00000000-0000-0000-0000-000000000019' AND "media_id" = '00000000-0000-0000-0000-00000000000b';

-- DELETE only the disposable example (shared seed records remain)
DELETE FROM "transportation_sensors"."capture_media" WHERE "capture_id" = '00000000-0000-0000-0000-000000000019' AND "media_id" = '00000000-0000-0000-0000-00000000000b';

-- Bounded temporal READ and cross-schema relationship.
SELECT r.reading_id,r.recorded_at,r.numeric_value,rd.name AS road
FROM transportation_sensors.traffic_readings r
JOIN transportation_sensors.sensors s ON s.sensor_id=r.sensor_id
JOIN transportation_sensors.monitoring_units u ON u.unit_id=s.unit_id
LEFT JOIN road_and_facility_locations.roads rd ON rd.road_id=u.road_id
WHERE r.sensor_id='00000000-0000-0000-0000-000000000015'
AND r.recorded_at>='2026-10-23T00:00:00Z' AND r.recorded_at<'2026-10-24T00:00:00Z'
ORDER BY r.recorded_at DESC LIMIT 100;
COMMIT;
