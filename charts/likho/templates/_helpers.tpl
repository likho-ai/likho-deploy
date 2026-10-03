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

{{/* "Always" for a floating tag, "IfNotPresent" for a pinned one. */}}
{{- define "likho.pullPolicy" -}}
{{- if or (hasSuffix ":latest" .) (not (contains ":" .)) }}Always{{ else }}IfNotPresent{{ end }}
{{- end }}
