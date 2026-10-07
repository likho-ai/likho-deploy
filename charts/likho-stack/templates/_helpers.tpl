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

{{/* Where the backups go: the S3 endpoint, bucket and prefix, and the keys to write there. */}}
{{- define "likho-stack.backupEnv" -}}
{{- $s3 := .Values.backup.s3 }}
- { name: S3_ENDPOINT, value: {{ $s3.endpoint | quote }} }
- { name: S3_BUCKET, value: {{ $s3.bucket | quote }} }
- { name: S3_PREFIX, value: {{ $s3.prefix | default (printf "%s/" .Release.Namespace) | quote }} }
- { name: AWS_DEFAULT_REGION, value: {{ $s3.region | quote }} }
{{- if $s3.secret }}
- name: AWS_ACCESS_KEY_ID
  valueFrom: { secretKeyRef: { name: {{ $s3.secret }}, key: AWS_ACCESS_KEY_ID } }
- name: AWS_SECRET_ACCESS_KEY
  valueFrom: { secretKeyRef: { name: {{ $s3.secret }}, key: AWS_SECRET_ACCESS_KEY } }
{{- else }}
- name: AWS_ACCESS_KEY_ID
  valueFrom: { secretKeyRef: { name: {{ .Values.secrets.name }}, key: S3_ACCESS_KEY } }
- name: AWS_SECRET_ACCESS_KEY
  valueFrom: { secretKeyRef: { name: {{ .Values.secrets.name }}, key: S3_SECRET_KEY } }
{{- end }}
{{- end }}

{{/* The storage class line of a volume claim, if one is set. */}}
{{- define "likho-stack.storageClass" -}}
{{- if .Values.storageClass }}
storageClassName: {{ .Values.storageClass | quote }}
{{- end }}
{{- end }}
