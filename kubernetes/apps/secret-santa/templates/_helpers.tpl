{{- define "secret-santa.name" -}}
{{ .Release.Name | trunc 63 | trimSuffix "-" }}
{{- end -}}
{{- define "secret-santa.selector" -}}
app.kubernetes.io/name: secret-santa
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
{{- define "secret-santa.image" -}}
{{ .Values.image.repository }}:{{ required "Set image.tag to a published immutable image tag" .Values.image.tag }}
{{- end -}}
