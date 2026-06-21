# Departures

Personal Sydney transport departure companion for iPhone, Apple Watch, widgets, and Live Activities.

The app is designed around scheduled commute windows. You configure a route, active days, start/stop times, how long it takes to leave for the station, and how many trips to surface. The server wakes those schedules, queries the Transport for NSW Trip Planner API, and updates Live Activities through APNS.

No account is required. The app creates a private anonymous install ID and uses it to identify itself to your server automatically.

## Stack

- iOS/watchOS: SwiftUI, ActivityKit, WidgetKit, XcodeGen
- Server: Node.js 24, TypeScript, Fastify, SQLite
- Transport data: TfNSW Trip Planner APIs at `https://api.transport.nsw.gov.au/v1/tp/`

## Repo Layout

- `apps/ios/DeparturesApp`: iPhone SwiftUI app
- `apps/ios/LiveActivityExtension`: Lock Screen, Dynamic Island, and widget extension
- `apps/ios/Shared`: Swift models shared by app and extension
- `apps/watch/DeparturesWatchApp`: Apple Watch companion app scaffold
- `server`: Fastify API, TfNSW client, APNS client, schedule worker
- `docs`: architecture and API notes

## First Run

```sh
cp server/.env.example server/.env
npm --prefix server install
npm --prefix server run dev
```

Generate the Xcode project:

```sh
xcodegen generate
open Departures.xcodeproj
```

The app defaults to the production endpoint:

```text
https://departures.ryankontos.com/api
```

## Cloud Migration Path

The server is intentionally stateless apart from SQLite and environment variables. Run the same service behind `https://departures.ryankontos.com/api` on the home Mac now. For a cloud move, migrate the same Node service, move the database to a managed volume or replace the repository with Postgres, and keep APNS/TfNSW secrets in the host secret manager.

## Production Endpoint On A Home Mac

Run the server on the Mac:

```sh
cp server/.env.example server/.env
npm --prefix server run dev
```

Point `departures.ryankontos.com` at the Mac using Cloudflare Tunnel or another reverse proxy, forwarding HTTPS traffic to:

```text
http://127.0.0.1:8080
```

Health checks:

```sh
curl http://127.0.0.1:8080/api/health
curl https://departures.ryankontos.com/api/health
```
