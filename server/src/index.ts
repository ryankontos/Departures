import Fastify from "fastify";
import { loadConfig } from "./config.js";
import { ApnsLiveActivityClient } from "./liveActivity.js";
import { registerRoutes } from "./routes.js";
import { ScheduleWorker } from "./scheduler.js";
import { Storage } from "./storage.js";
import { TfnswClient } from "./tfnsw.js";

const config = loadConfig();
const app = Fastify({ logger: true });
const storage = new Storage(config.databasePath);
const tfnsw = new TfnswClient({ apiKey: config.tfnswApiKey, timeZone: config.timeZone });
const apns = new ApnsLiveActivityClient(config.apns);

await registerRoutes(app, { storage, tfnsw, apns });

const worker = new ScheduleWorker(storage, tfnsw, apns, config.timeZone);
worker.start();

const close = async () => {
  worker.stop();
  await app.close();
  process.exit(0);
};

process.on("SIGINT", close);
process.on("SIGTERM", close);

await app.listen({ port: config.port, host: "0.0.0.0" });

