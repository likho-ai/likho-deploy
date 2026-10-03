# likho-deploy

Likho in Kubernetes: the Helm charts, the settings of each environment, and the scripts that
roll it out - the same charts for your machine, staging and production.

```
likho-deploy
├── charts/likho-stack      the backing services: PostgreSQL, MongoDB, Redis, NATS, SeaweedFS (S3), Meilisearch
├── charts/likho            the product: four services, the three web apps, the gateway, the public route
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

## Develop

```bash
helm lint charts/likho-stack charts/likho
helm template likho charts/likho -f environments/staging/env.yaml -f environments/local/values.yaml
skaffold diagnose
```

CI lints both charts, renders every environment and checks the objects against the Kubernetes
schemas (kubeconform). The proof is the local cluster: with it running, likho-web-shell's
browser test passes against it (`LIKHO_WEB_URL=http://localhost:8080 pnpm e2e`).
