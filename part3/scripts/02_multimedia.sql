-- MULTIMEDIA | native PostgreSQL / psql script
-- Run from the project root in numeric order. All changes use a local SQL transaction.
\set ON_ERROR_STOP on
\if :{?operational_db}
\else
\set operational_db srsp_operational
\endif
\connect :operational_db
SET TIME ZONE 'UTC';
BEGIN;


CREATE SCHEMA IF NOT EXISTS multimedia;
CREATE TABLE IF NOT EXISTS multimedia.media_assets (
 media_id UUID PRIMARY KEY,
 media_type TEXT NOT NULL CHECK(media_type IN ('image','video','audio')),
 mime_type TEXT NOT NULL, original_filename TEXT NOT NULL,
 size_bytes BIGINT NOT NULL CHECK(size_bytes >= 0),
 source_channel TEXT NOT NULL CHECK(source_channel IN ('citizen_portal','field_inspection','traffic_camera')),
 storage_bucket TEXT NOT NULL, storage_key TEXT NOT NULL,
 upload_status TEXT NOT NULL CHECK(upload_status IN ('pending','available','failed')),
 checksum_sha256 TEXT CHECK(checksum_sha256 ~ '^[a-f0-9]{64}$'),
 duration_seconds NUMERIC(12,3) CHECK(duration_seconds>=0),
 captured_at TIMESTAMPTZ, received_at TIMESTAMPTZ NOT NULL DEFAULT now(),
 UNIQUE(storage_bucket,storage_key),
 CHECK(media_type <> 'image' OR duration_seconds IS NULL),
 CHECK(upload_status <> 'available' OR checksum_sha256 IS NOT NULL)
);
CREATE INDEX IF NOT EXISTS media_received_idx ON multimedia.media_assets(received_at DESC);


-- Shared, deterministic seed records
INSERT INTO "multimedia"."media_assets"
 ("media_id", "media_type", "mime_type", "original_filename", "size_bytes", "source_channel", "storage_bucket", "storage_key", "upload_status", "received_at")
VALUES ('00000000-0000-0000-0000-00000000000a', 'image', 'image/png', 'demo-evidence.png', 0, 'citizen_portal', 'configure-your-s3-bucket', 'coursework/00000000-0000-0000-0000-00000000000a/demo-evidence.png', 'pending', '2026-10-23T12:00:00+00:00')
ON CONFLICT DO NOTHING;
INSERT INTO "multimedia"."media_assets"
 ("media_id", "media_type", "mime_type", "original_filename", "size_bytes", "source_channel", "storage_bucket", "storage_key", "upload_status", "received_at")
VALUES ('00000000-0000-0000-0000-00000000000b', 'image', 'image/png', 'demo-evidence.png', 0, 'citizen_portal', 'configure-your-s3-bucket', 'coursework/00000000-0000-0000-0000-00000000000b/demo-evidence.png', 'pending', '2026-10-23T12:00:00+00:00')
ON CONFLICT DO NOTHING;

-- CRUD FOR EACH TABLE

-- MEDIA_ASSETS

-- CREATE a disposable example
INSERT INTO "multimedia"."media_assets"
 ("media_id", "media_type", "mime_type", "original_filename", "size_bytes", "source_channel", "storage_bucket", "storage_key", "upload_status", "received_at")
VALUES ('9999dde0-cd6f-4023-abbd-414fe3538db2', 'image', 'image/png', 'demo-evidence.png', 0, 'citizen_portal', 'configure-your-s3-bucket', 'coursework/disposable/54370af2-30df-4146-a5f6-b3214f335666.png', 'pending', '2026-10-23T12:00:00+00:00');

-- READ by the full primary key
SELECT * FROM "multimedia"."media_assets" WHERE "media_id" = '9999dde0-cd6f-4023-abbd-414fe3538db2';

-- UPDATE the disposable example
UPDATE "multimedia"."media_assets" SET "original_filename" = 'reviewed.png', "upload_status" = 'failed'
WHERE "media_id" = '9999dde0-cd6f-4023-abbd-414fe3538db2';

-- DELETE only the disposable example (shared seed records remain)
DELETE FROM "multimedia"."media_assets" WHERE "media_id" = '9999dde0-cd6f-4023-abbd-414fe3538db2';

-- MEDIA_ASSETS

-- CREATE a disposable example
INSERT INTO "multimedia"."media_assets"
 ("media_id", "media_type", "mime_type", "original_filename", "size_bytes", "source_channel", "storage_bucket", "storage_key", "upload_status", "received_at")
VALUES ('b18adb9c-0c44-40ad-a50a-46c71b26a377', 'image', 'image/png', 'demo-evidence.png', 0, 'citizen_portal', 'configure-your-s3-bucket', 'coursework/disposable/9ba3ae72-e7ba-4abb-a204-0315e00d8a36.png', 'pending', '2026-10-23T12:00:00+00:00');

-- READ by the full primary key
SELECT * FROM "multimedia"."media_assets" WHERE "media_id" = 'b18adb9c-0c44-40ad-a50a-46c71b26a377';

-- UPDATE the disposable example
UPDATE "multimedia"."media_assets" SET "original_filename" = 'reviewed.png', "upload_status" = 'failed'
WHERE "media_id" = 'b18adb9c-0c44-40ad-a50a-46c71b26a377';

-- DELETE only the disposable example (shared seed records remain)
DELETE FROM "multimedia"."media_assets" WHERE "media_id" = 'b18adb9c-0c44-40ad-a50a-46c71b26a377';

-- SQL manages metadata only. These seeds remain pending: no file was uploaded.
-- S3 PutObject/GetObject/DeleteObject must be performed by the upload service.
-- After checksum verification, the service can mark its record available:
-- UPDATE multimedia.media_assets SET upload_status='available',
-- checksum_sha256=:verified_sha256,size_bytes=:verified_size WHERE media_id=:media_id;
SELECT media_id,storage_bucket,storage_key,upload_status FROM multimedia.media_assets;
COMMIT;
