-- ROAD_AND_FACILITY_LOCATIONS | native PostgreSQL / psql script
-- Run from the project root in numeric order. All changes use a local SQL transaction.
\set ON_ERROR_STOP on
\if :{?operational_db}
\else
\set operational_db srsp_operational
\endif
-- PostgreSQL has no CREATE DATABASE IF NOT EXISTS. Run this outside BEGIN.
SELECT format('CREATE DATABASE %I', :'operational_db')
WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = :'operational_db')\gexec
\connect :operational_db
SET TIME ZONE 'UTC';
BEGIN;


CREATE EXTENSION IF NOT EXISTS postgis;
CREATE SCHEMA IF NOT EXISTS road_and_facility_locations;
CREATE TABLE IF NOT EXISTS road_and_facility_locations.cities (
 city_id UUID PRIMARY KEY, name TEXT NOT NULL,
 boundary geometry(MultiPolygon,4326),
 created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
 CHECK(boundary IS NULL OR ST_IsValid(boundary))
);
CREATE TABLE IF NOT EXISTS road_and_facility_locations.roads (
 road_id UUID PRIMARY KEY, city_id UUID NOT NULL REFERENCES road_and_facility_locations.cities(city_id),
 name TEXT, road_type TEXT NOT NULL CHECK(road_type IN ('local','arterial','highway')),
 status TEXT NOT NULL CHECK(status IN ('open','restricted','closed')),
 geometry geometry(LineString,4326) NOT NULL,
 created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
 UNIQUE(road_id,city_id), CHECK(ST_IsValid(geometry) AND NOT ST_IsEmpty(geometry))
);
CREATE TABLE IF NOT EXISTS road_and_facility_locations.facilities (
 facility_id UUID PRIMARY KEY, city_id UUID NOT NULL REFERENCES road_and_facility_locations.cities(city_id),
 name TEXT NOT NULL, facility_type TEXT NOT NULL CHECK(facility_type IN ('public_building','park','parking_lot','bus_stop')),
 status TEXT NOT NULL CHECK(status IN ('operational','restricted','closed')),
 location geometry(Point,4326) NOT NULL, footprint geometry(MultiPolygon,4326),
 created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
 UNIQUE(facility_id,city_id), CHECK(NOT ST_IsEmpty(location)),
 CHECK(footprint IS NULL OR ST_IsValid(footprint))
);
CREATE TABLE IF NOT EXISTS road_and_facility_locations.service_zones (
 zone_id UUID PRIMARY KEY, city_id UUID NOT NULL REFERENCES road_and_facility_locations.cities(city_id),
 name TEXT NOT NULL, service_type TEXT NOT NULL CHECK(service_type IN ('emergency_response','maintenance','waste_collection')),
 boundary geometry(MultiPolygon,4326) NOT NULL, is_active BOOLEAN NOT NULL DEFAULT true,
 created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
 UNIQUE(zone_id,city_id), CHECK(ST_IsValid(boundary) AND NOT ST_IsEmpty(boundary))
);
CREATE INDEX IF NOT EXISTS facilities_geography_gix ON road_and_facility_locations.facilities USING gist ((location::geography));
CREATE INDEX IF NOT EXISTS roads_geometry_gix ON road_and_facility_locations.roads USING gist(geometry);
CREATE INDEX IF NOT EXISTS zones_boundary_gix ON road_and_facility_locations.service_zones USING gist(boundary);
CREATE INDEX IF NOT EXISTS roads_city_idx ON road_and_facility_locations.roads(city_id);
CREATE INDEX IF NOT EXISTS facilities_city_idx ON road_and_facility_locations.facilities(city_id);


-- Shared, deterministic seed records
INSERT INTO "road_and_facility_locations"."cities"
 ("city_id", "name", "boundary")
VALUES ('00000000-0000-0000-0000-000000000001', 'Demo Toronto', ST_GeomFromEWKT('SRID=4326;MULTIPOLYGON(((-79.5 43.5,-79.2 43.5,-79.2 43.8,-79.5 43.8,-79.5 43.5)))'))
ON CONFLICT DO NOTHING;
INSERT INTO "road_and_facility_locations"."roads"
 ("road_id", "city_id", "name", "road_type", "status", "geometry")
