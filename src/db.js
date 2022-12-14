const { Pool } = require("pg");
const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
});

function hasParams(obj) {
  for (_ in obj) return true;
  return false;
}

async function insertTealine({
  item_code,
  invoice_no,
  grade,
  no_of_bags,
  weight_per_bag,
  broker,
  garden,
}) {
  const client = await pool.connect();

  const tealineQuery =
    "WITH new_row AS (" +
    "  INSERT INTO item(item_code) VALUES ($1) RETURNING created_ts" +
    ") " +
    "INSERT INTO tealine" +
    "(item_code, created_ts, invoice_no, grade, no_of_bags, weight_per_bag, broker, garden) " +
    "SELECT $1, created_ts, $2, $3, $4, $5, $6, $7 " +
    "FROM new_row " +
    "RETURNING created_ts;";
  const tealineQueryRes = await client.query(tealineQuery, [
    item_code,
    invoice_no,
    grade,
    no_of_bags,
    weight_per_bag,
    broker,
    garden,
  ]);

  client.release();
  return {
    item_code,
    created_ts: tealineQueryRes.rows[0].created_ts,
  };
}

async function readTealine(data) {
  const client = await pool.connect();

  const tealineQueryParams = [
    "SELECT t.item_code, t.created_ts, t.broker, t.garden " +
      "FROM tealine t " +
      "WHERE t.no_of_bags != (" +
      "  SELECT COUNT(tr.*) " +
      "  FROM tealine_record tr " +
      "  WHERE tr.item_code = t.item_code " +
      "  AND tr.created_ts = t.created_ts" +
      ");",
  ];
  if (hasParams(data)) {
    tealineQueryParams[0] =
      "WITH record_rows AS (" +
      "  SELECT item_code, created_ts, " +
      "  row_to_json(tealine_record)::jsonb - '{item_code,created_ts,status,remaining}'::text[] " +
      "  AS record_data " +
      "  FROM tealine_record" +
      ") " +
      "SELECT t.item_code, t.created_ts, t.invoice_no, t.grade, t.no_of_bags, t.broker, " +
      "t.garden, array_remove(array_agg(r.record_data), NULL) AS record_list " +
      "FROM tealine t LEFT JOIN record_rows r " +
      "ON t.item_code = r.item_code AND t.created_ts = r.created_ts " +
      `WHERE ${Object.keys(data)
        .map((key, index) => `t.${key} = $${index + 1}`)
        .join(" AND ")}` +
      "GROUP BY t.item_code, t.created_ts;";
    // "SELECT t.item_code, t.created_ts, t.invoice_no, t.grade, " +
    // "t.no_of_bags, t.broker, t.garden, ARRAY_AGG(json_build_object( " +
    // "  'barcode', tr.barcode, " +
    // "  'store_location', tr.store_location, " +
    // "  'received_ts', tr.received_ts, " +
    // "  'gross_weight', tr.gross_weight, " +
    // "  'bag_weight', tr.bag_weight" +
    // ")) AS record_list " +
    // "FROM tealine t, tealine_record tr " +
    // "WHERE tr.item_code = t.item_code AND tr.created_ts = t.created_ts " +
    // `AND ${Object.keys(data)
    //   .map((key, index) => `t.${key} = $${index + 1}`)
    //   .join(" AND ")} ` +
    // "GROUP BY t.item_code, t.created_ts;";
    tealineQueryParams.push(Object.keys(data).map((key) => data[key]));
  }
  const tealineQueryRes = await client.query.apply(client, tealineQueryParams);

  client.release();
  return hasParams(data) ? tealineQueryRes.rows[0] : tealineQueryRes.rows;
}

async function insertTealineRecord({
  item_code,
  created_ts,
  store_location,
  gross_weight,
  bag_weight,
}) {
  const client = await pool.connect();

  const tealineRecordQuery =
    "INSERT INTO tealine_record(item_code, created_ts, store_location, gross_weight, bag_weight) " +
    "VALUES ($1, $2, $3, $4, $5) RETURNING received_ts, barcode;";
  const tealineRecordQueryRes = await client.query(tealineRecordQuery, [
    item_code,
    created_ts,
    store_location,
    gross_weight,
    bag_weight,
  ]);

  client.release();
  return {
    item_code,
    created_ts,
    received_ts: tealineRecordQueryRes.rows[0].received_ts,
    barcode: tealineRecordQueryRes.rows[0].barcode,
  };
}

