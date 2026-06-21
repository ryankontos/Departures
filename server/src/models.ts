import { z } from "zod";

export const weekdaySchema = z.enum(["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]);
export type Weekday = z.infer<typeof weekdaySchema>;

const timeSchema = z.string().regex(/^\d{2}:\d{2}$/);
const optionalTimeSchema = z.preprocess(
  (value) => (typeof value === "string" && value.trim().length === 0 ? undefined : value),
  timeSchema.optional()
);

export const routeEndpointSchema = z.object({
  id: z.string().min(1),
  name: z.string().min(1),
  type: z.enum(["stop", "coord", "any"]).default("stop")
});
export type RouteEndpoint = z.infer<typeof routeEndpointSchema>;

export const scheduleSchema = z.object({
  id: z.string().uuid(),
  userId: z.string().min(1),
  name: z.string().min(1),
  enabled: z.boolean().default(true),
  weekdays: z.array(weekdaySchema).min(1),
  activeStartTime: timeSchema,
  activeEndTime: timeSchema,
  earliestLeaveTime: optionalTimeSchema,
  arrivalWindowStartTime: optionalTimeSchema,
  arrivalWindowEndTime: optionalTimeSchema,
  walkMinutes: z.number().int().min(0).max(180),
  tripsToShow: z.number().int().min(1).max(6).default(3),
  origin: routeEndpointSchema,
  destination: routeEndpointSchema,
  createdAt: z.string().datetime(),
  updatedAt: z.string().datetime()
});
export type DepartureSchedule = z.infer<typeof scheduleSchema>;

export const scheduleInputSchema = scheduleSchema
  .omit({ id: true, userId: true, createdAt: true, updatedAt: true })
  .partial({
    activeStartTime: true,
    activeEndTime: true,
    earliestLeaveTime: true,
    arrivalWindowStartTime: true,
    arrivalWindowEndTime: true
  })
  .refine((schedule) => Boolean(schedule.arrivalWindowStartTime ?? schedule.activeStartTime), {
    path: ["arrivalWindowStartTime"],
    message: "Earliest arrival time is required"
  })
  .refine((schedule) => Boolean(schedule.arrivalWindowEndTime ?? schedule.activeEndTime), {
    path: ["arrivalWindowEndTime"],
    message: "Latest arrival time is required"
  });
export type DepartureScheduleInput = z.infer<typeof scheduleInputSchema>;

export const tripLegSchema = z.object({
  mode: z.string(),
  routeLabel: z.string().optional(),
  originName: z.string(),
  destinationName: z.string(),
  plannedDepartureTime: z.string().datetime().optional(),
  plannedArrivalTime: z.string().datetime().optional(),
  departureTime: z.string().datetime().optional(),
  arrivalTime: z.string().datetime().optional()
});
export type TripLeg = z.infer<typeof tripLegSchema>;

export const tripSnapshotSchema = z.object({
  id: z.string(),
  routeSummary: z.string(),
  plannedDepartureTime: z.string().datetime().optional(),
  plannedArrivalTime: z.string().datetime().optional(),
  departureTime: z.string().datetime(),
  arrivalTime: z.string().datetime(),
  leaveTime: z.string().datetime(),
  realtime: z.boolean(),
  legs: z.array(tripLegSchema)
});
export type TripSnapshot = z.infer<typeof tripSnapshotSchema>;

export const liveActivityStateSchema = z.object({
  scheduleId: z.string().uuid(),
  scheduleName: z.string(),
  generatedAt: z.string().datetime(),
  walkMinutes: z.number().int(),
  selectedTripId: z.string().optional(),
  trips: z.array(tripSnapshotSchema)
});
export type LiveActivityState = z.infer<typeof liveActivityStateSchema>;

export const journeyPreviewRequestSchema = z.object({
  schedule: scheduleInputSchema,
  now: z.string().datetime().optional()
});

export const stopSearchResultSchema = z.object({
  id: z.string(),
  name: z.string(),
  type: z.string().optional(),
  matchQuality: z.number().optional(),
  isBest: z.boolean().optional()
});
export type StopSearchResult = z.infer<typeof stopSearchResultSchema>;

export const deviceRegistrationSchema = z.object({
  deviceId: z.string().min(1),
  userId: z.string().min(1).optional(),
  name: z.string().optional(),
  devicePushToken: z.string().optional(),
  pushToStartToken: z.string().optional()
});

export const pushTokenSchema = z.object({
  token: z.string().min(1)
});

export const selectTripSchema = z.object({
  tripId: z.string().min(1)
});