VALUES ('00000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000001', 'Demo Road', 'local', 'open', ST_GeomFromEWKT('SRID=4326;LINESTRING(-79.39 43.65,-79.38 43.66)'))
ON CONFLICT DO NOTHING;
INSERT INTO "road_and_facility_locations"."facilities"
 ("facility_id", "city_id", "name", "facility_type", "status", "location")
VALUES ('00000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000001', 'Demo Community Centre', 'public_building', 'operational', ST_GeomFromEWKT('SRID=4326;POINT(-79.3832 43.6532)'))
ON CONFLICT DO NOTHING;
INSERT INTO "road_and_facility_locations"."facilities"
 ("facility_id", "city_id", "name", "facility_type", "status", "location")
VALUES ('00000000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000001', 'Demo Bus Stop', 'bus_stop', 'operational', ST_GeomFromEWKT('SRID=4326;POINT(-79.3832 43.6532)'))
ON CONFLICT DO NOTHING;
INSERT INTO "road_and_facility_locations"."service_zones"
 ("zone_id", "city_id", "name", "service_type", "boundary", "is_active")
VALUES ('00000000-0000-0000-0000-000000000005', '00000000-0000-0000-0000-000000000001', 'Demo Emergency Zone', 'emergency_response', ST_GeomFromEWKT('SRID=4326;MULTIPOLYGON(((-79.5 43.5,-79.2 43.5,-79.2 43.8,-79.5 43.8,-79.5 43.5)))'), TRUE)
ON CONFLICT DO NOTHING;

-- CRUD FOR EACH TABLE

-- CITIES

-- CREATE a disposable example
INSERT INTO "road_and_facility_locations"."cities"
 ("city_id", "name", "boundary")
VALUES ('a8009a6b-46e3-4e83-a261-4bda8c60408f', 'Demo Toronto', ST_GeomFromEWKT('SRID=4326;MULTIPOLYGON(((-79.5 43.5,-79.2 43.5,-79.2 43.8,-79.5 43.8,-79.5 43.5)))'));

-- READ by the full primary key
SELECT * FROM "road_and_facility_locations"."cities" WHERE "city_id" = 'a8009a6b-46e3-4e83-a261-4bda8c60408f';

-- UPDATE the disposable example
UPDATE "road_and_facility_locations"."cities" SET "name" = 'Demo Toronto reviewed'
WHERE "city_id" = 'a8009a6b-46e3-4e83-a261-4bda8c60408f';

-- DELETE only the disposable example (shared seed records remain)
DELETE FROM "road_and_facility_locations"."cities" WHERE "city_id" = 'a8009a6b-46e3-4e83-a261-4bda8c60408f';

-- ROADS

-- CREATE a disposable example
INSERT INTO "road_and_facility_locations"."roads"
 ("road_id", "city_id", "name", "road_type", "status", "geometry")
VALUES ('18bbefdb-53cd-434c-95c1-346e76f7d08d', '00000000-0000-0000-0000-000000000001', 'Demo Road', 'local', 'open', ST_GeomFromEWKT('SRID=4326;LINESTRING(-79.39 43.65,-79.38 43.66)'));

-- READ by the full primary key
SELECT * FROM "road_and_facility_locations"."roads" WHERE "road_id" = '18bbefdb-53cd-434c-95c1-346e76f7d08d';

-- UPDATE the disposable example
UPDATE "road_and_facility_locations"."roads" SET "name" = 'Demo Road reviewed'
WHERE "road_id" = '18bbefdb-53cd-434c-95c1-346e76f7d08d';

-- DELETE only the disposable example (shared seed records remain)
DELETE FROM "road_and_facility_locations"."roads" WHERE "road_id" = '18bbefdb-53cd-434c-95c1-346e76f7d08d';

-- FACILITIES

-- CREATE a disposable example
INSERT INTO "road_and_facility_locations"."facilities"
 ("facility_id", "city_id", "name", "facility_type", "status", "location")