async function updateTealineRecordStatus({ barcode, reduced_by }) {
  const client = await pool.connect();

  const tealineRecordQueryParams = [
    "UPDATE tealine_record " +
      "SET status = 'DISPATCHED' " +
      "WHERE barcode = $1 " +
      "RETURNING barcode, status;",
    [barcode],
  ];
  if (reduced_by) {
    tealineRecordQueryParams[0] =
      "WITH query_row AS (" +
      "  SELECT remaining - $2 AS remaining, barcode " +
      "  FROM tealine_record " +
      "  WHERE barcode = $1" +
      ")" +
      "UPDATE tealine_record " +
      "SET status = CASE " +
      "  WHEN query_row.remaining = 0 THEN 'PROCESSED' " +
      "  ELSE 'IN_PROCESS' " +
      "END, remaining = query_row.remaining " +
      "FROM query_row " +
      "WHERE tealine_record.barcode = query_row.barcode " +
      "RETURNING tealine_record.barcode, status;";
    tealineRecordQueryParams[1].push(reduced_by);
  }
  const tealineRecordQueryRes = await client.query.apply(
    client,
    tealineRecordQueryParams
  );

  client.release();
  return tealineRecordQueryRes.rows[0];
}

async function insertBlendsheet({
  item_code,
  blendsheet_no,
  standard,
  grade,
  remarks,
  no_of_batches,
  tealine,
}) {
  console.log(tealine);
  const client = await pool.connect();

  const blendsheetQuery =
    "WITH new_row AS (" +
    "  INSERT INTO item(item_code) VALUES ($1) RETURNING created_ts " +
    "), blend_row AS (" +
    "  INSERT INTO blendsheet" +
    "  (item_code, created_ts, blendsheet_no, standard, grade, remarks, no_of_batches) " +
    "  SELECT $1, created_ts, $2, $3, $4, $5, $6 " +
    "  FROM new_row " +
    "), blend_mix_row AS (" +
    "  INSERT INTO blendsheet_mix" +
    "  (blendsheet_no, tealine_code, no_of_bags) " +
    "  SELECT $2, unnest($7::json[])->>'tealine_code', (unnest($7::json[])->>'no_of_bags')::integer" +
    ") SELECT created_ts FROM new_row;";
  const blendsheetQueryRes = await client.query(blendsheetQuery, [
    item_code,
    blendsheet_no,
    standard,
    grade,
    remarks,
    no_of_batches,
    tealine,
  ]);

  client.release();
  return {
    item_code,
    created_ts: blendsheetQueryRes.rows[0].created_ts,
  };
}

async function readBlendsheet(data) {
  const client = await pool.connect();

  const blendsheetQueryParams = [
    "WITH query_row AS (" +
      " SELECT bool_or(active) AS active, " +
      "  json_agg(json_build_object(" +
      "    'item_code', item_code, " +
      "    'created_ts', created_ts, " +
      "    'blendsheet_no', blendsheet_no" +
      "  )) AS data FROM blendsheet" +
      ") SELECT active, CASE " +
      "  WHEN NOT active THEN data " +
      "END AS data FROM query_row;",
  ];
  if (hasParams(data)) {
    blendsheetQueryParams[0] =
      "SELECT b.item_code, b.created_ts, b.blendsheet_no, b.no_of_batches, b.batches_completed, " +
      "json_agg(" +
      "  json_build_object('tealine_code', bm.tealine_code, 'no_of_bags', bm.no_of_bags)" +
      ") AS tealine " +
      "FROM blendsheet b INNER JOIN blendsheet_mix bm " +
      "USING(blendsheet_no) " +
      `WHERE ${Object.keys(data)
        .map((key, index) => `b.${key} = $${index + 1}`)
        .join(" AND ")} ` +
      "GROUP BY item_code, created_ts;";
    blendsheetQueryParams.push(Object.keys(data).map((key) => data[key]));
  }
  const blendsheetQueryRes = await client.query.apply(
    client,
    blendsheetQueryParams
  );

  client.release();
  return hasParams(data)
    ? blendsheetQueryRes.rows[0]
    : Object.keys(blendsheetQueryRes.rows[0]).reduce(
        (obj, key) =>
          blendsheetQueryRes.rows[0][key] !== null
            ? { ...obj, [key]: blendsheetQueryRes.rows[0][key] }
            : obj,
        {}
      );
}

