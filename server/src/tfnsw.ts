import type { DepartureSchedule, StopSearchResult, TripLeg, TripSnapshot } from "./models.js";
import { addMinutes, dateOnSydneyClock, maxDate, zonedParts } from "./time.js";

const MAKEABLE_TRIP_GRACE_MINUTES = 2;
const STOP_SEARCH_CACHE_MS = 10 * 60_000;

type TfnswClientOptions = {
  apiKey?: string;
  timeZone: string;
  baseUrl?: string;
};

export class TfnswClient {
  private readonly baseUrl: string;
  private readonly stopSearchCache = new Map<string, { expiresAt: number; results: StopSearchResult[] }>();

  constructor(private readonly options: TfnswClientOptions) {
    this.baseUrl = options.baseUrl ?? "https://api.transport.nsw.gov.au/v1/tp/";
  }

  async searchStops(query: string): Promise<StopSearchResult[]> {
    const cacheKey = query.trim().toLowerCase();
    const cached = this.stopSearchCache.get(cacheKey);
    if (cached && cached.expiresAt > Date.now()) {
      return cached.results;
    }

    const json = await this.request("stop_finder", {
      type_sf: "any",
      name_sf: query,
      odvSugMacro: "1",
      TfNSWSF: "true",
      anyMaxSizeHitList: "50"
    });

    const locations = Array.isArray(json.locations) ? json.locations : [];
    const results = locations.map((location: any): StopSearchResult => ({
      id: String(location.id ?? ""),
      name: String(location.name ?? location.disassembledName ?? ""),
      type: location.type,
      matchQuality: typeof location.matchQuality === "number" ? location.matchQuality : undefined,
      isBest: Boolean(location.isBest)
    })).filter((location: StopSearchResult) => location.id.length > 0 && location.name.length > 0);
    this.stopSearchCache.set(cacheKey, { expiresAt: Date.now() + STOP_SEARCH_CACHE_MS, results });
    return results;
  }

  async searchStations(query: string): Promise<StopSearchResult[]> {
    const stationQuery = /\b(station|metro)\b/i.test(query) ? query : `${query} Station`;
    const stops = await this.searchStops(stationQuery);
    const stations = stops
      .filter((stop) => stop.type === "stop")
      .filter((stop) => /\b(station|metro)\b/i.test(stop.name))
      .map((stop) => ({
        ...stop,
        name: stop.name.replace(/\s+/g, " ").trim()
      }));
    return uniqueById(stations).sort((left, right) => {
      const quality = (right.matchQuality ?? 0) - (left.matchQuality ?? 0);
      return quality !== 0 ? quality : left.name.localeCompare(right.name);
    });
  }

  async previewTrips(schedule: DepartureSchedule, now = new Date()): Promise<TripSnapshot[]> {
    const serviceNow = this.previewReferenceTime(schedule, now);
    const requestedDeparture = this.requestedDepartureTime(schedule, serviceNow);
    const queryTime = schedule.arrivalWindowEndTime
      ? dateOnSydneyClock(serviceNow, schedule.arrivalWindowEndTime, this.options.timeZone)
      : requestedDeparture;
    const json = await this.request("trip", {
      depArrMacro: schedule.arrivalWindowEndTime ? "arr" : "dep",
      itdDate: formatTfnswDate(queryTime),
      itdTime: formatTfnswTime(queryTime),
      type_origin: schedule.origin.type === "coord" ? "coord" : "stop",
      name_origin: schedule.origin.id,
      type_destination: schedule.destination.type === "coord" ? "coord" : "stop",
      name_destination: schedule.destination.id,
      TfNSWTR: "true",
      calcNumberOfTrips: String(Math.max(schedule.tripsToShow * 4, 12))
    });

    const journeys = Array.isArray(json.journeys) ? json.journeys : [];
    return journeys
      .map((journey: any, index: number) => normalizeJourney(journey, schedule, index))
      .filter((trip: TripSnapshot | undefined): trip is TripSnapshot => {
        if (!trip) return false;
        const leave = new Date(trip.leaveTime);
        if (leave.getTime() + MAKEABLE_TRIP_GRACE_MINUTES * 60_000 < now.getTime()) return false;
        if (schedule.arrivalWindowStartTime) {
          const start = dateOnSydneyClock(serviceNow, schedule.arrivalWindowStartTime, this.options.timeZone);
          if (new Date(trip.arrivalTime).getTime() < start.getTime()) return false;
        }
        if (schedule.arrivalWindowEndTime) {
          const end = dateOnSydneyClock(serviceNow, schedule.arrivalWindowEndTime, this.options.timeZone);
          if (new Date(trip.arrivalTime).getTime() > end.getTime()) return false;
        }
        return true;
      })
      .sort((left: TripSnapshot, right: TripSnapshot) => new Date(left.departureTime).getTime() - new Date(right.departureTime).getTime())
      .slice(0, schedule.tripsToShow);
  }

  private requestedDepartureTime(schedule: DepartureSchedule, now: Date): Date {
    const byWalkLead = addMinutes(now, schedule.walkMinutes);
    if (!schedule.earliestLeaveTime) return byWalkLead;
    const earliestLeave = dateOnSydneyClock(now, schedule.earliestLeaveTime, this.options.timeZone);
    return maxDate(byWalkLead, addMinutes(earliestLeave, schedule.walkMinutes));
  }

  private previewReferenceTime(schedule: DepartureSchedule, now: Date): Date {
    const targetDay = this.nextPreviewDay(schedule, now);
    return dateOnSydneyClock(targetDay, schedule.activeStartTime, this.options.timeZone);
  }