VALUES ('d6b6602f-4118-48be-a7f3-8b49144f4cf1', '00000000-0000-0000-0000-000000000001', 'Demo Community Centre', 'public_building', 'operational', ST_GeomFromEWKT('SRID=4326;POINT(-79.3832 43.6532)'));

-- READ by the full primary key
SELECT * FROM "road_and_facility_locations"."facilities" WHERE "facility_id" = 'd6b6602f-4118-48be-a7f3-8b49144f4cf1';

-- UPDATE the disposable example
UPDATE "road_and_facility_locations"."facilities" SET "name" = 'Demo Community Centre reviewed'
WHERE "facility_id" = 'd6b6602f-4118-48be-a7f3-8b49144f4cf1';

-- DELETE only the disposable example (shared seed records remain)
DELETE FROM "road_and_facility_locations"."facilities" WHERE "facility_id" = 'd6b6602f-4118-48be-a7f3-8b49144f4cf1';

-- FACILITIES

-- CREATE a disposable example
INSERT INTO "road_and_facility_locations"."facilities"
 ("facility_id", "city_id", "name", "facility_type", "status", "location")
VALUES ('453a54bb-56a6-490c-8cc8-d283b8ef6742', '00000000-0000-0000-0000-000000000001', 'Demo Bus Stop', 'bus_stop', 'operational', ST_GeomFromEWKT('SRID=4326;POINT(-79.3832 43.6532)'));

-- READ by the full primary key
SELECT * FROM "road_and_facility_locations"."facilities" WHERE "facility_id" = '453a54bb-56a6-490c-8cc8-d283b8ef6742';

-- UPDATE the disposable example
UPDATE "road_and_facility_locations"."facilities" SET "name" = 'Demo Bus Stop reviewed'
WHERE "facility_id" = '453a54bb-56a6-490c-8cc8-d283b8ef6742';

-- DELETE only the disposable example (shared seed records remain)
DELETE FROM "road_and_facility_locations"."facilities" WHERE "facility_id" = '453a54bb-56a6-490c-8cc8-d283b8ef6742';

-- SERVICE_ZONES

-- CREATE a disposable example
INSERT INTO "road_and_facility_locations"."service_zones"
 ("zone_id", "city_id", "name", "service_type", "boundary", "is_active")
VALUES ('5e155a54-d1a9-4c66-bfe3-32806daef580', '00000000-0000-0000-0000-000000000001', 'Demo Emergency Zone', 'emergency_response', ST_GeomFromEWKT('SRID=4326;MULTIPOLYGON(((-79.5 43.5,-79.2 43.5,-79.2 43.8,-79.5 43.8,-79.5 43.5)))'), TRUE);

-- READ by the full primary key
SELECT * FROM "road_and_facility_locations"."service_zones" WHERE "zone_id" = '5e155a54-d1a9-4c66-bfe3-32806daef580';

-- UPDATE the disposable example
UPDATE "road_and_facility_locations"."service_zones" SET "name" = 'Demo Emergency Zone reviewed'
WHERE "zone_id" = '5e155a54-d1a9-4c66-bfe3-32806daef580';

-- DELETE only the disposable example (shared seed records remain)
DELETE FROM "road_and_facility_locations"."service_zones" WHERE "zone_id" = '5e155a54-d1a9-4c66-bfe3-32806daef580';

-- Spatial READ; the geography expression matches the GiST expression index.
SELECT facility_id,name FROM road_and_facility_locations.facilities
WHERE ST_DWithin(location::geography,
 ST_SetSRID(ST_MakePoint(-79.3832,43.6532),4326)::geography,1000);
COMMIT;
-- Snapshot for validating logical references in script 04 (mongosh).
\copy (SELECT json_build_object('cities',(SELECT json_agg(city_id::text) FROM road_and_facility_locations.cities),'roads',(SELECT json_agg(road_id::text) FROM road_and_facility_locations.roads),'facilities',(SELECT json_agg(facility_id::text) FROM road_and_facility_locations.facilities))) TO 'part3/.runtime/location-references.json'
