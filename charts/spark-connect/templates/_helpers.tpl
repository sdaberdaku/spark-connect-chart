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

{{/* Executor image: executor.image.repository and executor.image.tag, each falling back to image.*. */}}
{{- define "spark-connect.executorImage" -}}
{{ .Values.executor.image.repository | default .Values.image.repository }}:{{ .Values.executor.image.tag | default .Values.image.tag | default .Chart.AppVersion }}
{{- end }}

{{- define "spark-connect.driverServiceAccountName" -}}
{{- if .Values.serviceAccount.driver.create }}
{{- default (include "spark-connect.nameWith" (list . "driver")) .Values.serviceAccount.driver.name }}
{{- else if .Values.serviceAccount.driver.name }}
{{- .Values.serviceAccount.driver.name }}
{{- else }}
{{- fail "serviceAccount.driver.name is required when serviceAccount.driver.create is false (the driver needs its own ServiceAccount with rights to manage executor pods)" }}
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
spark.kubernetes.executor.container.image: {{ include "spark-connect.executorImage" . | quote }}
spark.kubernetes.container.image.pullPolicy: {{ .Values.image.pullPolicy | quote }}
spark.kubernetes.authenticate.driver.serviceAccountName: {{ include "spark-connect.driverServiceAccountName" . | quote }}
spark.kubernetes.authenticate.executor.serviceAccountName: {{ include "spark-connect.executorServiceAccountName" . | quote }}
spark.kubernetes.executor.podTemplateFile: /etc/spark-connect/executor-pod-template.yaml
spark.kubernetes.executor.podTemplateContainerName: executor
spark.driver.cores: {{ include "spark-connect.num" .Values.driver.cores | quote }}
spark.driver.memory: "{{ include "spark-connect.num" .Values.driver.memoryMiB }}m"
spark.driver.memoryOverhead: "{{ include "spark-connect.num" .Values.driver.memoryOverheadMiB }}m"
spark.driver.extraJavaOptions: {{ include "spark-connect.confValue" (list "driver.javaOptions" .Values.driver.javaOptions) | quote }}
spark.executor.cores: {{ include "spark-connect.num" .Values.executor.cores | quote }}
spark.executor.memory: "{{ include "spark-connect.num" .Values.executor.memoryMiB }}m"
spark.executor.memoryOverhead: "{{ include "spark-connect.num" .Values.executor.memoryOverheadMiB }}m"
spark.executor.extraJavaOptions: {{ include "spark-connect.confValue" (list "executor.javaOptions" .Values.executor.javaOptions) | quote }}
spark.executor.instances: {{ include "spark-connect.num" .Values.executor.instances | quote }}
spark.kubernetes.executor.request.cores: {{ .Values.executor.cpuRequest | quote }}
spark.jars.ivy: /tmp/.ivy
spark.local.dir: /var/data/spark-local
{{- with .Values.packages }}
{{- $packages := list }}
{{- range $i, $p := . }}{{ $packages = append $packages (include "spark-connect.confValue" (list (printf "packages[%d]" $i) $p)) }}{{ end }}
spark.jars.packages: {{ join "," $packages | quote }}
{{- end }}
{{- if .Values.pools }}
spark.scheduler.allocation.file: /etc/spark-connect/pools.xml
{{- end }}
{{- end }}

