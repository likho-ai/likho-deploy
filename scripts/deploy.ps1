# Rolls an environment out: both charts as Helm releases, in the kubectl context you name.
#   .\scripts\deploy.ps1 staging -Context my-staging-cluster
#   .\scripts\deploy.ps1 production -Context my-production-cluster
# Before the first roll-out of an environment: fill in the .env.<environment>.local files
# (likho-infra/scripts/make-env-secrets.py), then `uv run python scripts/secrets.py <environment>`
# with GHCR_USER and GHCR_TOKEN set, in the same context. A release is a change of an image tag
# in environments/<environment>/values.yaml, committed, then this script again; a rollback is
# `helm -n likho-<environment> rollback likho`.
param(
    [Parameter(Mandatory = $true)] [ValidateSet('staging', 'production')] [string] $Environment,
    [string] $Context = '',
    [switch] $DryRun
)
$ErrorActionPreference = 'Stop'
Set-Location (Split-Path -Parent $PSScriptRoot)
$namespace = "likho-$Environment"
$common = @('--namespace', $namespace, '--wait', '--timeout', '15m')
if ($Context) { $common += @('--kube-context', $Context) }
if ($DryRun) { $common += '--dry-run' }

& helm upgrade --install likho-stack charts/likho-stack -f "environments/$Environment/stack.yaml" @common
if ($LASTEXITCODE -ne 0) { throw 'the backing services did not roll out' }
& helm upgrade --install likho charts/likho -f "environments/$Environment/env.yaml" -f "environments/$Environment/values.yaml" @common
if ($LASTEXITCODE -ne 0) { throw 'the product did not roll out' }
& helm list --namespace $namespace $(if ($Context) { @('--kube-context', $Context) })
