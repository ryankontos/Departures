import { mkdirSync } from "node:fs";
import { dirname } from "node:path";
import { DatabaseSync } from "node:sqlite";
import type { DepartureSchedule, LiveActivityState } from "./models.js";
import { scheduleSchema } from "./models.js";

export type DeviceRecord = {
  userId: string;
  deviceId: string;
  name?: string;
  devicePushToken?: string;
  pushToStartToken?: string;
  updatedAt: string;
};

export type LiveActivityRecord = {
  activityId: string;
  userId: string;
  scheduleId: string;
  deviceId: string;
  activityPushToken?: string;
  selectedTripId?: string;
  status: "active" | "ended";
  lastState?: LiveActivityState;
  updatedAt: string;
};

export class Storage {
  private db: DatabaseSync;

  constructor(path: string) {
    mkdirSync(dirname(path), { recursive: true });
    this.db = new DatabaseSync(path);
    this.db.exec(`
      CREATE TABLE IF NOT EXISTS schedules (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL DEFAULT 'local',
        value TEXT NOT NULL,
        updated_at TEXT NOT NULL
      );
      CREATE TABLE IF NOT EXISTS devices (
        device_id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL DEFAULT 'local',
        name TEXT,
        device_push_token TEXT,
        push_to_start_token TEXT,
        updated_at TEXT NOT NULL
      );
      CREATE TABLE IF NOT EXISTS live_activities (
        activity_id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL DEFAULT 'local',
        schedule_id TEXT NOT NULL,
        device_id TEXT NOT NULL,
        activity_push_token TEXT,
        selected_trip_id TEXT,
        status TEXT NOT NULL,
        last_state TEXT,
        updated_at TEXT NOT NULL
      );
    `);
    this.addColumnIfMissing("devices", "device_push_token", "TEXT");
  }

  listSchedules(): DepartureSchedule[] {
    const rows = this.db.prepare("SELECT value FROM schedules ORDER BY json_extract(value, '$.name')").all() as { value: string }[];
    return rows.map((row) => scheduleSchema.parse(JSON.parse(row.value)));
  }

  listSchedulesForUser(userId: string): DepartureSchedule[] {
    const rows = this.db.prepare("SELECT value FROM schedules WHERE user_id = ? ORDER BY json_extract(value, '$.name')").all(userId) as { value: string }[];
    return rows.map((row) => scheduleSchema.parse(JSON.parse(row.value)));
  }

  getSchedule(id: string): DepartureSchedule | undefined {
    const row = this.db.prepare("SELECT value FROM schedules WHERE id = ?").get(id) as { value: string } | undefined;
    return row ? scheduleSchema.parse(JSON.parse(row.value)) : undefined;
  }

  upsertSchedule(schedule: DepartureSchedule): DepartureSchedule {
    this.db.prepare("INSERT OR REPLACE INTO schedules (id, user_id, value, updated_at) VALUES (?, ?, ?, ?)").run(
      schedule.id,
      schedule.userId,
      JSON.stringify(schedule),
      schedule.updatedAt
    );
    return schedule;
  }

  deleteSchedule(id: string): boolean {
    const result = this.db.prepare("DELETE FROM schedules WHERE id = ?").run(id);
    return result.changes > 0;
  }

  upsertDevice(record: DeviceRecord) {
    this.db.prepare(`
      INSERT INTO devices (device_id, user_id, name, device_push_token, push_to_start_token, updated_at)
      VALUES (?, ?, ?, ?, ?, ?)
      ON CONFLICT(device_id) DO UPDATE SET
        user_id = excluded.user_id,
        name = excluded.name,
        device_push_token = COALESCE(excluded.device_push_token, devices.device_push_token),
        push_to_start_token = COALESCE(excluded.push_to_start_token, devices.push_to_start_token),
        updated_at = excluded.updated_at
    `).run(record.deviceId, record.userId, record.name ?? null, record.devicePushToken ?? null, record.pushToStartToken ?? null, record.updatedAt);
  }

  listDevices(userId?: string): DeviceRecord[] {
    const sql = userId
      ? "SELECT user_id, device_id, name, device_push_token, push_to_start_token, updated_at FROM devices WHERE user_id = ?"
      : "SELECT user_id, device_id, name, device_push_token, push_to_start_token, updated_at FROM devices";
    const rows = (userId ? this.db.prepare(sql).all(userId) : this.db.prepare(sql).all()) as Array<{
      user_id: string;
      device_id: string;
      name?: string;
      device_push_token?: string;
      push_to_start_token?: string;
      updated_at: string;
    }>;
    return rows.map((row) => ({
      userId: row.user_id,
      deviceId: row.device_id,
      name: row.name,
      devicePushToken: row.device_push_token,
      pushToStartToken: row.push_to_start_token,
      updatedAt: row.updated_at
    }));
  }

  upsertLiveActivity(record: LiveActivityRecord) {
    this.db.prepare(`
      INSERT INTO live_activities (activity_id, user_id, schedule_id, device_id, activity_push_token, selected_trip_id, status, last_state, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(activity_id) DO UPDATE SET
        user_id = excluded.user_id,
        activity_push_token = COALESCE(excluded.activity_push_token, live_activities.activity_push_token),
        selected_trip_id = COALESCE(excluded.selected_trip_id, live_activities.selected_trip_id),
        status = excluded.status,
        last_state = COALESCE(excluded.last_state, live_activities.last_state),
        updated_at = excluded.updated_at
    `).run(
      record.activityId,
      record.userId,
      record.scheduleId,
      record.deviceId,
      record.activityPushToken ?? null,
      record.selectedTripId ?? null,
      record.status,
      record.lastState ? JSON.stringify(record.lastState) : null,
      record.updatedAt
    );
  }

  activeLiveActivitiesForSchedule(scheduleId: string): LiveActivityRecord[] {
    const rows = this.db.prepare("SELECT * FROM live_activities WHERE schedule_id = ? AND status = 'active'").all(scheduleId) as any[];
    return rows.map(rowToLiveActivity);
  }

  private addColumnIfMissing(table: string, column: string, type: string) {
    const rows = this.db.prepare(`PRAGMA table_info(${table})`).all() as Array<{ name: string }>;
    if (!rows.some((row) => row.name === column)) {
      this.db.exec(`ALTER TABLE ${table} ADD COLUMN ${column} ${type}`);
    }
  }
}

function rowToLiveActivity(row: any): LiveActivityRecord {
  return {
    activityId: row.activity_id,
    userId: row.user_id,
    scheduleId: row.schedule_id,
    deviceId: row.device_id,
    activityPushToken: row.activity_push_token ?? undefined,
    selectedTripId: row.selected_trip_id ?? undefined,
    status: row.status,
    lastState: row.last_state ? JSON.parse(row.last_state) : undefined,
    updatedAt: row.updated_at
  };
}
