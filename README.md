# likho-deploy

Likho in Kubernetes: the Helm charts, the settings of each environment, and the scripts that
roll it out - the same charts for your machine, staging and production.

```
likho-deploy
├── charts/likho-stack      the backing services: PostgreSQL, MongoDB, Redis, NATS, SeaweedFS (S3), Meilisearch,
│                           ClickHouse; backups, the restore drill, snapshots, their NetworkPolicy
├── charts/likho            the product: the services, the web apps, the gateway, the public route; scaling
│                           (HPA, KEDA), disruption budgets, NetworkPolicies, alerts
├── environments/
│   ├── local/              minikube on your machine (the staging configuration at http://localhost:8080)
│   ├── staging/            env.yaml (synced settings), values.yaml (images, hostname), stack.yaml
│   └── production/         the same, pinned images, two replicas
├── scripts/
│   ├── local.ps1, local.sh    the local cluster, start to finish
│   ├── deploy.ps1, deploy.sh  staging or production: both charts as Helm releases
│   ├── sync-env.py            each repository's .env.<environment> -> environments/<environment>/env.yaml
│   ├── secrets.py             the .env.<environment>.local files -> Kubernetes Secrets (never written to disk)
│   └── render.py              the product chart -> rendered/local/likho.yaml, for Skaffold
└── skaffold.yaml           the local loop: build the seven images, deploy the product, forward :8080
```

## How settings reach a pod