  private nextPreviewDay(schedule: DepartureSchedule, now: Date): Date {
    const endTime = schedule.arrivalWindowEndTime ?? schedule.activeEndTime;
    for (let dayOffset = 0; dayOffset < 8; dayOffset += 1) {
      const candidate = addMinutes(now, dayOffset * 24 * 60);
      const parts = zonedParts(candidate, this.options.timeZone);
      if (!schedule.weekdays.includes(parts.weekday)) continue;
      if (dayOffset === 0 && !isBeforeOrEqual(parts.time, endTime)) continue;
      return candidate;
    }
    return now;
  }

  private async request(apiCall: string, params: Record<string, string>): Promise<any> {
    if (!this.options.apiKey) {
      throw new Error("TFNSW_API_KEY is not configured");
    }

    const url = new URL(apiCall, this.baseUrl);
    url.searchParams.set("outputFormat", "rapidJSON");
    url.searchParams.set("coordOutputFormat", "EPSG:4326");
    for (const [key, value] of Object.entries(params)) {
      url.searchParams.set(key, value);
    }

    const response = await fetch(url, {
      headers: {
        Authorization: `apikey ${this.options.apiKey}`,
        Accept: "application/json"
      }
    });

    if (!response.ok) {
      const body = await response.text();
      throw new Error(`TfNSW ${apiCall} failed with ${response.status}: ${body.slice(0, 300)}`);
    }

    return response.json();
  }
}

function isBeforeOrEqual(left: string, right: string): boolean {
  return clockMinutes(left) <= clockMinutes(right);
}

function clockMinutes(value: string): number {
  const [hours = "0", minutes = "0"] = value.split(":");
  return Number(hours) * 60 + Number(minutes);
}

function uniqueById(stops: StopSearchResult[]): StopSearchResult[] {
  const seen = new Set<string>();
  return stops.filter((stop) => {
    if (seen.has(stop.id)) return false;
    seen.add(stop.id);
    return true;
  });
}

function normalizeJourney(journey: any, schedule: DepartureSchedule, index: number): TripSnapshot | undefined {
  const legs = Array.isArray(journey.legs) ? journey.legs : [];
  const publicLegs = legs.filter((leg: any) => leg.transportation);
  const firstLeg = publicLegs[0] ?? legs[0];
  const lastLeg = publicLegs[publicLegs.length - 1] ?? legs[legs.length - 1];
  const departureTime = extractTime(firstLeg?.origin, "departure");
  const arrivalTime = extractTime(lastLeg?.destination, "arrival");
  const plannedDepartureTime = extractPlannedTime(firstLeg?.origin, "departure");
  const plannedArrivalTime = extractPlannedTime(lastLeg?.destination, "arrival");

  if (!departureTime || !arrivalTime) return undefined;

  const normalizedLegs: TripLeg[] = legs.map((leg: any) => ({
    mode: String(leg.transportation?.product?.name ?? leg.transportation?.name ?? leg.type ?? "Walk"),
    routeLabel: leg.transportation?.number ? String(leg.transportation.number) : undefined,
    originName: String(leg.origin?.name ?? leg.origin?.disassembledName ?? schedule.origin.name),
    destinationName: String(leg.destination?.name ?? leg.destination?.disassembledName ?? schedule.destination.name),
    plannedDepartureTime: extractPlannedTime(leg.origin, "departure")?.toISOString(),
    plannedArrivalTime: extractPlannedTime(leg.destination, "arrival")?.toISOString(),
    departureTime: extractTime(leg.origin, "departure")?.toISOString(),
    arrivalTime: extractTime(leg.destination, "arrival")?.toISOString()
  }));

  const routeLabels = normalizedLegs
    .filter((leg) => !isWalkMode(leg.mode))
    .map((leg) => leg.routeLabel ?? leg.mode)
    .filter(Boolean)
    .slice(0, 3)
    .join(" -> ");

  return {
    id: String(journey.id ?? `${departureTime.toISOString()}-${index}`),
    routeSummary: routeLabels || `${schedule.origin.name} to ${schedule.destination.name}`,
    plannedDepartureTime: plannedDepartureTime?.toISOString(),
    plannedArrivalTime: plannedArrivalTime?.toISOString(),
    departureTime: departureTime.toISOString(),
    arrivalTime: arrivalTime.toISOString(),
    leaveTime: addMinutes(departureTime, -schedule.walkMinutes).toISOString(),
    realtime: Boolean(firstLeg?.origin?.departureTimeEstimated || lastLeg?.destination?.arrivalTimeEstimated),
    legs: normalizedLegs
  };
}

function isWalkMode(mode: string): boolean {
  return /walk|footpath/i.test(mode);
}

function extractPlannedTime(stop: any, kind: "departure" | "arrival"): Date | undefined {
  const planned = stop?.[`${kind}TimePlanned`];
  if (!planned) return undefined;
  const date = new Date(planned);
  return Number.isNaN(date.getTime()) ? undefined : date;
}

function extractTime(stop: any, kind: "departure" | "arrival"): Date | undefined {
  const estimated = stop?.[`${kind}TimeEstimated`];
  const planned = stop?.[`${kind}TimePlanned`];
  const value = estimated || planned;
  if (!value) return undefined;
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? undefined : date;
}

function formatTfnswDate(date: Date): string {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, "0");
  const day = String(date.getDate()).padStart(2, "0");
  return `${year}${month}${day}`;
}

function formatTfnswTime(date: Date): string {
  return `${String(date.getHours()).padStart(2, "0")}${String(date.getMinutes()).padStart(2, "0")}`;
}