async function updateBlendsheetBatch({ item_code, created_ts }) {
  const client = await pool.connect();

  const blendsheetQuery =
    "UPDATE blendsheet " +
    "SET batches_completed = batches_completed + 1, active = TRUE " +
    "WHERE item_code = $1 AND created_ts = $2 " +
    "RETURNING batches_completed, active;";
  const blendsheetQueryRes = await client.query(blendsheetQuery, [
    item_code,
    created_ts,
  ]);

  client.release();
  return {
    item_code,
    created_ts,
    batches_completed: blendsheetQueryRes.rows[0].batches_completed,
    active: blendsheetQueryRes.rows[0].active,
  };
}

async function updateBlendsheetBatchInactive({ item_code, created_ts }) {
  const client = await pool.connect();

  const blendsheetQuery =
    "UPDATE blendsheet " +
    "SET active = FALSE " +
    "WHERE item_code = $1 AND created_ts = $2 " +
    "RETURNING active;";
  const blendsheetQueryRes = await client.query(blendsheetQuery, [
    item_code,
    created_ts,
  ]);

  client.release();
  return {
    item_code,
    created_ts,
    active: blendsheetQueryRes.rows[0].active,
  };
}

async function insertBlendsheetRecord({
  item_code,
  created_ts,
  store_location,
  gross_weight,
  bag_weight,
}) {
  const client = await pool.connect();

  const blendsheetRecordQuery =
    "INSERT INTO blendsheet_record(item_code, created_ts, store_location, gross_weight, bag_weight) " +
    "VALUES ($1, $2, $3, $4, $5) RETURNING received_ts, barcode;";
  const blendsheetRecordQueryRes = await client.query(blendsheetRecordQuery, [
    item_code,
    created_ts,
    store_location,
    gross_weight,
    bag_weight,
  ]);

  client.release();
  return {
    item_code,
    created_ts,
    received_ts: blendsheetRecordQueryRes.rows[0].received_ts,
    barcode: blendsheetRecordQueryRes.rows[0].barcode,
  };
}
// start of flavorsheet
//insertFlavorsheet
async function insertFlavorsheet({
  item_code,
  flavorsheet_no,
  standard,
  grade,
  remarks,
  no_of_batches,
  blendsheet,
}) {
  const client = await pool.connect();

  const flavorsheetQuery =
    "WITH new_row AS (" +
    "  INSERT INTO item(item_code) VALUES ($1) RETURNING created_ts " +
    "), flavor_row AS (" +
    "  INSERT INTO flavorsheet" +
    "  (item_code, created_ts, flavorsheet_no, standard, grade, remarks, no_of_batches) " +
    "  SELECT $1, created_ts, $2, $3, $4, $5, $6 " +
    "  FROM new_row " +
    "), flavor_mix_row AS (" +
    "  INSERT INTO flavorsheet_mix" +
    "  (flavorsheet_no, blendsheet_code, no_of_bags) " +
    "  SELECT $2, unnest($7::json[])->>'blendsheet_code', (unnest($7::json[])->>'no_of_bags')::integer" +
    ") SELECT created_ts FROM new_row;";
  const flavorsheetQueryRes = await client.query(flavorsheetQuery, [
    item_code,
    flavorsheet_no,
    standard,
    grade,
    remarks,
    no_of_batches,
    blendsheet,
  ]);

  client.release();
  return {
    item_code,
    created_ts: flavorsheetQueryRes.rows[0].created_ts,
  };
}
//readFlavorsheet
async function readFlavorsheet(data) {
  const client = await pool.connect();

  const flavorsheetQueryParams = [
    "WITH query_row AS (" +
      " SELECT bool_or(active) AS active, " +
      "  json_agg(json_build_object(" +
      "    'item_code', item_code, " +
      "    'created_ts', created_ts, " +
      "    'flavorsheet_no', flavorsheet_no" +
      "  )) AS data FROM flavorsheet" +
      ") SELECT active, CASE " +
      "  WHEN NOT active THEN data " +
      "END AS data FROM query_row;",
  ];
  if (hasParams(data)) {
    flavorsheetQueryParams[0] =
      "SELECT b.item_code, b.created_ts, b.flavorsheet_no, b.no_of_batches, b.batches_completed, " +
      "json_agg(" +
      "  json_build_object('blendsheet_code', bm.blendsheet_code, 'no_of_bags', bm.no_of_bags)" +
      ") AS blendsheet " +
      "FROM flavorsheet b INNER JOIN flavorsheet_mix bm " +
      "USING(flavorsheet_no) " +
      `WHERE ${Object.keys(data)
        .map((key, index) => `b.${key} = $${index + 1}`)
        .join(" AND ")} ` +
      "GROUP BY item_code, created_ts;";
    flavorsheetQueryParams.push(Object.keys(data).map((key) => data[key]));
  }
  const flavorsheetQueryRes = await client.query.apply(
    client,
    flavorsheetQueryParams
  );

  client.release();
  return hasParams(data)
    ? flavorsheetQueryRes.rows[0]
    : Object.keys(flavorsheetQueryRes.rows[0]).reduce(
        (obj, key) =>
          flavorsheetQueryRes.rows[0][key] !== null
            ? { ...obj, [key]: flavorsheetQueryRes.rows[0][key] }
            : obj,
        {}
      );
}
//updateFlavorsheetBatch
async function updateFlavorsheetBatch({ item_code, created_ts }) {
  const client = await pool.connect();

  const flavorsheetQuery =
    "UPDATE flavorsheet " +
    "SET batches_completed = batches_completed + 1, active = TRUE " +
    "WHERE item_code = $1 AND created_ts = $2 " +
    "RETURNING batches_completed, active;";
  const flavorsheetQueryRes = await client.query(flavorsheetQuery, [
    item_code,
    created_ts,
  ]);

  client.release();
  return {
    item_code,
    created_ts,
    batches_completed: flavorsheetQueryRes.rows[0].batches_completed,
    active: flavorsheetQueryRes.rows[0].active,
  };
}
//updateFlavorsheetBatchInactive
async function updateFlavorsheetBatchInactive({ item_code, created_ts }) {
  const client = await pool.connect();

  const flavorsheetQuery =
    "UPDATE flavorsheet " +
    "SET active = FALSE " +
    "WHERE item_code = $1 AND created_ts = $2 " +
    "RETURNING active;";
  const flavorsheetQueryRes = await client.query(flavorsheetQuery, [
    item_code,
    created_ts,
  ]);

  client.release();
  return {
    item_code,
    created_ts,
    active: flavorsheetQueryRes.rows[0].active,
  };
}
//insertFlavorsheetRecord
async function insertFlavorsheetRecord({
  item_code,
  created_ts,
  store_location,
  gross_weight,
  bag_weight,
}) {
  const client = await pool.connect();

  const flavorsheetRecordQuery =
    "INSERT INTO flavorsheet_record(item_code, created_ts, store_location, gross_weight, bag_weight) " +
    "VALUES ($1, $2, $3, $4, $5) RETURNING received_ts, barcode;";
  const flavorsheetRecordQueryRes = await client.query(flavorsheetRecordQuery, [
    item_code,
    created_ts,
    store_location,
    gross_weight,
    bag_weight,
  ]);

  client.release();
  return {
    item_code,
    created_ts,
    received_ts: flavorsheetRecordQueryRes.rows[0].received_ts,
    barcode: flavorsheetRecordQueryRes.rows[0].barcode,
  };
}
// end of flavorsheet

