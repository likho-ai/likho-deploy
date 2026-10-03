# The local cluster, start to finish:
#   .\scripts\local.ps1 up        start minikube (if needed), make the Secrets, install the backing services
#                                 (Helm), build and deploy the product (Skaffold), forward the gateway to
#                                 http://localhost:8080 and rebuild what you change
#   .\scripts\local.ps1 run       the same, once (no watching)
#   .\scripts\local.ps1 status    what is running
#   .\scripts\local.ps1 down      remove Likho and the backing services from the cluster (the cluster stays)
#   .\scripts\local.ps1 destroy   delete the cluster
# The local cluster runs the staging configuration (environments/staging/env.yaml and the
# .env.staging.local secrets) at http://localhost:8080; see environments/local/values.yaml.
param(
    [ValidateSet('up', 'run', 'status', 'down', 'destroy')] [string] $Command = 'up',
    [int] $Cpus = 4,
    [int] $MemoryMB = 5120
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

function Ensure-Stack {
    & uv run python scripts/secrets.py staging --namespace likho --allow-placeholders
    if ($LASTEXITCODE -ne 0) { throw 'secrets were not applied' }
    & helm upgrade --install likho-stack charts/likho-stack --namespace likho -f environments/local/stack.yaml --wait --timeout 10m
    if ($LASTEXITCODE -ne 0) { throw 'the backing services did not come up' }
    & uv run python scripts/render.py local
    if ($LASTEXITCODE -ne 0) { throw 'the charts did not render' }
}

function Ensure-Cluster {
    $status = & minikube status --format '{{.Host}}' 2>$null
    if ($status -ne 'Running') {
        Write-Host "Starting minikube ($Cpus cpus, $MemoryMB MB)..."
        & minikube start --driver=docker --container-runtime=docker --cpus=$Cpus --memory=$MemoryMB --addons=storage-provisioner --addons=default-storageclass
        if ($LASTEXITCODE -ne 0) { throw 'minikube did not start' }
    }
    & kubectl config use-context minikube | Out-Null
}

switch ($Command) {
    'up' {
        Ensure-Cluster
        Ensure-Stack
        & skaffold dev --port-forward
    }
    'run' {
        Ensure-Cluster
        Ensure-Stack
        & skaffold run
        Write-Host 'Reach it with: kubectl -n likho port-forward svc/likho-gateway 8080:80'
    }
    'status' {
        & minikube status
        & kubectl -n likho get pods,pvc
    }
    'down' {
        & skaffold delete
        & helm uninstall likho-stack --namespace likho
    }
    'destroy' {
        & minikube delete
    }
}
