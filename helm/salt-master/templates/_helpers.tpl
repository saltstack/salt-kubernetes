{{- define "salt-master.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "salt-master.fullname" -}}
{{- $name := include "salt-master.name" . -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else }}
{{- if .Values.nameOverride }}
{{- printf "%s-%s" .Release.Name (include "salt-master.name" .) | trunc 63 | trimSuffix "-" -}}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end }}
{{- end }}
{{- end -}}

{{- define "salt-master.labels" -}}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version | replace "+" "_" }}
app.kubernetes.io/name: {{ include "salt-master.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | default "" }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "salt-master.selectorLabels" -}}
app.kubernetes.io/name: {{ include "salt-master.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "salt-master.clusterId" -}}
{{- .Values.agent.cluster.id | default .Release.Name -}}
{{- end -}}

{{- define "salt-master.clusterSecretName" -}}
{{- .Values.agent.cluster.secretName | default (printf "%s-cluster-secret" .Release.Name) -}}
{{- end -}}

{{/* Directory holding the accepted minion keys: cluster_pki_dir in cluster mode. */}}
{{- define "salt-master.keysDir" -}}
{{- if .Values.agent.cluster.enabled -}}/etc/salt/pki/cluster{{- else -}}/etc/salt/pki/master{{- end -}}
{{- end -}}

{{/* Comma-separated per-ordinal FQDNs of every replica (peers; self is dropped by the entrypoint). */}}
{{- define "salt-master.clusterPeers" -}}
{{- $peers := list -}}
{{- range $i := until (int .Values.agent.replicas) -}}
{{- $peers = append $peers (printf "salt-master-%d.salt-master-headless.%s.svc.%s" $i $.Values.namespace $.Values.agent.cluster.clusterDomain) -}}
{{- end -}}
{{- join "," $peers -}}
{{- end -}}

{{- define "salt-master.validate" -}}
{{- $c := .Values.agent.cluster -}}
{{- if and $c.enabled (not (has $c.storageMode (list "isolated" "shared"))) -}}
{{- fail "agent.cluster.storageMode must be 'isolated' or 'shared'." -}}
{{- end -}}
{{- if and $c.enabled (lt (int .Values.agent.replicas) 2) -}}
{{- fail "agent.cluster.enabled requires agent.replicas >= 2: Salt refuses to start a cluster member that has no peers." -}}
{{- end -}}
{{- if and $c.hostNetwork (not $c.enabled) -}}
{{- fail "agent.cluster.hostNetwork requires agent.cluster.enabled." -}}
{{- end -}}
{{- if and $c.enabled (eq $c.storageMode "shared") (not $c.sharedStorage.existingClaim) -}}
{{- fail "agent.cluster.sharedStorage.existingClaim (a ReadWriteMany PVC) is required when agent.cluster.storageMode=shared." -}}
{{- end -}}
{{- if and (gt (int .Values.agent.replicas) 1) (not $c.enabled) (not .Values.agent.masterKeySecretName) -}}
{{- fail "agent.masterKeySecretName is required when agent.replicas > 1 and agent.cluster.enabled is false (every replica must share one keypair)." -}}
{{- end -}}
{{- end -}}