async function insertHerbline({ item_code, herbline_name }) {
  const client = await pool.connect();

  const herblineQuery =
    "INSERT INTO herbline(item_code, herbline_name) VALUES ($1, $2);";
  await client.query(herblineQuery, [item_code, herbline_name]);

  client.release();
  return {
    item_code,
    herbline_name,
  };
}

async function readHerbline() {
  const client = await pool.connect();

  const herblineQuery = "SELECT item_code, name FROM herbline;";
  const herblineQueryRes = await client.query(herblineQuery);

  client.release();
  return herblineQueryRes.rows;
}

async function insertHerblineRecord({
  item_code,
  reference,
  gross_weight,
  store_location,
}) {
  const client = await pool.connect();

  const herblineRecordQuery =
    "WITH new_row AS (" +
    "  INSERT INTO item(item_code) VALUES ($1) RETURNING created_ts" +
    ") " +
    "INSERT INTO herbline_record" +
    "(item_code, created_ts, reference, gross_weight, store_location) " +
    "SELECT $1, created_ts, $2, $3, $4 " +
    "FROM new_row " +
    "RETURNING created_ts, barcode;";
  const herblineRecordQueryRes = await client.query(herblineRecordQuery, [
    item_code,
    reference,
    gross_weight,
    store_location,
  ]);

  client.release();
  return {
    item_code,
    created_ts: herblineRecordQueryRes.rows[0].created_ts,
    barcode: herblineRecordQueryRes.rows[0].barcode,
  };
}

