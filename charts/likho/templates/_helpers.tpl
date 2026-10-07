{{/* Labels every object carries. */}}
{{- define "likho.labels" -}}
app.kubernetes.io/part-of: likho
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{- end }}

{{/* The labels a workload and its Service match on. */}}
{{- define "likho.selector" -}}
app.kubernetes.io/name: {{ . }}
app.kubernetes.io/instance: likho
{{- end }}

{{/* The in-cluster address of a Service, as nginx's resolver needs it (no search list). */}}
{{- define "likho.upstream" -}}
{{ .name }}.{{ .ctx.Release.Namespace }}.svc.{{ .ctx.Values.clusterDomain }}:{{ .port }}
{{- end }}

{{/* "true" unless the service says enabled: false. */}}
{{- define "likho.enabled" -}}
{{- if not (and (hasKey . "enabled") (not .enabled)) }}true{{ end }}
{{- end }}

{{/* Whether KEDA scales this service (it asks for it and the cluster has KEDA). */}}
{{- define "likho.keda" -}}
{{- if and .ctx.Values.keda.enabled .svc.keda .svc.keda.enabled }}true{{ end }}
{{- end }}

{{/* Whether something else owns the replica count: KEDA, or a HorizontalPodAutoscaler. */}}
{{- define "likho.autoscaled" -}}
{{- if or (include "likho.keda" .) (and .svc.autoscaling .svc.autoscaling.enabled) }}true{{ end }}
{{- end }}

{{/* The fewest pods the service runs: what the autoscaler keeps, or the fixed count. */}}
{{- define "likho.minReplicas" -}}
{{- if include "likho.keda" . }}{{ .svc.keda.minReplicas | default 1 }}
{{- else if and .svc.autoscaling .svc.autoscaling.enabled }}{{ .svc.autoscaling.minReplicas | default 1 }}
{{- else }}{{ .svc.replicas | default 1 }}{{ end }}
{{- end }}

{{/* Spread the pods of one workload over nodes (and zones), as far as the cluster allows. */}}
{{- define "likho.spread" -}}
{{- if .ctx.Values.spreadPods }}
topologySpreadConstraints:
  - maxSkew: 1
    topologyKey: kubernetes.io/hostname
    whenUnsatisfiable: ScheduleAnyway
    labelSelector:
      matchLabels: {{- include "likho.selector" .name | nindent 8 }}
  - maxSkew: 1
    topologyKey: topology.kubernetes.io/zone
    whenUnsatisfiable: ScheduleAnyway
    labelSelector:
      matchLabels: {{- include "likho.selector" .name | nindent 8 }}
{{- end }}
{{- end }}

{{/* "Always" for a floating tag, "IfNotPresent" for a pinned one. */}}
{{- define "likho.pullPolicy" -}}
{{- if or (hasSuffix ":latest" .) (not (contains ":" .)) }}Always{{ else }}IfNotPresent{{ end }}
{{- end }}
