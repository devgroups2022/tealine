const log4js = require("log4js");
const types = require("util").types;

log4js.configure({
  appenders: {
    stdout: {
      type: "stdout",
      layout: {
        type: "pattern",
        pattern: "%[[%p] -%] %m",
      },
    },
    file: {
      type: "file",
      filename: "app.log",
      layout: {
        type: "pattern",
        pattern: "[%d] [%p] - %m",
      },
    },
  },
  categories: {
    default: {
      appenders: ["file"],
      level: "debug",
    },
    "default.debug": {
      appenders: ["stdout"],
      level: "debug",
    },
  },
});

const logger = log4js.getLogger(
  process.env.NODE_ENV === "production" ? "default" : "default.debug"
);

["uncaughtException", "unhandledRejection"].forEach((event) => {
  process.on(event, (err, source) => {
    let error = types.isNativeError(err) ? err : new Error(err);
    if (types.isPromise(source)) error.name = error.name.concat("<Promise>");
    logger.error(error);
    process.exit(1);
  });
});

if (!["development", "production"].includes(process.env.NODE_ENV)) {
  throw new Error(
    "Invalid environment, should be one of: 'development', 'production'"
  );
}

const express = require("express");
const { object, string, number, array, boolean } = require("yup");
const httpCodes = require("./http_codes");

const db = require("./db");
logger.debug("Connected to database");

function validate(schema) {
  return (req, res, next) => {
    schema
      .validate(req.method === "GET" ? req.query : req.body)
      .then((result) => {
        res.locals.validated_params = result;
        next();
      })
      .catch((e) =>
        next({
          status: 400,
          body: `Validation failed for the following attribute: ${e.path}`,
        })
      );
  };
}

const app = express();
const adminRoute = express.Router();
const userRoute = express.Router();
app.use(express.json());

app.use((req, res, next) => {
  res.header("Access-Control-Allow-Origin", "*");
  res.header("Access-Control-Allow-Headers", "*");
  next();
});

const insertTealineSchema = object({
  item_code: string().required(),
  invoice_no: string().required(),
  grade: string().required(),
  no_of_bags: number().integer().required(),
  weight_per_bag: number().required(),
  broker: string().required(),
  garden: string().required(),
});
adminRoute.post("/tealine", validate(insertTealineSchema), (req, res, next) => {
  db.insertTealine(res.locals.validated_params)
    .then((result) => res.json(result))
    .catch((e) => next(e));
});

const insertBlendsheetSchema = object({
  item_code: string().required(),
  blendsheet_no: string().required(),
  standard: string().required(),
  grade: string().required(),
  remarks: string().required(),
  no_of_batches: number().integer().required(),
  tealine: array()
    .of(
      object({
        tealine_code: string().required(),
        no_of_bags: number().integer().required(),
      })
    )
    .min(1)
    .required(),
});
adminRoute.post(
  "/blendsheet",
  validate(insertBlendsheetSchema),
  (req, res, next) => {
    db.insertBlendsheet(res.locals.validated_params)
      .then((result) => res.json(result))
      .catch((e) => next(e));
  }
);

//start of flavorsheet
adminRoute.post(
  "/flavorsheet",
  // validate(insertFlavorsheetSchema),
  (req, res, next) => {
    db.insertFlavorsheet(req.body)
      .then((result) => res.json(result))
      .catch((e) => next(e));
  }
);
// end of flavorsheet

const insertLocationSchema = object({
  location_name: string().required(),
});
adminRoute.post(
  "/location",
  validate(insertLocationSchema),
  (req, res, next) => {
    db.insertLocation(res.locals.validated_params)
      .then((result) => res.json(result))
      .catch((e) => next(e));
  }
);

const insertHerblineSchema = object({
  item_code: string().required(),
  herbline_name: string().required(),
});
adminRoute.post(
  "/herbline",
  validate(insertHerblineSchema),
  (req, res, next) => {
    db.insertHerbline(res.locals.validated_params)
      .then((result) => res.json(result))
      .catch((e) => next(e));
  }
);

userRoute.get("/tealine", (req, res, next) => {
  db.readTealine(req.query)
    .then((data) => res.json(data))
    .catch((e) => next(e));
});

