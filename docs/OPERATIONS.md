# Production Observability Design

This is a design document; the production observability platform is not implemented
in the local lab.

## 1. Goals

Production observability must answer:

1. Is the user-facing service available?
2. Is it fast enough?
3. Are errors increasing?
4. Which release is serving traffic?
5. Is Kubernetes healthy?
6. Is the node/runtime healthy?
7. Did a deployment cause the change?
8. Is the observability platform itself healthy?

## 2. Signal model

### Application

Collect:

- request rate
- success/error rate
- latency distribution
- active requests
- readiness/liveness state
- process restarts
- application-specific business errors

### Kubernetes

Collect:

- node Ready state
- CPU/memory/disk pressure
- pod restarts
- Pending/Failed pods
- Deployment availability
- replica mismatch
- scheduling failures
- eviction events
- ingress/controller errors

### Node/runtime

Collect:

- CPU
- memory
- filesystem/inodes
- network errors/drops
- conntrack utilization
- file-descriptor utilization
- containerd health
- kubelet health
- clock synchronization

### Logs

Centralize structured application logs and Kubernetes/node logs.

Sensitive values must be redacted before collection where possible.

## 3. Metrics architecture

A typical production design:

```text
Applications / Kubernetes / Nodes
            |
            v
     Prometheus agents
            |
            v
     Central metrics store
            |
      +-----+-----+
      |           |
   Grafana     Alertmanager
      |           |
 dashboards     paging
```

The exact stack is intentionally left as an implementation choice, but the
ownership and retention requirements are not.

## 4. Dashboards

### Service dashboard

- traffic
- success rate
- p50/p95/p99 latency
- 4xx/5xx
- current release
- available/unavailable replicas

### Kubernetes dashboard

- node availability
- CPU/memory utilization
- pod health
- restart rates
- pending workloads
- cluster control-plane health

### Deployment dashboard

- deployment start/end
- rollout duration
- desired/current/available replicas
- error-rate comparison before/after release
- current image digest
- Git commit/release ID

## 5. Alerting

Examples:

### Availability

Alert when:

- service availability breaches the SLO
- no healthy replicas remain
- ingress returns sustained 5xx

### Latency

Alert when p95/p99 latency exceeds the service threshold for a sustained window.

### Kubernetes

Alert on:

- NodeNotReady
- sustained resource pressure
- excessive pod restarts
- deployment unavailable
- unschedulable pods
- persistent storage failures

### Observability

Alert when:

- metrics ingestion stops
- log ingestion drops unexpectedly
- alert delivery fails
- central storage is unavailable

The observability system must monitor itself.

## 6. SLOs and error budgets

For an HTTP service, start with an availability SLO such as:

```text
Availability = successful eligible requests / total eligible requests
```

and define a latency SLO separately.

Example policy:

- availability SLO: 99.9%
- latency SLO: 99% of eligible requests below the service latency target

The actual targets must come from business requirements rather than being assumed
because they are common industry numbers.

Error budget consumption controls release risk:

- healthy budget -> normal deployment
- elevated burn -> progressive rollout / additional verification
- exhausted budget -> freeze non-essential risky changes and prioritize reliability

## 7. Retention and access

Retention should be selected from:

- incident investigation needs
- regulatory requirements
- storage cost
- query performance
- business requirements

Access should follow least privilege:

- developers: service/application views
- SRE: platform and incident data
- security: audit/security data
- restricted production secrets are never exposed through dashboards or logs

## 8. Observability failure

Production must remain operable if the monitoring platform fails.

The workload should continue serving traffic even when metrics storage or dashboards
are unavailable.

Critical alerting paths should have redundancy and should not depend on the same
failure domain as the workload where practical.

During observability loss:

- Kubernetes-native status/events remain available
- logs may remain buffered locally for a bounded period
- synthetic checks provide an independent availability signal
- recovery includes checking for data gaps

## 9. Deployment verification

Every production deployment should produce an observable release marker:

```text
service=demo-app
release=2026.10.26-abc1234
image_digest=sha256:...
```

The deployment system correlates this marker with:

- Git commit
- CI pipeline
- deployment time
- Kubernetes rollout
- alert events

This makes "what changed?" answerable during an incident.

## 10. Production readiness boundary

The local lab intentionally demonstrates Kubernetes-native visibility rather than
claiming that it is a production monitoring platform. Production adds centralized
metrics/logs, durable retention, alert routing, SLOs, dashboards, access control,
and monitoring-of-monitoring.
