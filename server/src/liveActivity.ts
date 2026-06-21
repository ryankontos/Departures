import { createPrivateKey, sign } from "node:crypto";
import { readFileSync } from "node:fs";
import type { Config } from "./config.js";
import type { LiveActivityState } from "./models.js";

type PushKind = "start" | "update" | "end";

export class ApnsLiveActivityClient {
  constructor(private readonly config: Config["apns"]) {}

  get configured(): boolean {
    return Boolean(this.config.teamId && this.config.keyId && this.config.privateKeyPath && this.config.bundleId);
  }

  async pushToStart(token: string, state: LiveActivityState): Promise<void> {
    await this.send(token, "start", state);
  }

  async update(token: string, state: LiveActivityState): Promise<void> {
    await this.send(token, "update", state);
  }

  async end(token: string, state: LiveActivityState): Promise<void> {
    await this.send(token, "end", state);
  }

  private async send(token: string, event: PushKind, state: LiveActivityState): Promise<void> {
    if (!this.configured) {
      console.log(`[apns] ${event} skipped; APNS is not configured`);
      return;
    }

    const url = `${this.host()}/3/device/${token}`;
    const timestamp = Math.floor(Date.now() / 1000);
    const payload: Record<string, unknown> = {
      aps: {
        timestamp,
        event,
        "content-state": state,
        "dismissal-date": timestamp + 60,
        alert: {
          title: state.scheduleName,
          body: state.trips[0] ? `Leave ${formatClock(state.trips[0].leaveTime)} for ${formatClock(state.trips[0].departureTime)}` : "No matching departures"
        }
      }
    };

    if (event === "start") {
      payload.aps = {
        ...(payload.aps as Record<string, unknown>),
        attributes: {
          scheduleId: state.scheduleId,
          scheduleName: state.scheduleName
        },
        "attributes-type": "DepartureActivityAttributes"
      };
    }

    const response = await fetch(url, {
      method: "POST",
      headers: {
        authorization: `bearer ${this.jwt()}`,
        "apns-topic": `${this.config.bundleId}.push-type.liveactivity`,
        "apns-push-type": "liveactivity",
        "apns-priority": "10",
        "content-type": "application/json"
      },
      body: JSON.stringify(payload)
    });

    if (!response.ok) {
      const body = await response.text();
      throw new Error(`APNS ${event} failed with ${response.status}: ${body}`);
    }
  }

  private host(): string {
    return this.config.environment === "production" ? "https://api.push.apple.com" : "https://api.sandbox.push.apple.com";
  }

  private jwt(): string {
    const header = base64Url(JSON.stringify({ alg: "ES256", kid: this.config.keyId }));
    const claims = base64Url(JSON.stringify({ iss: this.config.teamId, iat: Math.floor(Date.now() / 1000) }));
    const signingInput = `${header}.${claims}`;
    const key = createPrivateKey(readFileSync(this.config.privateKeyPath!, "utf8"));
    const signature = sign("sha256", Buffer.from(signingInput), key);
    return `${signingInput}.${base64Url(signature)}`;
  }
}

function base64Url(input: string | Buffer): string {
  return Buffer.from(input).toString("base64url");
}

function formatClock(iso: string): string {
  return new Intl.DateTimeFormat("en-AU", { hour: "numeric", minute: "2-digit" }).format(new Date(iso));
}

