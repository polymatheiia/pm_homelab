# Sparky local patches

Garmin menstrual data -> cycle tracker. Upstream fetches `menstrual_data` in the
garmin microservice but the server never stores it.

- `services/garmin/garminCycleProcessor.ts` (new): writes real (non-predicted)
  Garmin period days as `medium` flow in `cycle_daily_entries`, skipping days
  that already have an entry, then calls `cycleService.recomputeCycles`.
  No-op if cycle tracking is disabled in Sparky settings.
- `services/garminService.ts`: upstream file plus an import and a per-chunk
  hook in `syncGarminData`.

Base image: `codewithcj/sparkyfitness_server@sha256:51a2d7c19bd99b50ea17e579fe8d9d4febed895595356b1ddafe0fa808caf75e`
(created 2026-10-30; rebased 2026-11-03). `garminService.ts` is mounted over the image copy, so it
masks upstream changes to that file. After `docker compose pull`, run:

    docker run --rm --entrypoint cat codewithcj/sparkyfitness_server:latest \
      /app/SparkyFitnessServer/services/garminService.ts | diff - patches/services/garminService.ts

and re-apply the two hunks if upstream changed it (or drop the mounts once
upstream ships cycle import).
