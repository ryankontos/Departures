# Production Endpoint

The app is configured to use:

```text
https://departures.ryankontos.com/api
```

## Home Mac Hosting

Start the server locally on the Mac:

```sh
npm --prefix server run dev
```

The server listens on port `8080`. Put a reverse proxy or Cloudflare Tunnel in front of it:

```text
departures.ryankontos.com -> http://127.0.0.1:8080
```

The API routes already include the `/api` prefix, so the proxy should forward the full path unchanged. For example:

```text
https://departures.ryankontos.com/api/schedules -> http://127.0.0.1:8080/api/schedules
```

## Checks

Local:

```sh
curl http://127.0.0.1:8080/api/health
```

Public:

```sh
curl https://departures.ryankontos.com/api/health
```

## Cloud Move Later

Keep `PUBLIC_API_BASE_URL=https://departures.ryankontos.com/api` and move the same service to a VM/container. SQLite can move with a persistent volume at first; Postgres is the natural later upgrade if the app becomes public.

