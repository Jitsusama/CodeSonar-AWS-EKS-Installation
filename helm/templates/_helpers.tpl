{{- define "chart.installName" -}}
{{ .Release.Name }}
{{- end }}

{{- define "launchd.name" -}}
{{ include "chart.installName" . }}-launchd
{{- end }}

{{- define "launchd.group" -}}
remotes
{{- end }}

{{- define "hub.name" -}}
{{ include "chart.installName" . }}-hub
{{- end }}

{{- define "hub.internalPort" -}}
7340
{{- end }}

{{- define "hub.externalPort" -}}
{{ .Values.hub.port }}
{{- end }}

{{- define "hub.tempListeningAddress" -}}
0.0.0.0:{{ add (include "hub.internalPort" .) 30 }}
{{- end }}

{{- define "hub.tempBaseUri" -}}
{{- if .Values.hub.tls_cert -}}
https://{{ include "hub.tempListeningAddress" . }}
{{- else -}}
http://{{ include "hub.tempListeningAddress" . }}
{{- end -}}
{{- end }}

{{- define "hub.listeningAddress" -}}
0.0.0.0:{{ include "hub.internalPort" . }}
{{- end }}

{{- define "hub.baseUri" -}}
{{- if .Values.hub.tls_cert -}}
https://{{ include "hub.name" . }}:{{ include "hub.externalPort" . }}
{{- else -}}
http://{{ include "hub.name" . }}:{{ include "hub.externalPort" . }}
{{- end -}}
{{- end }}
