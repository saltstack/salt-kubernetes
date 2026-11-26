{{/*
The namespace the operator watches, and where its Role/RoleBinding live.
Empty means cluster-wide (ClusterRole). By default this is the namespace the
release is installed into; watchNamespace overrides it, and clusterWide: true
selects cluster-wide watching.
*/}}
{{- define "salt-key-operator.watchNamespace" -}}
{{- if not .Values.clusterWide -}}
{{- .Values.watchNamespace | default .Release.Namespace -}}
{{- end -}}
{{- end -}}
