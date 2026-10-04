{{/*
Имя чарта (обрезано до 63 символов).
*/}}
{{- define "homework.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Полное имя (release-name + chart-name).
*/}}
{{- define "homework.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Версия чарта как label.
*/}}
{{- define "homework.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Общие labels.
*/}}
{{- define "homework.labels" -}}
helm.sh/chart: {{ include "homework.chart" . }}
{{ include "homework.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels — неизменны, используются в Deployment.selector и Service.selector.
ВАЖНО: те же labels должны быть в обоих местах.
*/}}
{{- define "homework.selectorLabels" -}}
app.kubernetes.io/name: {{ include "homework.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Имя ServiceAccount.
*/}}
{{- define "homework.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "homework.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Имя ClusterRole (уникальное для релиза).
*/}}
{{- define "homework.clusterRoleName" -}}
{{- .Values.rbac.clusterRoleName | default (printf "%s-metrics-reader" .Release.Name) }}
{{- end }}

{{/*
Имя ClusterRoleBinding (уникальное для релиза).
*/}}
{{- define "homework.clusterRoleBindingName" -}}
{{- .Values.rbac.clusterRoleBindingName | default (printf "%s-metrics-reader-binding" .Release.Name) }}
{{- end }}  