async function insertLocation({ location_name, herbline_section }) {
  const client = await pool.connect();

  const storeLocationQuery =
    "INSERT INTO store_location(location_name, herbline_section) VALUES ($1, $2);";
  await client.query(storeLocationQuery, [location_name, herbline_section]);

  client.release();
  return { location: location_name };
}

async function readLocation(data) {
  const client = await pool.connect();

  const storeLocationQueryParams = [
    "SELECT location_name FROM store_location;",
  ];
  if (hasParams(data)) {
    const { herbline_section } = data;
    storeLocationQueryParams[0] =
      "SELECT location_name FROM store_location WHERE herbline_section = $1;";
    storeLocationQueryParams.push([Number(herbline_section) ? true : false]);
  }
  const storeLocationQueryRes = await client.query.apply(
    client,
    storeLocationQueryParams
  );

  client.release();
  return storeLocationQueryRes.rows.map((row) => ({
    store_location: row.location_name,
  }));
}

async function readBarcode({ table_name, barcode }) {
  const client = await pool.connect();

  const scanQuery = `SELECT * FROM scan_record($1, $2) AS scan_result;`;
  const scanQueryRes = await client.query(scanQuery, [table_name, barcode]);

  client.release();

  return (
    scanQueryRes.rows[0].scan_result && scanQueryRes.rows[0].scan_result[0]
  );
}
// start of update herbline record status
async function updateHerblineRecordStatus({ barcode }) {
  const client = await pool.connect();

  const herblineRecordQuery =
    "UPDATE herbline_record " +
    "SET status = 'DISPATCHED' " +
    "WHERE barcode = $1 " +
    "RETURNING barcode, status;";

  const herblineRecordQueryRes = await client.query(
    client,
    herblineRecordQuery,
    [barcode]
  );

  client.release();
  return herblineRecordQueryRes.rows[0];
}
// end of update herbline record status

// Start of update flavorsheet record status
async function updateFlavorsheetRecordStatus({ barcode }) {
  const client = await pool.connect();

  const flavorsheetRecordQuery =
    "UPDATE flavorsheet_record " +
    "SET status = 'DISPATCHED' " +
    "WHERE barcode = $1 " +
    "RETURNING barcode, status;";

  const flavorsheetRecordQueryRes = await client.query(
    client,
    flavorsheetRecordQuery,
    [barcode]
  );

  client.release();
  return flavorsheetRecordQueryRes.rows[0];
}
// End of update flavorsheet record status

// Start of update blendsheet record status
async function updateBlendsheetRecordStatus({ barcode, reduced_by }) {
  const client = await pool.connect();

  const blendsheetRecordQuery = [
    "UPDATE blendsheet_record " +
      "SET status = 'DISPATCHED' " +
      "WHERE barcode = $1 " +
      "RETURNING barcode, status;",
  ];
  if (reduced_by) {
    blendsheetRecordQuery[0] =
      "WITH query_row AS (" +
      "  SELECT remaining - $2 AS remaining, barcode " +
      "  FROM tealine_record " +
      "  WHERE barcode = $1" +
      ")" +
      "UPDATE tealine_record " +
      "SET status = CASE " +
      "  WHEN query_row.remaining = 0 THEN 'PROCESSED' " +
      "  ELSE 'IN_PROCESS' " +
      "END, remaining = query_row.remaining " +
      "FROM query_row " +
      "WHERE tealine_record.barcode = query_row.barcode " +
      "RETURNING tealine_record.barcode, status;";
    blendsheetRecordQuery[1].push(reduced_by);
  }
  const blendsheetRecordQueryRes = await client.query.apply(
    client,
    blendsheetRecordQuery,
    [barcode]
  );

  client.release();
  return blendsheetRecordQueryRes.rows[0];
}
// End of update blendsheet record status

module.exports = {
  insertTealine,
  readTealine,
  insertTealineRecord,
  updateTealineRecordStatus,
  insertBlendsheet,
  readBlendsheet,
  updateBlendsheetBatch,
  updateBlendsheetBatchInactive,
  insertBlendsheetRecord,
  insertFlavorsheet,
  readFlavorsheet,
  updateFlavorsheetBatch,
  updateFlavorsheetBatchInactive,
  insertFlavorsheetRecord,
  insertHerbline,
  readHerbline,
  insertHerblineRecord,
  insertLocation,
  readLocation,
  readBarcode,
  updateHerblineRecordStatus, //updateHerblineRecordStatus
  updateFlavorsheetRecordStatus,
  updateBlendsheetRecordStatus,
};
