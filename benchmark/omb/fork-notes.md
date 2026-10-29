# OMB build notes

The benchmark harness uses [OpenMessaging Benchmark](https://github.com/openmessaging/openmessaging-benchmark) (Apache 2.0, upstream).

## Clone + build

```bash
# From repo root
cd benchmark/omb
git clone https://github.com/openmessaging/openmessaging-benchmark.git
cd ../..
make benchmark-build-image       # builds + pushes to your ECR per .env OMB_IMAGE
```

Alternatively, override the source location via env var:
```
OMB_FORK_SRC=/absolute/path/to/your/omb-checkout make benchmark-build-image
```

## Scale limits with upstream OMB

Upstream OMB auto-creates topics via a single `AdminClient.createTopics(...)` call. At scale (150 topics × 100 partitions = 15,000 partitions × RF=3 = 45,000 replicas), the Kafka controller can't complete that within OMB's 30s request timeout and all futures hang.

**For benchmarks up to ~50-100 topics**: upstream OMB works out of the box. The `benchmark/scripts/pre-create-topics.sh` script in this kit creates the topics in advance, and OMB's `createTopics` call becomes a quick no-op (topic already exists).

**For benchmarks at 150+ topics × 100+ partitions**: upstream OMB will time out on `createTopics` even after pre-creation (it still issues the call and blocks waiting). To run at this scale you need to:
- Reduce `BENCHMARK_TOPIC_COUNT` and `BENCHMARK_PARTITIONS_PER_TOPIC` in `.env` so the total stays under ~5,000 partitions, OR
- Patch OMB to skip `createTopics` when a `topicNames` field is set in the workload YAML (and reference that field from the pre-populated list in `benchmark/scripts/render-templates.sh`). See the patch sketch below.

## Patch sketch for `topicNames` support

If you want to run at 150-topic scale, apply this patch to upstream OMB after cloning:

In `benchmark-framework/src/main/java/io/openmessaging/benchmark/Workload.java`, add a field:
```java
public java.util.List<String> topicNames = null;
```

In `benchmark-framework/src/main/java/io/openmessaging/benchmark/WorkloadGenerator.java`, replace the `createTopics` call (currently around line 74) with:
```java
if (workload.topicNames == null || workload.topicNames.isEmpty()) {
    worker.createTopics(new TopicsInfo(workload.topics, workload.partitionsPerTopic));
}
// Otherwise, trust that topics have been pre-created (via pre-create-topics.sh)
// and skip the slow createTopics call.
```

Rebuild with `make benchmark-build-image`. The kit's `benchmark/scripts/render-templates.sh` already generates `topicNames: [...]` in each workload YAML from `BENCHMARK_TOPIC_COUNT`, so no further changes are needed.

## Skipping the build entirely

If you have an existing OMB image available in your registry, just set `OMB_IMAGE` in `.env` to that image reference and skip `make benchmark-build-image`. The kit will deploy using whatever image you specify.
