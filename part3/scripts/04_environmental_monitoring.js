// Native mongosh script. Run from the project root after PostgreSQL script 01.
// Also implements the optional location-attribute collections from Part 2.
// PostgreSQL UUIDs are canonical strings; MongoDB has logical references, not FKs.
(() => {
  const fs = require('fs');
  const refs = JSON.parse(fs.readFileSync('part3/.runtime/location-references.json','utf8'));
  const id = n => '00000000-0000-0000-0000-'+n.toString(16).padStart(12,'0');
  const CITY=id(1), ROAD=id(2), FACILITY=id(3), now=ISODate('2026-10-23T12:00:00Z');
  const uuidSchema={bsonType:'string',pattern:'^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$'};
  const assert = (test,message) => {if(!test) throw new Error(message);};
  assert(db.version().split('.')[0] >= 8,'MongoDB 8.0 or newer is required');
  assert(refs.cities.includes(CITY),'Unknown PostgreSQL city');
  assert(refs.roads.includes(ROAD),'Unknown PostgreSQL road');
  assert(refs.facilities.includes(FACILITY),'Unknown PostgreSQL facility');
  // Snapshot validation is not an atomic cross-store transaction. Production
  // reference reconciliation and source retirement rules are still required.
  function ensureRegular(database,name,schema) {
    const info=database.getCollectionInfos({name})[0];
    if(!info) database.createCollection(name,{validator:{$jsonSchema:schema},validationLevel:'strict',validationAction:'error'});
    else {
      assert(!info.options.timeseries,name+' must be a regular collection');
      const result=database.runCommand({collMod:name,validator:{$jsonSchema:schema},validationLevel:'strict',validationAction:'error'});
      assert(result.ok===1,'Cannot update collection validator');
    }
    return database.getCollection(name);
  }
  function crud(collection,document,changes,key='_id') {
    // Use an actual source UUID for location documents: read/create-if-missing,
    // update and delete, then restore that same shared example for later use.
    collection.updateOne({[key]:document[key]},{$setOnInsert:document},{upsert:true}); // CREATE
    const original=collection.findOne({[key]:document[key]}); // READ
    assert(original!==null,'Read failed: '+collection.getName());
    assert(collection.updateOne({[key]:document[key]},{$set:changes}).matchedCount===1,'Update failed'); // UPDATE
    assert(collection.deleteOne({[key]:document[key]}).deletedCount===1,'Delete failed'); // DELETE
    collection.insertOne(original); // Preserve the shared fixture.
    print('CRUD OK: '+collection.getFullName());
  }

  const locations=db.getSiblingDB('srsp_location_attributes');
  const attributeBase={bsonType:'object',required:['_id','attributes','created_at','updated_at'],properties:{
    _id:uuidSchema,attributes:{bsonType:'object'},created_at:{bsonType:'date'},updated_at:{bsonType:'date'}}};
  const roadSchema=JSON.parse(JSON.stringify(attributeBase));
  roadSchema.properties.attributes={bsonType:'object',additionalProperties:false,properties:{
    surface_material:{bsonType:'string'},lane_count:{bsonType:'int',minimum:1},
    cycle_lane_present:{bsonType:'bool'},sidewalk_present:{bsonType:'bool'}}};
  const facilitySchema=JSON.parse(JSON.stringify(attributeBase));
  facilitySchema.properties.attributes={bsonType:'object',additionalProperties:false,properties:{
    building_capacity_persons:{bsonType:'int',minimum:0},accessible_entrance:{bsonType:'bool'},
    parking_space_count:{bsonType:'int',minimum:0},park_amenities:{bsonType:'array',items:{bsonType:'string'}},bus_stop_shelter:{bsonType:'bool'}}};
  const roadAttributes=ensureRegular(locations,'road_attributes',roadSchema);
  const facilityAttributes=ensureRegular(locations,'facility_attributes',facilitySchema);
  crud(roadAttributes,{_id:ROAD,attributes:{surface_material:'asphalt',lane_count:Int32(2),cycle_lane_present:true},created_at:now,updated_at:now},
    {'attributes.lane_count':Int32(3),updated_at:now});
  crud(facilityAttributes,{_id:FACILITY,attributes:{building_capacity_persons:Int32(250),accessible_entrance:true},created_at:now,updated_at:now},
    {'attributes.building_capacity_persons':Int32(260),updated_at:now});

  const env=db.getSiblingDB('srsp_environment');
  const devices=ensureRegular(env,'monitoring_devices',{bsonType:'object',
    required:['_id','city_id','location','status','configuration','updated_at'],properties:{
      _id:{bsonType:'string'},city_id:uuidSchema,facility_id:uuidSchema,
      location:{bsonType:'object',required:['type','coordinates'],properties:{type:{enum:['Point']},
        coordinates:{bsonType:'array',minItems:2,maxItems:2,items:{bsonType:'double'}}}},
      status:{enum:['active','inactive','maintenance']},updated_at:{bsonType:'date'},
      configuration:{bsonType:'object',required:['sampling_interval_seconds','metrics'],properties:{
        sampling_interval_seconds:{bsonType:'int',minimum:1},metrics:{bsonType:'array',minItems:1,
          items:{bsonType:'object',required:['metric','unit'],properties:{metric:{bsonType:'string'},unit:{bsonType:'string'}}}}}}}});
  const events=ensureRegular(env,'environmental_events',{bsonType:'object',
    required:['_id','city_id','event_type','occurred_at','details'],properties:{_id:{bsonType:'string'},
      city_id:uuidSchema,device_id:{bsonType:'string'},reading_id:{bsonType:'string'},
      event_type:{enum:['weather_event','elevated_water_level','temperature_observation']},
      occurred_at:{bsonType:'date'},details:{bsonType:'object'}}});
  const ts={timeField:'recorded_at',metaField:'metadata',granularity:'seconds'};
  const existing=env.getCollectionInfos({name:'environmental_readings'})[0];
  if(!existing) env.createCollection('environmental_readings',{timeseries:ts});
  else for(const field of Object.keys(ts)) assert(existing.options.timeseries?.[field]===ts[field],'Incompatible time-series options');
  const readings=env.getCollection('environmental_readings');
  devices.createIndex({location:'2dsphere'},{name:'device_location_geo'});
  readings.createIndex({'metadata.device_id':1,recorded_at:-1},{name:'device_time_idx'});
  events.createIndex({city_id:1,occurred_at:-1},{name:'event_city_time_idx'});

  const device={_id:'demo-env-device-001',city_id:CITY,facility_id:FACILITY,
    location:{type:'Point',coordinates:[-79.3832,43.6532]},status:'active',
    configuration:{sampling_interval_seconds:Int32(10),metrics:[{metric:'temperature',unit:'degC'}]},updated_at:now};
  // Use a disposable device for DELETE, so readings never lose their parent.
  devices.updateOne({_id:device._id},{$setOnInsert:device},{upsert:true});
  crud(devices,{...device,_id:'demo-env-device-crud'},{status:'maintenance',updated_at:now});
  devices.deleteOne({_id:'demo-env-device-crud'});

  function validateReading(r) {
    assert(typeof r.reading_id==='string' && r.reading_id.length>0,'Invalid reading ID');
    assert(r.recorded_at instanceof Date && r.received_at instanceof Date,'Date fields required');
    assert(typeof r.value==='number' && Number.isFinite(r.value),'Finite numeric value required');
    assert(['valid','suspect','invalid'].includes(r.quality_status),'Invalid quality status');
    const parent=devices.findOne({_id:r.metadata.device_id});
    assert(parent && parent.city_id===r.metadata.city_id,'Unknown device or city mismatch');
    assert(parent.configuration.metrics.some(m=>m.metric===r.metadata.metric && m.unit===r.metadata.unit),'Unsupported metric/unit');
  }
  const reading={reading_id:'demo-env-reading-001',recorded_at:now,
    metadata:{device_id:device._id,city_id:CITY,metric:'temperature',unit:'degC'},value:21.5,quality_status:'valid',received_at:now};
  validateReading(reading);
  // Serial demonstration deduplication only; no unique index is supported here.
  if(!readings.findOne({reading_id:reading.reading_id})) readings.insertOne(reading); // CREATE
  printjson(readings.find({'metadata.device_id':device._id,recorded_at:{$gte:now,$lt:ISODate('2026-10-24T00:00:00Z')}}).limit(100).toArray()); // READ

  const event={_id:'demo-env-event-001',device_id:device._id,reading_id:reading.reading_id,city_id:CITY,
    event_type:'temperature_observation',occurred_at:now,details:{message:'Routine temperature observation'}};
  assert(readings.findOne({reading_id:event.reading_id}),'Missing event reading');
  events.updateOne({_id:event._id},{$setOnInsert:event},{upsert:true});
  crud(events,{...event,_id:'demo-env-event-crud'},{details:{message:'Reviewed observation'}});
  events.deleteOne({_id:'demo-env-event-crud'});

  // Time-series UPDATE may only match/change metadata, with updateMany.
  // No JSON Schema validator or unique reading_id index is claimed for readings.
  const tempDevice={...device,_id:'demo-env-temp-series'};
  devices.updateOne({_id:tempDevice._id},{$setOnInsert:tempDevice},{upsert:true});
  const tempReading={...reading,reading_id:'demo-env-temp-reading',metadata:{...reading.metadata,device_id:tempDevice._id}};
  // Idempotent cleanup of this isolated temporary series if an earlier run failed.
  readings.deleteMany({'metadata.device_id':tempDevice._id});
  validateReading(tempReading);readings.insertOne(tempReading); // CREATE
  assert(readings.findOne({reading_id:tempReading.reading_id}),'Missing temporary reading'); // READ
  assert(readings.updateMany({'metadata.device_id':tempDevice._id},{$set:{'metadata.calibration_revision':Int32(1)}}).matchedCount===1,'Metadata update failed'); // UPDATE
  assert(readings.deleteMany({'metadata.device_id':tempDevice._id}).deletedCount===1,'Series deletion failed'); // DELETE
  devices.deleteOne({_id:tempDevice._id});
  print('CRUD OK: srsp_environment.environmental_readings');

  // Native export consumed by SQL script 08; grouping preserves metric and unit.
  const summaries=readings.aggregate([
    {$match:{quality_status:'valid',recorded_at:{$gte:ISODate('2026-10-23T04:00:00Z'),$lt:ISODate('2026-10-24T04:00:00Z')}}},
    {$group:{_id:{day:{$dateToString:{format:'%Y-%m-%d',date:'$recorded_at',timezone:'America/Toronto'}},city:'$metadata.city_id',metric:'$metadata.metric',unit:'$metadata.unit'},
      samples:{$sum:1},minimum:{$min:'$value'},maximum:{$max:'$value'},average:{$avg:'$value'}}}
  ]).toArray();
  const csv=value=>'"'+String(value).replaceAll('"','""')+'"';
  const lines=['day,city_id,metric,unit,samples,minimum,maximum,average'];
  for(const s of summaries) lines.push([s._id.day,s._id.city,s._id.metric,s._id.unit,s.samples,s.minimum,s.maximum,s.average].map(csv).join(','));
  fs.writeFileSync('part3/.runtime/environmental.csv',lines.join('\n')+'\n');
  print('04 complete; environmental summaries exported for PostgreSQL script 08');
})();
