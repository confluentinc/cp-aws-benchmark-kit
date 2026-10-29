# OMB (OpenMessaging Benchmark) — forked image

The cp-benchmark-kit uses a fork of upstream OMB that adds a `topicNames: [...]` field to the workload YAML. This lets OMB use pre-created topics (via `benchmark/scripts/pre-create-topics.sh`) instead of calling `AdminClient.createTopics()`, which times out at 150+ topics.

## Rebuild

```bash
bash build.sh   # builds + pushes to $OMB_IMAGE from .env
```

## Fork origin

- Upstream: https://github.com/openmessaging/openmessaging-benchmark
- Fork patch: adds `topicNames` field support in `benchmark/driver-kafka/src/main/java/.../WorkloadGenerator.java`

See the `openmessaging-benchmark/` folder in the ORIGINAL repo (prior to cp-benchmark-kit consolidation) for the full fork — needs to be copied/submoduled into this repo if rebuilding is required. For a one-time deploy, pointing `.env`'s `OMB_IMAGE` at an existing ECR image is sufficient.

## Dockerfile

The fork repo has `docker/Dockerfile` and `docker/Dockerfile.build` — a two-stage build that compiles OMB JARs in a maven image and then packages into a minimal runtime image. Multi-arch (amd64 + arm64).

```bash
cd openmessaging-benchmark   # fork repo
docker buildx build --platform linux/arm64 \
  -t ${OMB_IMAGE} \
  -f docker/Dockerfile .
docker push ${OMB_IMAGE}
```

## TODO (if making this fully self-contained)

- Vendor the fork repo as a git submodule here, OR
- Commit a single `Dockerfile` + `build.sh` + a `fork-notes.md` describing exactly which upstream SHA + the patch diff, so an engineer could re-create the fork from upstream if needed.
