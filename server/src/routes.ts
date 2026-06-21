import type { FastifyInstance } from "fastify";
import { randomUUID } from "node:crypto";
import type { ApnsLiveActivityClient } from "./liveActivity.js";
import {
  deviceRegistrationSchema,
  journeyPreviewRequestSchema,
  pushTokenSchema,
  scheduleInputSchema,
  selectTripSchema
} from "./models.js";
import type { Storage } from "./storage.js";
import type { TfnswClient } from "./tfnsw.js";

type RouteDeps = {
  storage: Storage;
  tfnsw: TfnswClient;
  apns: ApnsLiveActivityClient;
};

export async function registerRoutes(app: FastifyInstance, deps: RouteDeps) {
  app.get("/health", async () => ({ ok: true }));
  app.get("/api/health", async () => ({ ok: true }));

  app.get("/api/stops/search", async (request) => {
    const query = String((request.query as any).q ?? "");
    if (query.trim().length < 2) return [];
    return deps.tfnsw.searchStops(query);
  });

  app.get("/api/schedules", async (request) => deps.storage.listSchedulesForUser(userIdFrom(request)));

  app.post("/api/schedules", async (request, reply) => {
    const input = scheduleInputSchema.parse(request.body);
    const now = new Date().toISOString();
    const schedule = deps.storage.upsertSchedule({
      ...input,
      userId: userIdFrom(request),
      id: randomUUID(),
      createdAt: now,
      updatedAt: now
    });
    return reply.code(201).send(schedule);
  });

  app.put("/api/schedules/:id", async (request) => {
    const id = String((request.params as any).id);
    const existing = deps.storage.getSchedule(id);
    const input = scheduleInputSchema.parse(request.body);
    const now = new Date().toISOString();
    return deps.storage.upsertSchedule({
      ...input,
      id,
      userId: existing?.userId ?? userIdFrom(request),
      createdAt: existing?.createdAt ?? now,
      updatedAt: now
    });
  });

  app.delete("/api/schedules/:id", async (request, reply) => {
    const deleted = deps.storage.deleteSchedule(String((request.params as any).id));
    return reply.code(deleted ? 204 : 404).send();
  });

  app.post("/api/journeys/preview", async (request) => {
    const parsed = journeyPreviewRequestSchema.parse(request.body);
    const now = parsed.now ? new Date(parsed.now) : new Date();
    const schedule = {
      ...parsed.schedule,
      id: randomUUID(),
      userId: userIdFrom(request),
      createdAt: now.toISOString(),
      updatedAt: now.toISOString()
    };
    return deps.tfnsw.previewTrips(schedule, now);
  });

  app.post("/api/devices", async (request, reply) => {
    const parsed = deviceRegistrationSchema.parse(request.body);
    deps.storage.upsertDevice({
      userId: parsed.userId ?? userIdFrom(request),
      deviceId: parsed.deviceId,
      name: parsed.name,
      pushToStartToken: parsed.pushToStartToken,
      updatedAt: new Date().toISOString()
    });
    return reply.code(204).send();
  });

  app.post("/api/live-activities/:activityId/token", async (request, reply) => {
    const activityId = String((request.params as any).activityId);
    const parsed = pushTokenSchema.parse(request.body);
    deps.storage.upsertLiveActivity({
      activityId,
      userId: userIdFrom(request),
      scheduleId: String((request.query as any).scheduleId ?? "unknown"),
      deviceId: String((request.query as any).deviceId ?? "unknown"),
      activityPushToken: parsed.token,
      status: "active",
      updatedAt: new Date().toISOString()
    });
    return reply.code(204).send();
  });

  app.post("/api/live-activities/:activityId/select-trip", async (request, reply) => {
    const activityId = String((request.params as any).activityId);
    const parsed = selectTripSchema.parse(request.body);
    deps.storage.upsertLiveActivity({
      activityId,
      userId: userIdFrom(request),
      scheduleId: String((request.query as any).scheduleId ?? "unknown"),
      deviceId: String((request.query as any).deviceId ?? "unknown"),
      selectedTripId: parsed.tripId,
      status: "active",
      updatedAt: new Date().toISOString()
    });
    return reply.code(204).send();
  });
}

function userIdFrom(request: any): string {
  const header = request.headers["x-departures-user"];
  if (Array.isArray(header)) return header[0] ?? "local";
  return typeof header === "string" && header.trim().length > 0 ? header : "local";
}
