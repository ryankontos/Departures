import type { DepartureSchedule, StopSearchResult, TripLeg, TripSnapshot } from "./models.js";
import { addMinutes, dateOnSydneyClock, maxDate } from "./time.js";

type TfnswClientOptions = {
  apiKey?: string;
  timeZone: string;
  baseUrl?: string;
};

export class TfnswClient {
  private readonly baseUrl: string;

  constructor(private readonly options: TfnswClientOptions) {
    this.baseUrl = options.baseUrl ?? "https://api.transport.nsw.gov.au/v1/tp/";
  }

  async searchStops(query: string): Promise<StopSearchResult[]> {
    const json = await this.request("stop_finder", {
      type_sf: "any",
      name_sf: query,
      odvSugMacro: "1",
      TfNSWSF: "true",
      anyMaxSizeHitList: "12"
    });

    const locations = Array.isArray(json.locations) ? json.locations : [];
    return locations.map((location: any): StopSearchResult => ({
      id: String(location.id ?? ""),
      name: String(location.name ?? location.disassembledName ?? ""),
      type: location.type,
      matchQuality: typeof location.matchQuality === "number" ? location.matchQuality : undefined,
      isBest: Boolean(location.isBest)
    })).filter((location: StopSearchResult) => location.id.length > 0 && location.name.length > 0);
  }

  async previewTrips(schedule: DepartureSchedule, now = new Date()): Promise<TripSnapshot[]> {
    const requestedDeparture = this.requestedDepartureTime(schedule, now);
    const json = await this.request("trip", {
      depArrMacro: "dep",
      itdDate: formatTfnswDate(requestedDeparture),
      itdTime: formatTfnswTime(requestedDeparture),
      type_origin: schedule.origin.type === "coord" ? "coord" : "stop",
      name_origin: schedule.origin.id,
      type_destination: schedule.destination.type === "coord" ? "coord" : "stop",
      name_destination: schedule.destination.id,
      TfNSWTR: "true",
      calcNumberOfTrips: String(Math.max(schedule.tripsToShow, 5))
    });

    const journeys = Array.isArray(json.journeys) ? json.journeys : [];
    return journeys
      .map((journey: any, index: number) => normalizeJourney(journey, schedule, index))
      .filter((trip: TripSnapshot | undefined): trip is TripSnapshot => {
        if (!trip) return false;
        const leave = new Date(trip.leaveTime);
        if (leave.getTime() + 3 * 60_000 < now.getTime()) return false;
        if (schedule.arrivalWindowStartTime) {
          const start = dateOnSydneyClock(now, schedule.arrivalWindowStartTime, this.options.timeZone);
          if (new Date(trip.arrivalTime).getTime() < start.getTime()) return false;
        }
        if (schedule.arrivalWindowEndTime) {
          const end = dateOnSydneyClock(now, schedule.arrivalWindowEndTime, this.options.timeZone);
          if (new Date(trip.arrivalTime).getTime() > end.getTime()) return false;
        }
        return true;
      })
      .slice(0, schedule.tripsToShow);
  }

  private requestedDepartureTime(schedule: DepartureSchedule, now: Date): Date {
    const byWalkLead = addMinutes(now, schedule.walkMinutes);
    if (!schedule.earliestLeaveTime) return byWalkLead;
    const earliestLeave = dateOnSydneyClock(now, schedule.earliestLeaveTime, this.options.timeZone);
    return maxDate(byWalkLead, addMinutes(earliestLeave, schedule.walkMinutes));
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

function normalizeJourney(journey: any, schedule: DepartureSchedule, index: number): TripSnapshot | undefined {
  const legs = Array.isArray(journey.legs) ? journey.legs : [];
  const publicLegs = legs.filter((leg: any) => leg.transportation);
  const firstLeg = publicLegs[0] ?? legs[0];
  const lastLeg = publicLegs[publicLegs.length - 1] ?? legs[legs.length - 1];
  const departureTime = extractTime(firstLeg?.origin, "departure");
  const arrivalTime = extractTime(lastLeg?.destination, "arrival");

  if (!departureTime || !arrivalTime) return undefined;

  const normalizedLegs: TripLeg[] = legs.map((leg: any) => ({
    mode: String(leg.transportation?.product?.name ?? leg.transportation?.name ?? leg.type ?? "Walk"),
    routeLabel: leg.transportation?.number ? String(leg.transportation.number) : undefined,
    originName: String(leg.origin?.name ?? leg.origin?.disassembledName ?? schedule.origin.name),
    destinationName: String(leg.destination?.name ?? leg.destination?.disassembledName ?? schedule.destination.name),
    departureTime: extractTime(leg.origin, "departure")?.toISOString(),
    arrivalTime: extractTime(leg.destination, "arrival")?.toISOString()
  }));

  const routeLabels = normalizedLegs
    .map((leg) => leg.routeLabel ?? leg.mode)
    .filter(Boolean)
    .slice(0, 3)
    .join(" -> ");

  return {
    id: String(journey.id ?? `${departureTime.toISOString()}-${index}`),
    routeSummary: routeLabels || `${schedule.origin.name} to ${schedule.destination.name}`,
    departureTime: departureTime.toISOString(),
    arrivalTime: arrivalTime.toISOString(),
    leaveTime: addMinutes(departureTime, -schedule.walkMinutes).toISOString(),
    realtime: Boolean(firstLeg?.origin?.departureTimeEstimated || lastLeg?.destination?.arrivalTimeEstimated),
    legs: normalizedLegs
  };
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
