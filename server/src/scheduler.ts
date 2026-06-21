import type { ApnsLiveActivityClient } from "./liveActivity.js";
import type { DepartureSchedule, LiveActivityState } from "./models.js";
import type { Storage } from "./storage.js";
import type { TfnswClient } from "./tfnsw.js";
import { isTimeInWindow, zonedParts } from "./time.js";

export class ScheduleWorker {
  private timer: NodeJS.Timeout | undefined;

  constructor(
    private readonly storage: Storage,
    private readonly tfnsw: TfnswClient,
    private readonly apns: ApnsLiveActivityClient,
    private readonly timeZone: string
  ) {}

  start() {
    this.tick().catch((error) => console.error("[scheduler] initial tick failed", error));
    this.timer = setInterval(() => {
      this.tick().catch((error) => console.error("[scheduler] tick failed", error));
    }, 60_000);
  }

  stop() {
    if (this.timer) clearInterval(this.timer);
  }

  async tick(now = new Date()) {
    const schedules = this.storage.listSchedules().filter((schedule) => this.isActive(schedule, now));
    for (const schedule of schedules) {
      await this.updateSchedule(schedule, now);
    }
  }

  private async updateSchedule(schedule: DepartureSchedule, now: Date) {
    const trips = await this.tfnsw.previewTrips(schedule, now);
    const activeActivities = this.storage.activeLiveActivitiesForSchedule(schedule.id);
    const devices = this.storage.listDevices(schedule.userId);

    const state: LiveActivityState = {
      scheduleId: schedule.id,
      scheduleName: schedule.name,
      generatedAt: now.toISOString(),
      walkMinutes: schedule.walkMinutes,
      selectedTripId: activeActivities[0]?.selectedTripId,
      trips
    };

    for (const activity of activeActivities) {
      if (!activity.activityPushToken) continue;
      await this.apns.update(activity.activityPushToken, {
        ...state,
        selectedTripId: activity.selectedTripId
      });
      this.storage.upsertLiveActivity({
        ...activity,
        lastState: state,
        updatedAt: now.toISOString()
      });
    }

    if (activeActivities.length === 0) {
      for (const device of devices.filter((device) => device.pushToStartToken)) {
        await this.apns.pushToStart(device.pushToStartToken!, state);
        this.storage.upsertLiveActivity({
          activityId: `${schedule.id}:${device.deviceId}`,
          userId: schedule.userId,
          scheduleId: schedule.id,
          deviceId: device.deviceId,
          status: "active",
          lastState: state,
          updatedAt: now.toISOString()
        });
      }
    }
  }

  private isActive(schedule: DepartureSchedule, now: Date): boolean {
    if (!schedule.enabled) return false;
    const parts = zonedParts(now, this.timeZone);
    return schedule.weekdays.includes(parts.weekday) && isTimeInWindow(parts.time, schedule.activeStartTime, schedule.activeEndTime);
  }
}
