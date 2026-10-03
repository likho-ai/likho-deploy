{{/* Labels every object carries. */}}
{{- define "likho-stack.labels" -}}
app.kubernetes.io/part-of: likho
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{- end }}

{{/* The labels a workload and its Service match on: app.kubernetes.io/name=<component>. */}}
{{- define "likho-stack.selector" -}}
app.kubernetes.io/name: {{ . }}
app.kubernetes.io/instance: likho
{{- end }}

{{/* The storage class line of a volume claim, if one is set. */}}
{{- define "likho-stack.storageClass" -}}
{{- if .Values.storageClass }}
storageClassName: {{ .Values.storageClass | quote }}
{{- end }}
{{- end }}
