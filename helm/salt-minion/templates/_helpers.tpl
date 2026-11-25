{{/* Validation */}}
{{- define "salt-minion.validateKeyPair" -}}
{{- $minion := .Values.agent.minion -}}
{{- if ne (empty $minion.privateKeyB64) (empty $minion.publicKeyB64) -}}
{{- fail "agent.minion.privateKeyB64 and agent.minion.publicKeyB64 must be set together" -}}
{{- end -}}
{{- end -}}

{{- define "salt-minion.validateKeySource" -}}
{{- $minion := .Values.agent.minion -}}
{{- if not (or $minion.keySecretName $minion.privateKeyB64 $minion.allowSelfGeneratedKey) -}}
{{- fail "set agent.minion.keySecretName or both agent.minion.privateKeyB64 and agent.minion.publicKeyB64, or enable agent.minion.allowSelfGeneratedKey" -}}
{{- end -}}
{{- end -}}

{{/* Values */}}
{{- define "salt-minion.keySecretName" -}}
{{- .Values.agent.minion.keySecretName | default (printf "%s-keys" .Release.Name) -}}
{{- end -}}

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

{{/* Enabled decisions */}}
{{- define "salt-minion.keySecretEnabled" -}}
{{- if .Values.agent.minion.privateKeyB64 -}}
true
{{- end -}}
{{- end -}}

{{- define "salt-minion.keygenEnabled" -}}
{{- $minion := .Values.agent.minion -}}
{{- if and (eq .Values.agent.authMode "in_cluster") $minion.allowSelfGeneratedKey (not $minion.keySecretName) (not $minion.privateKeyB64) -}}
true
{{- end -}}
{{- end -}}

{{- define "salt-minion.keygenJobEnabled" -}}
{{- if include "salt-minion.keygenEnabled" . -}}
{{- if include "salt-minion.perPodKeys" . -}}
true
{{- else -}}
{{- $secretName := include "salt-minion.keySecretName" . -}}
{{- if not (lookup "v1" "Secret" .Values.namespace $secretName) -}}
true
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{- define "salt-minion.keygenRbacEnabled" -}}
{{- if and .Values.rbac.create (include "salt-minion.keygenEnabled" .) -}}
true
{{- end -}}
{{- end -}}

{{/*
StatefulSet name. Pods are named <name>-<ordinal> and the entrypoint falls
back to the pod hostname for the minion ID, so this doubles as the ID prefix.
*/}}
{{- define "salt-minion.workloadName" -}}
{{- .Values.agent.minion.idPrefix | default "salt-minion" -}}
{{- end -}}

{{/* Space-separated pod names (== minion IDs) of every replica. */}}
{{- define "salt-minion.podNames" -}}
{{- $name := include "salt-minion.workloadName" . -}}
{{- $names := list -}}
{{- range $i := until (int .Values.agent.replicas) -}}
{{- $names = append $names (printf "%s-%d" $name $i) -}}
{{- end -}}
{{- join " " $names -}}
{{- end -}}

{{/* "true" when each replica needs its own keypair (replicas > 1). */}}
{{- define "salt-minion.perPodKeys" -}}
{{- if gt (int .Values.agent.replicas) 1 -}}
true
{{- end -}}
{{- end -}}

{{/* Every replica is a separate minion, so it needs its own ID and keypair. */}}
{{- define "salt-minion.validateReplicas" -}}
{{- $minion := .Values.agent.minion -}}
{{- if include "salt-minion.perPodKeys" . -}}
{{- if $minion.id -}}
{{- fail "agent.minion.id cannot be used with agent.replicas > 1 (every pod would register as the same minion); use agent.minion.idPrefix to get <prefix>-0, <prefix>-1, ..." -}}
{{- end -}}
{{- if $minion.privateKeyB64 -}}
{{- fail "agent.minion.privateKeyB64/publicKeyB64 hold a single keypair and cannot be used with agent.replicas > 1; set agent.minion.keySecretName to a Secret with per-pod keys, or enable agent.minion.allowSelfGeneratedKey" -}}
{{- end -}}
{{- end -}}
{{- end -}}
