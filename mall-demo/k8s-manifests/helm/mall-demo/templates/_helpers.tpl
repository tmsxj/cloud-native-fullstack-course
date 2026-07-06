{{/*
Common labels for all resources
*/}}
{{- define "mall-demo.labels" -}}
app.kubernetes.io/name: {{ .name | default .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: mall-demo
{{- end }}

{{/*
Service labels
*/}}
{{- define "mall-demo.serviceLabels" -}}
app: {{ .serviceName }}
{{ include "mall-demo.labels" (dict "name" .serviceName "Chart" .Chart "Release" .Release) }}
{{- end }}

{{/*
Common annotations for Prometheus scraping
*/}}
{{- define "mall-demo.prometheusAnnotations" -}}
prometheus.io/scrape: "true"
prometheus.io/port: "8080"
prometheus.io/path: {{ .metricsPath | default "/actuator/prometheus" | quote }}
{{- end }}

{{/*
Full image reference
*/}}
{{- define "mall-demo.image" -}}
{{- if .imageOverride }}
{{ .imageOverride }}
{{- else }}
{{ .Values.global.imageRegistry }}/{{ .Values.imagePrefix }}-{{ .imageName }}:{{ .Values.global.imageTag }}
{{- end }}
{{- end }}

{{/*
Topology spread constraints
*/}}
{{- define "mall-demo.topologySpread" -}}
{{- if .Values.topologySpread.enabled }}
topologySpreadConstraints:
  - maxSkew: {{ .Values.topologySpread.maxSkew }}
    topologyKey: {{ .Values.topologySpread.topologyKey }}
    whenUnsatisfiable: DoNotSchedule
    labelSelector:
      matchLabels:
        app: {{ .serviceName }}
{{- end }}
{{- end }}

{{/*
Pod anti-affinity
*/}}
{{- define "mall-demo.antiAffinity" -}}
affinity:
  podAntiAffinity:
    preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 100
        podAffinityTerm:
          labelSelector:
            matchLabels:
              app: {{ .serviceName }}
          topologyKey: kubernetes.io/hostname
{{- end }}

{{/*
Container security context
*/}}
{{- define "mall-demo.securityContext" -}}
securityContext:
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: false
  runAsNonRoot: true
{{- end }}

{{/*
Env vars for database
*/}}
{{- define "mall-demo.dbEnv" -}}
- name: DB_HOST
  value: {{ .Values.global.db.host | quote }}
- name: DB_PORT
  value: {{ .Values.global.db.port | quote }}
- name: DB_USERNAME
  value: {{ .Values.global.db.username | quote }}
- name: DB_PASSWORD
  value: {{ .Values.global.db.password | quote }}
- name: DB_NAME
  value: {{ .dbName | quote }}
{{- end }}

{{/*
Env vars for Redis
*/}}
{{- define "mall-demo.redisEnv" -}}
- name: REDIS_HOST
  value: {{ .Values.global.redis.host | quote }}
- name: REDIS_PORT
  value: {{ .Values.global.redis.port | quote }}
- name: REDIS_PASSWORD
  value: {{ .Values.global.redis.password | quote }}
{{- end }}

{{/*
Env vars for OTel
*/}}
{{- define "mall-demo.otelEnv" -}}
{{- if .Values.global.otel.enabled }}
- name: OTEL_EXPORTER_OTLP_ENDPOINT
  value: {{ .Values.global.otel.endpoint | quote }}
- name: OTEL_SERVICE_NAME
  value: {{ .serviceName | quote }}
{{- end }}
{{- end }}

{{/*
Env vars for Kafka
*/}}
{{- define "mall-demo.kafkaEnv" -}}
- name: KAFKA_BROKERS
  value: {{ .Values.global.kafka.brokers | quote }}
{{- end }}

{{/*
Service name helper
*/}}
{{- define "mall-demo.serviceName" -}}
{{- if contains "gateway" .serviceName }}
api-gateway
{{- else }}
{{ .serviceName }}
{{- end }}
{{- end }}
