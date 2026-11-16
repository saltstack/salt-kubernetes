{{/* Format an image repository and tag. */}}
{{- define "salt-minion.image" -}}
{{- printf "%s:%s" .repository (toString .tag) -}}
{{- end -}}

{{/* Resolve the minion image from chart values. */}}
{{- define "salt-minion.agentImage" -}}
{{- include "salt-minion.image" .Values.agent.image -}}
{{- end -}}

{{/* Resolve the key-generation image from chart values. */}}
{{- define "salt-minion.keygenImage" -}}
{{- include "salt-minion.image" .Values.keygen.image -}}
{{- end -}}