The `.env` files in each service's repository stay the source of truth
([the convention](https://github.com/likho-ai/likho-infra#settings)):

| File in the service's repository | In the cluster | Made by |
| --- | --- | --- |
| `.env.<environment>` (committed, no secrets) | ConfigMap `<service>-env` | `scripts/sync-env.py <environment>`, committed here as `environments/<environment>/env.yaml` |
| `.env.<environment>.local` (ignored by git) | Secret `<service>-secrets` | `scripts/secrets.py <environment>`, applied straight to the cluster |
| what differs in a cluster (an address, a replica count) | the container's `env` | `environments/<environment>/values.yaml` |

A later source wins. The Secret of the backing services (database passwords, S3 keys) comes from
`likho-infra/.env.<environment>.local`; the stack chart creates the database users, the streams
and the buckets from it when its pods start.

The in-cluster addresses the `.env.<environment>` files use (`postgres:5432`, `nats:4222`,
`likho-media:5010`, ...) are the names of the Services here, so nothing is rewritten. One
setting exists only for a cluster: likho-media's `INTERNAL_URL` (`http://likho-media:4010`),
the address the transcription worker downloads originals from, since the public address is
not reachable from inside.

## The local cluster

Needs Docker Desktop, [minikube](https://minikube.sigs.k8s.io/), kubectl, Helm 4, Skaffold 2 and
uv, and the other repositories cloned next to this one (`D:\likho\likho-api`, ...).

```powershell
.\scripts\local.ps1 up      # minikube, the Secrets, the backing services (Helm), the product (Skaffold), :8080
```

The first run builds the seven images inside minikube and the transcription service downloads
its model (1.6 GB) on the first job; later runs rebuild only what changed. Open
http://localhost:8080 and sign in with `admin@example.com` / `admin-password-1`.
`.\scripts\local.ps1 status`, `down`, `destroy` do what they say.

Two things to know. The backing services are a Helm release that Skaffold never touches, so a
redeploy never restarts a database or the event bus; `skaffold run` restarts every pod of the
product (Skaffold labels each run), `skaffold dev` only what changed. And the local cluster runs
the **staging** configuration (`environments/staging/env.yaml`, the `.env.staging.local`
secrets) with `http://localhost:8080` as its address and the development admin login - what is
rehearsed here is what staging gets.

To copy the model you already have instead of downloading it:

```powershell
kubectl -n likho cp "$env:USERPROFILE\.cache\huggingface\hub\models--mobiuslabsgmbh--faster-whisper-large-v3-turbo" `
  "$(kubectl -n likho get pod -l app.kubernetes.io/name=likho-transcription -o name | % { $_ -replace 'pod/','' }):/models/hub/"
```

## Staging and production

1. Secrets: `uv run python ..\likho-infra\scripts\make-env-secrets.py staging`, then fill in the
   domain and the first admin's email in the `.env.staging.local` files it names.
2. Settings: `uv run python scripts/sync-env.py staging` and commit `environments/staging/env.yaml`.
3. `environments/staging/values.yaml`: the image tags to run and the public hostname (`route`:
   an `HTTPRoute` to the cluster's Gateway - NGINX Gateway Fabric, or the cloud's own; TLS ends
   there. Without a Gateway, make `gateway.service.type` a LoadBalancer).
4. With the cluster's context current and `GHCR_USER`/`GHCR_TOKEN` set (a token with
   `read:packages`, because the images are private): `uv run python scripts/secrets.py staging`,
   then `.\scripts\deploy.ps1 staging`.

A release is a change of the image tag in `values.yaml`, committed, and `deploy.ps1` again; a
rollback is `helm -n likho-staging rollback likho` (or the same change the other way).
Production is the same with `production`; its values pin image tags and run two replicas of what
the browser talks to.

Managed databases or object storage: disable the part in `environments/<environment>/stack.yaml`
and point the service's `.env.<environment>.local` at the managed address.

## Scale and operations

What the charts do in a real cluster, and what the cluster must have for it:

| Part | What it does | Switch | The cluster needs |
| --- | --- | --- | --- |
| Worker scaling | The transcription worker is a StatefulSet (a model cache per pod); a KEDA `ScaledObject` adds a pod per job waiting on the `likho-transcription-requested` consumer, up to `keda.maxReplicas`, and removes them slowly (a stopping pod finishes its job: 15 minutes' grace) | `keda.enabled`, `services.likho-transcription.keda` | [KEDA](https://keda.sh) (`helm install keda kedacore/keda -n keda --create-namespace`) |
| HPA | likho-api, the gateway and the web apps on CPU (two pods at least) | `services.<name>.autoscaling`, `gateway.autoscaling` | metrics-server |
| Disruption budgets | every workload with two pods or more keeps all but one through a drain or an upgrade; pods are spread over nodes and zones | `podDisruptionBudgets`, `spreadPods` | - |
| NetworkPolicies | a service is reachable only by the services that call it (`ingressFrom`), the databases only by Likho's pods, NATS's monitoring port also by KEDA and Prometheus; outgoing traffic is free | `networkPolicy.enabled` (both charts) | a CNI that enforces them (Calico, Cilium, the cloud's own) |
| Alerts | a `PodMonitor` for every `/metrics` and a `PrometheusRule`: a job waiting too long, failures, no worker, restarts, volumes filling, a backup failed or missing | `alerts.enabled`, `alerts.labels` | kube-prometheus-stack (the operator, kube-state-metrics) |
| Backups | nightly `likho-backup`: PostgreSQL (`pg_dump` of every `likho_*` database and the roles), MongoDB (`mongodump`), ClickHouse (every table) to S3 under `<namespace>/<UTC time>/`, `keepDays` kept | `backup` in the stack values | an S3 bucket outside the cluster for real use (`backup.s3`) |
| Restore drill | monthly `likho-restore-drill`: the newest backup restored into scratch databases, every table and collection checked, then dropped | `backup.drill` | - |
| Snapshots | nightly `VolumeSnapshot`s of the volumes (the audio is too big to dump) | `snapshots` in the stack values | the CSI snapshot CRDs and a `VolumeSnapshotClass` |
| GPU | `ghcr.io/likho-ai/likho-transcription:<tag>-cuda` (CUDA 12, cuDNN 9) on a GPU node pool: see the commented block in `environments/production/values.yaml` | `image`, `resources`, `nodeSelector`, `tolerations` | GPU nodes with the NVIDIA device plugin |

Production switches all of these on (`environments/production/values.yaml`, `stack.yaml`); the
product chart refuses to render when KEDA or the Prometheus Operator is missing, rather than
failing halfway through an upgrade. Staging has the policies and the backups.

Backups by hand:

```powershell
kubectl -n likho-production create job --from=cronjob/likho-backup likho-backup-now
kubectl -n likho-production create job --from=cronjob/likho-restore-drill likho-drill-now
kubectl -n likho-production logs job/likho-drill-now --all-containers --prefix
```

To restore for real, run the drill's steps against the live names: fetch the backup
(`BACKUP_STAMP` picks one other than the newest), `pg_restore --clean --if-exists -d <db>` each
dump, `mongorestore --drop --gzip --archive`, and recreate each ClickHouse table from its `.sql`
then `INSERT ... FORMAT Native`. Stop the services first (`kubectl scale --replicas=0`).
Meilisearch is not backed up: likho-search rebuilds the index from the transcripts.

The first upgrade to these charts replaces the transcription Deployment with a StatefulSet; its
old model volume is removed and each worker downloads the model once into its own.

## Develop

```bash
helm lint charts/likho-stack charts/likho
helm template likho charts/likho -f environments/staging/env.yaml -f environments/local/values.yaml
skaffold diagnose
```

CI lints both charts, renders every environment and checks the objects against the Kubernetes
schemas (kubeconform). The proof is the local cluster: with it running, likho-web-shell's
browser test passes against it (`LIKHO_WEB_URL=http://localhost:8080 pnpm e2e`).
