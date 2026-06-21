# Architecture

## Product Loop

1. The iOS app creates a private anonymous installation ID in Keychain and registers a device plus ActivityKit push-to-start token with the server.
2. You create one or more route schedules with active weekdays, start/stop time, route endpoints, walking lead time, and arrival constraints.
3. The server wakes once per minute, finds active schedules for `Australia/Sydney`, and asks TfNSW Trip Planner for candidate journeys.
4. The server starts or updates a Live Activity using APNS live activity pushes.
5. The Live Activity shows trips, leave countdowns, train departure countdowns, and arrival times.
6. Tapping a trip deep-links into the app to select that trip; the server can then focus future updates on it.

## Why The Server Owns Scheduling

iOS apps cannot reliably run arbitrary code at exactly 7:00am every weekday while suspended. The server can run the schedule reliably and use APNS to start or update Live Activities. This is also the right split for eventual hosting on a cloud VM/container.

## Accountless Identity

The first version does not need accounts. Each app install creates a random `userId` once, stores it in Keychain, and sends it as `X-Departures-User` on every request. The server scopes schedules, registered devices, and Live Activities by that ID. If this ever becomes a public app, that same column can be linked to Sign in with Apple without rewriting the schedule model.

## TfNSW API Notes

The current Trip Planner technical manual documents:

- API base: `https://api.transport.nsw.gov.au/v1/tp/`
- Common response parameter: `outputFormat=rapidJSON`
- Common coordinate parameter: `coordOutputFormat=EPSG:4326`
- Stop search: `stop_finder`
- Trip planning: `trip`
- Departure board: `departure_mon`
- Service alerts: `add_info`
- Auth header: `Authorization: apikey <token>`

For multi-step journeys such as Hornsby to Chatswood to Martin Place, `trip` is the primary endpoint. `departure_mon` remains useful later for station-board style views.

## Live Activity Caveat

Remote start requires ActivityKit push-to-start support, available on modern iOS versions. If push-to-start is unavailable or disabled, the app can still start a Live Activity locally and the server can update it after receiving the activity push token.
