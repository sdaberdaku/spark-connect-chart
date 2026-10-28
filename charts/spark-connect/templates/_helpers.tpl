{{- define "spark-connect.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "spark-connect.fullname" -}}
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

{{/* fullname plus a suffix, with the fullname shortened so the result stays within 63 characters. Usage: include "spark-connect.nameWith" (list . "driver") */}}
{{- define "spark-connect.nameWith" -}}
{{- $suffix := index . 1 }}
{{- printf "%s-%s" (include "spark-connect.fullname" (index . 0) | trunc (int (sub 62 (len $suffix))) | trimSuffix "-") $suffix }}
{{- end }}

{{- define "spark-connect.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "spark-connect.selectorLabels" -}}
app.kubernetes.io/name: {{ include "spark-connect.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "spark-connect.labels" -}}
helm.sh/chart: {{ include "spark-connect.chart" . }}
{{ include "spark-connect.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "spark-connect.image" -}}
{{ .Values.image.repository }}:{{ .Values.image.tag | default .Chart.AppVersion }}
{{- end }}

{{- define "spark-connect.driverServiceAccountName" -}}
{{- if .Values.serviceAccount.driver.create }}
{{- default (include "spark-connect.nameWith" (list . "driver")) .Values.serviceAccount.driver.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.driver.name }}
{{- end }}
{{- end }}

{{- define "spark-connect.executorServiceAccountName" -}}
{{- if .Values.serviceAccount.executor.create }}
{{- default (include "spark-connect.nameWith" (list . "executor")) .Values.serviceAccount.executor.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.executor.name }}
{{- end }}
{{- end }}

{{- define "spark-connect.podSecurityContext" -}}
{{- toYaml .Values.podSecurityContext }}
{{- end }}

{{- define "spark-connect.containerSecurityContext" -}}
{{- toYaml .Values.securityContext }}
{{- end }}

{{/* Integers from values.yaml arrive as float64; print them without an exponent. */}}
{{- define "spark-connect.num" -}}
{{- if kindIs "float64" . }}{{ int64 . }}{{ else }}{{ . }}{{ end }}
{{- end }}

{{/*
Spark properties the chart sets. Rendered into spark-defaults.conf; sparkConf may not set any of them.
Keys set at runtime by the driver Deployment (driver host, pod name, auth token) are not rendered here.
*/}}
{{- define "spark-connect.ownedConf" -}}
{{- $ns := .Release.Namespace }}
{{- $image := include "spark-connect.image" . }}
spark.master: k8s://https://kubernetes.default.svc
spark.kubernetes.namespace: {{ $ns | quote }}
spark.connect.grpc.binding.port: {{ include "spark-connect.num" .Values.service.ports.connect | quote }}
spark.ui.port: {{ include "spark-connect.num" .Values.service.ports.ui | quote }}
spark.kubernetes.container.image: {{ $image | quote }}
spark.kubernetes.executor.container.image: {{ $image | quote }}
spark.kubernetes.container.image.pullPolicy: {{ .Values.image.pullPolicy | quote }}
spark.kubernetes.authenticate.driver.serviceAccountName: {{ include "spark-connect.driverServiceAccountName" . | quote }}
spark.kubernetes.authenticate.executor.serviceAccountName: {{ include "spark-connect.executorServiceAccountName" . | quote }}
spark.kubernetes.executor.podTemplateFile: /etc/spark-connect/executor-pod-template.yaml
spark.kubernetes.executor.podTemplateContainerName: executor
spark.driver.cores: {{ include "spark-connect.num" .Values.driver.cores | quote }}
spark.driver.memory: "{{ include "spark-connect.num" .Values.driver.memoryMiB }}m"
spark.driver.memoryOverhead: "{{ include "spark-connect.num" .Values.driver.memoryOverheadMiB }}m"
spark.driver.extraJavaOptions: {{ .Values.driver.javaOptions | quote }}
spark.executor.cores: {{ include "spark-connect.num" .Values.executor.cores | quote }}
spark.executor.memory: "{{ include "spark-connect.num" .Values.executor.memoryMiB }}m"
spark.executor.memoryOverhead: "{{ include "spark-connect.num" .Values.executor.memoryOverheadMiB }}m"
spark.executor.extraJavaOptions: {{ .Values.executor.javaOptions | quote }}
spark.executor.instances: {{ include "spark-connect.num" .Values.executor.instances | quote }}
spark.kubernetes.executor.request.cores: {{ .Values.executor.cpuRequest | quote }}
spark.jars.ivy: /tmp/.ivy
spark.local.dir: /var/data/spark-local
{{- with .Values.packages }}
spark.jars.packages: {{ join "," . | quote }}
{{- end }}
{{- if .Values.pools }}
spark.scheduler.allocation.file: /etc/spark-connect/pools.xml
{{- end }}
{{- end }}

{{/* Every key the chart owns (rendered or set at runtime) and the value to use instead. */}}
{{- define "spark-connect.ownedPaths" -}}
spark.master: nothing (the chart always targets the in-cluster API server)
spark.kubernetes.namespace: the release namespace
spark.connect.grpc.binding.port: service.ports.connect
spark.ui.port: service.ports.ui
spark.driver.host: nothing (the driver pod IP is set at start)
spark.kubernetes.driver.pod.name: nothing (the driver pod name is set at start)
spark.kubernetes.container.image: image.repository and image.tag
spark.kubernetes.executor.container.image: image.repository and image.tag
spark.kubernetes.container.image.pullPolicy: image.pullPolicy
spark.kubernetes.authenticate.driver.serviceAccountName: serviceAccount.driver
spark.kubernetes.authenticate.executor.serviceAccountName: serviceAccount.executor
spark.kubernetes.executor.podTemplateFile: nothing (the chart renders the executor pod template)
spark.kubernetes.executor.podTemplateContainerName: nothing (the chart renders the executor pod template)
spark.driver.cores: driver.cores
spark.driver.memory: driver.memoryMiB
spark.driver.memoryOverhead: driver.memoryOverheadMiB
spark.driver.extraJavaOptions: driver.javaOptions
spark.executor.cores: executor.cores
spark.executor.memory: executor.memoryMiB
spark.executor.memoryOverhead: executor.memoryOverheadMiB
spark.executor.extraJavaOptions: executor.javaOptions
spark.executor.instances: executor.instances
spark.kubernetes.executor.request.cores: executor.cpuRequest
spark.jars.packages: packages
spark.jars.ivy: nothing (the Ivy cache is on an emptyDir under /tmp)
spark.local.dir: nothing (scratch space is an emptyDir)
spark.scheduler.allocation.file: pools
spark.connect.authenticate.token: auth
{{- end }}

{{/* A configuration value as a string; whole floats (numbers from values files) print without an exponent. */}}
{{- define "spark-connect.confValue" -}}
{{- if and (kindIs "float64" .) (eq . (floor .)) }}{{ printf "%d" (int64 .) }}{{ else }}{{ toString . }}{{ end }}
{{- end }}

{{/* The final spark-defaults.conf map: sparkConf (templated) plus owned keys. Fails on a collision. */}}
{{- define "spark-connect.sparkDefaults" -}}
{{- $root := . }}
{{- $paths := include "spark-connect.ownedPaths" . | fromYaml }}
{{- $out := include "spark-connect.ownedConf" . | fromYaml }}
{{- range $k, $v := .Values.sparkConf }}
{{- if hasKey $paths $k }}
{{- fail (printf "sparkConf.%s is set by the chart; use %s instead" $k (get $paths $k)) }}
{{- end }}
{{- $_ := set $out $k (tpl (include "spark-connect.confValue" $v) $root) }}
{{- end }}
{{- toYaml $out }}
{{- end }}
