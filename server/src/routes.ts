import type { FastifyInstance } from "fastify";
import { randomUUID } from "node:crypto";
import { ZodError } from "zod";
import type { ApnsLiveActivityClient } from "./liveActivity.js";
import {
  deviceRegistrationSchema,
  type DepartureScheduleInput,
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
  app.setErrorHandler((error, request, reply) => {
    if (error instanceof ZodError) {
      return reply.code(400).send({
        error: "Validation Error",
        message: "Invalid request body",
        issues: error.issues.map((issue) => ({
          path: issue.path.join("."),
          message: issue.message
        }))
      });
    }

    request.log.error(error);
    const message = error instanceof Error ? error.message : "Unexpected server error";
    return reply.code(500).send({
      error: "Internal Server Error",
      message
    });
  });

  app.get("/health", async () => ({ ok: true }));
  app.get("/api/health", async () => ({ ok: true }));

  app.get("/api/stops/search", async (request) => {
    const query = String((request.query as any).q ?? "");
    if (query.trim().length < 2) return [];
    return deps.tfnsw.searchStops(query);
  });

  app.get("/api/stations", async (request) => {
    const query = String((request.query as any).q ?? "Station");
    if (query.trim().length < 2) return [];
    return deps.tfnsw.searchStations(query);
  });

  app.get("/api/schedules", async (request) => deps.storage.listSchedulesForUser(userIdFrom(request)));

  app.post("/api/schedules", async (request, reply) => {
    const input = normalizeScheduleInput(scheduleInputSchema.parse(request.body));
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
    const input = normalizeScheduleInput(scheduleInputSchema.parse(request.body));
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
    const input = normalizeScheduleInput(parsed.schedule);
    const schedule = {
      ...input,
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
      devicePushToken: parsed.devicePushToken,
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

function normalizeScheduleInput(input: DepartureScheduleInput) {
  const arrivalWindowStartTime = input.arrivalWindowStartTime ?? input.activeStartTime;
  const arrivalWindowEndTime = input.arrivalWindowEndTime ?? input.activeEndTime;
  const activeStartTime = input.activeStartTime ?? subtractMinutes(arrivalWindowStartTime!, 120);
  const activeEndTime = input.activeEndTime ?? arrivalWindowEndTime!;

  return {
    ...input,
    activeStartTime,
    activeEndTime,
    arrivalWindowStartTime,
    arrivalWindowEndTime
  };
}

function subtractMinutes(hhmm: string, minutesToSubtract: number): string {
  const [hour = "0", minute = "0"] = hhmm.split(":");
  const total = (Number(hour) * 60 + Number(minute) - minutesToSubtract + 24 * 60) % (24 * 60);
  return `${String(Math.floor(total / 60)).padStart(2, "0")}:${String(total % 60).padStart(2, "0")}`;
}

function userIdFrom(request: any): string {
  const header = request.headers["x-departures-user"];
  if (Array.isArray(header)) return header[0] ?? "local";
  return typeof header === "string" && header.trim().length > 0 ? header : "local";
}
