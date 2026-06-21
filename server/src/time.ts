import type { Weekday } from "./models.js";

const weekdayLookup: Record<string, Weekday> = {
  Monday: "monday",
  Tuesday: "tuesday",
  Wednesday: "wednesday",
  Thursday: "thursday",
  Friday: "friday",
  Saturday: "saturday",
  Sunday: "sunday"
};

export function zonedParts(date: Date, timeZone: string) {
  const parts = new Intl.DateTimeFormat("en-AU", {
    timeZone,
    weekday: "long",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
    hourCycle: "h23"
  }).formatToParts(date);

  const map = Object.fromEntries(parts.map((part) => [part.type, part.value]));
  return {
    weekday: weekdayLookup[map.weekday ?? "Monday"] ?? "monday",
    dateKey: `${map.year}-${map.month}-${map.day}`,
    time: `${map.hour}:${map.minute}`,
    hour: Number(map.hour),
    minute: Number(map.minute)
  };
}

export function isTimeInWindow(time: string, start: string, end: string): boolean {
  const current = minutesFromClock(time);
  const startMinutes = minutesFromClock(start);
  const endMinutes = minutesFromClock(end);
  if (startMinutes <= endMinutes) {
    return current >= startMinutes && current <= endMinutes;
  }
  return current >= startMinutes || current <= endMinutes;
}

export function minutesFromClock(value: string): number {
  const [hours = "0", minutes = "0"] = value.split(":");
  return Number(hours) * 60 + Number(minutes);
}

export function addMinutes(date: Date, minutes: number): Date {
  return new Date(date.getTime() + minutes * 60_000);
}

export function maxDate(left: Date, right: Date): Date {
  return left.getTime() >= right.getTime() ? left : right;
}

export function dateOnSydneyClock(now: Date, time: string, timeZone: string): Date {
  const parts = zonedParts(now, timeZone);
  const [hours = "0", minutes = "0"] = time.split(":");
  const formatter = new Intl.DateTimeFormat("en-CA", {
    timeZone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit"
  });
  const [year, month, day] = formatter.format(now).split("-").map(Number);
  const utcGuess = new Date(Date.UTC(year ?? 1970, (month ?? 1) - 1, day ?? 1, Number(hours), Number(minutes), 0));
  const guessParts = zonedParts(utcGuess, timeZone);
  const offsetMinutes = (Number(hours) * 60 + Number(minutes)) - (guessParts.hour * 60 + guessParts.minute);
  void parts;
  return addMinutes(utcGuess, offsetMinutes);
}

