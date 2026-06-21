import "dotenv/config";

export type Config = {
  port: number;
  publicApiBaseUrl: string;
  databasePath: string;
  timeZone: string;
  tfnswApiKey?: string;
  apns: {
    teamId?: string;
    keyId?: string;
    privateKeyPath?: string;
    bundleId?: string;
    environment: "sandbox" | "production";
  };
};

export function loadConfig(): Config {
  return {
    port: Number(process.env.PORT ?? "8080"),
    publicApiBaseUrl: process.env.PUBLIC_API_BASE_URL ?? "https://departures.ryankontos.com/api",
    databasePath: process.env.DATABASE_PATH ?? "./data/departures.sqlite",
    timeZone: process.env.TIME_ZONE ?? "Australia/Sydney",
    tfnswApiKey: emptyToUndefined(process.env.TFNSW_API_KEY),
    apns: {
      teamId: emptyToUndefined(process.env.APNS_TEAM_ID),
      keyId: emptyToUndefined(process.env.APNS_KEY_ID),
      privateKeyPath: emptyToUndefined(process.env.APNS_PRIVATE_KEY_PATH),
      bundleId: emptyToUndefined(process.env.APNS_BUNDLE_ID),
      environment: process.env.APNS_ENVIRONMENT === "production" ? "production" : "sandbox"
    }
  };
}

function emptyToUndefined(value: string | undefined): string | undefined {
  return value && value.trim().length > 0 ? value : undefined;
}
