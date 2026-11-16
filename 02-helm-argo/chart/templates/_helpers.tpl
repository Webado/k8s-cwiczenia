{{/*
_helpers.tpl = "funkcje" wielokrotnego użytku dla szablonów.
Pliki zaczynające się od "_" nie generują zasobów, tylko definiują pomocnicze kawałki.
*/}}

{{/* Wspólne labele, dodawane do każdego zasobu */}}
{{- define "demo-app.labels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Values.appVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/* Labele do selektorów. MUSZĄ być stałe (selector w Deploymencie jest niezmienialny!) */}}
{{- define "demo-app.selectorLabels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
