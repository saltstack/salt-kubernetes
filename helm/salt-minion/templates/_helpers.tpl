{{/* Per-image registry overrides the global registry. */}}
{{- define "salt-minion.image" -}}
{{- $registry := .image.registry | default .global.imageRegistry -}}
{{- if $registry -}}
{{- printf "%s/%s:%v" (trimSuffix "/" $registry) .image.repository .image.tag -}}
{{- else -}}
{{- printf "%s:%v" .image.repository .image.tag -}}
{{- end -}}
{{- end -}}

{{/* Resolve the minion image from chart values. */}}
{{- define "salt-minion.agentImage" -}}
{{- include "salt-minion.image" (dict "image" .Values.agent.image "global" .Values.global) -}}
{{- end -}}

{{/* Resolve the key-generation image from chart values. */}}
{{- define "salt-minion.keygenImage" -}}
{{- include "salt-minion.image" (dict "image" .Values.agent.keygenImage "global" .Values.global) -}}
{{- end -}}

{{/* Per-image pull secrets override global pull secrets. */}}
{{- define "salt-minion.imagePullSecrets" -}}
{{- with (.image.imagePullSecrets | default .global.imagePullSecrets) -}}
imagePullSecrets:
{{ toYaml . | indent 2 }}
{{- end -}}
{{- end -}}

{{/* Resolve pull secrets for the minion image. */}}
{{- define "salt-minion.agentImagePullSecrets" -}}
{{- include "salt-minion.imagePullSecrets" (dict "image" .Values.agent.image "global" .Values.global) -}}
{{- end -}}

{{/* Resolve pull secrets for the key-generation image. */}}
{{- define "salt-minion.keygenImagePullSecrets" -}}
{{- include "salt-minion.imagePullSecrets" (dict "image" .Values.agent.keygenImage "global" .Values.global) -}}
{{- end -}}