const insertTealineRecordSchema = object({
  item_code: string().required(),
  created_ts: string().required(),
  store_location: string().required(),
  gross_weight: number().required(),
  bag_weight: number().required(),
});
userRoute.post(
  "/tealine",
  validate(insertTealineRecordSchema),
  (req, res, next) => {
    db.insertTealineRecord(res.locals.validated_params)
      .then((data) => res.json(data))
      .catch((e) => next(e));
  }
);

userRoute.put("/tealine", (req, res, next) => {
  db.updateTealineRecordStatus(req.body)
    .then((data) => res.json(data))
    .catch((e) => next(e));
});

userRoute.get("/blendsheet", (req, res, next) => {
  db.readBlendsheet(req.query)
    .then((data) => res.json(data))
    .then((e) => next(e));
});

userRoute.post("/blendsheet", (req, res, next) => {
  db.insertBlendsheetRecord(req.body)
    .then((data) => res.json(data))
    .catch((e) => next(e));
});

userRoute.put("/blendsheet", (req, res, next) => {
  let method = req.body.active
    ? db.updateBlendsheetBatch
    : db.updateBlendsheetBatchInactive;
  method
    .call(db, req.body)
    .then((data) => res.json(data))
    .catch((e) => next(e));
});
//start of flavorsheet
userRoute.get("/flavorsheet", (req, res, next) => {
  db.readFlavorsheet(req.query)
    .then((data) => res.json(data))
    .then((e) => next(e));
});

userRoute.post("/flavorsheet", (req, res, next) => {
  db.insertFlavorsheetRecord(req.body)
    .then((data) => res.json(data))
    .catch((e) => next(e));
});

userRoute.put("/flavorsheet", (req, res, next) => {
  let method = req.body.active
    ? db.updateFlavorsheetBatch
    : db.updateFlavorsheetBatchInactive;
  method
    .call(db, req.body)
    .then((data) => res.json(data))
    .catch((e) => next(e));
});
//end of flavorsheet

userRoute.get("/location", (req, res, next) => {
  db.readLocation(req.query)
    .then((data) => res.json(data))
    .catch((e) => next(e));
});

userRoute.get("/herbline", (req, res, next) => {
  db.readHerbline(req.query)
    .then((data) => res.json(data))
    .catch((e) => next(e));
});

const insertHerblineRecordSchema = object({
  item_code: string().required(),
  reference: string().required(),
  gross_weight: number().required(),
  store_location: string().required(),
});

userRoute.post(
  "/herbline",
  validate(insertHerblineRecordSchema),
  (req, res, next) => {
    db.insertHerblineRecord(res.locals.validated_params)
      .then((data) => res.json(data))
      .catch((e) => next(e));
  }
);

userRoute.get("/scan", (req, res, next) => {
  db.readBarcode(req.query)
    .then((data) => res.json(data))
    .catch((e) => next(e));
});

// start of update herbline record status
userRoute.put("/herblinerecord", (req, res, next) => {
  db.updateHerblineRecordStatus(req.body)
    .then((data) => res.json(data))
    .catch((e) => next(e));
});
// end of update herbline record status

// start of update flavorsheet record status
userRoute.put("/flavorsheetrecord", (req, res, next) => {
  db.updateFlavorsheetRecordStatus(req.body)
    .then((data) => res.json(data))
    .catch((e) => next(e));
});
// end of update flavorsheet record status

// start of update blendsheet record status
userRoute.put("/blendsheetrecord", (req, res, next) => {
  db.updateBlendsheetRecordStatus(req.body)
    .then((data) => res.json(data))
    .catch((e) => next(e));
});
// end of update blendsheet record status

app.use("/app/admin", adminRoute);
app.use("/app", userRoute);

app.get("*", (req, res, next) => {
  next({ status: 404 });
});

app.use((err, req, res, next) => {
  if (err.status === 400 && err.type === "entity.parse.failed")
    return next({ status: 400, body: `Error parsing JSON: ${err.message}` });
  next(err);
});

app.use((err, req, res, next) => {
  if (err.status)
    return res.status(err.status).json(err.body || httpCodes[err.status]);

  logger.error(err.stack);
  res
    .status(500)
    .type("text/plain")
    .send(process.env.NODE_ENV === "production" ? httpCodes[500] : err.stack);
});

app.listen(process.env.PORT, () => {
  logger.debug(`Server started listening at port ${process.env.PORT}`);
});