{{/* Every key the chart owns (rendered or set at runtime) and what to tell a user who sets it in sparkConf. */}}
{{- define "spark-connect.ownedPaths" -}}
spark.master: " and cannot be overridden (the chart always targets the in-cluster API server)"
spark.kubernetes.namespace: "; use the release namespace instead"
spark.connect.grpc.binding.port: "; use service.ports.connect instead"
spark.ui.port: "; use service.ports.ui instead"
spark.driver.host: " and cannot be overridden (the driver pod IP is set at start)"
spark.kubernetes.driver.pod.name: " and cannot be overridden (the driver pod name is set at start)"
spark.kubernetes.container.image: "; use image.repository and image.tag instead"
spark.kubernetes.executor.container.image: "; use executor.image (or image.repository and image.tag) instead"
spark.kubernetes.container.image.pullPolicy: "; use image.pullPolicy instead"
spark.kubernetes.authenticate.driver.serviceAccountName: "; use serviceAccount.driver instead"
spark.kubernetes.authenticate.executor.serviceAccountName: "; use serviceAccount.executor instead"
spark.kubernetes.executor.podTemplateFile: " and cannot be overridden (the chart renders the executor pod template)"
spark.kubernetes.executor.podTemplateContainerName: " and cannot be overridden (the chart renders the executor pod template)"
spark.driver.cores: "; use driver.cores instead"
spark.driver.memory: "; use driver.memoryMiB instead"
spark.driver.memoryOverhead: "; use driver.memoryOverheadMiB instead"
spark.driver.extraJavaOptions: "; use driver.javaOptions instead"
spark.executor.cores: "; use executor.cores instead"
spark.executor.memory: "; use executor.memoryMiB instead"
spark.executor.memoryOverhead: "; use executor.memoryOverheadMiB instead"
spark.executor.extraJavaOptions: "; use executor.javaOptions instead"
spark.executor.instances: "; use executor.instances instead"
spark.kubernetes.executor.request.cores: "; use executor.cpuRequest instead"
spark.jars.packages: "; use packages instead"
spark.jars.ivy: " and cannot be overridden (the Ivy cache is on an emptyDir under /tmp)"
spark.local.dir: " and cannot be overridden (scratch space is an emptyDir)"
spark.scheduler.allocation.file: "; use pools instead"
spark.connect.authenticate.token: "; use auth instead"
{{- end }}

{{/*
A configuration value as a string; whole floats (numbers from values files) print without an exponent.
Usage: include "spark-connect.confValue" (list "sparkConf.some.key" $value), where the first item is the value path shown in errors. Fails on a map or a list (what an
unescaped dotted key in --set produces) and on a newline.
*/}}
{{- define "spark-connect.confValue" -}}
{{- $label := index . 0 }}
{{- $v := index . 1 }}
{{- if or (kindIs "map" $v) (kindIs "slice" $v) }}
{{- fail (printf "%s is a %s, not a value. Escape the dots in the key, for example --set 'sparkConf.spark\\.sql\\.shuffle\\.partitions=64'" $label (ternary "map" "list" (kindIs "map" $v))) }}
{{- end }}
{{- $out := "" }}
{{- if and (kindIs "float64" $v) (eq $v (floor $v)) }}{{ $out = printf "%d" (int64 $v) }}{{ else }}{{ $out = toString $v }}{{ end }}
{{- if contains "\n" $out }}
{{- fail (printf "%s contains a newline, which Spark properties cannot hold" $label) }}
{{- end }}
{{- $out }}
{{- end }}

{{/* The final spark-defaults.conf map: sparkConf (templated) plus owned keys. Fails on a collision. */}}
{{- define "spark-connect.sparkDefaults" -}}
{{- $root := . }}
{{- $paths := include "spark-connect.ownedPaths" . | fromYaml }}
{{- $out := include "spark-connect.ownedConf" . | fromYaml }}
{{- range $k, $v := .Values.sparkConf }}
{{- if hasKey $paths $k }}
{{- fail (printf "sparkConf.%s is set by the chart%s" $k (get $paths $k)) }}
{{- end }}
{{- $val := tpl (include "spark-connect.confValue" (list (printf "sparkConf.%s" $k) $v)) $root }}
{{- if contains "\n" $val }}
{{- fail (printf "sparkConf.%s contains a newline, which Spark properties cannot hold" $k) }}
{{- end }}
{{- $_ := set $out $k $val }}
{{- end }}
{{- toYaml $out }}
{{- end }}
