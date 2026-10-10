{{/*
Chart name, shortened to the 63 characters a Kubernetes label allows.
*/}}
{{- define "open-archiver.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Prefix for every resource name. Uses the release name alone when it already contains the chart
name, so `helm install open-archiver .` gives "open-archiver" and not "open-archiver-open-archiver".
*/}}
{{- define "open-archiver.fullname" -}}
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

{{/*
Name of one component, e.g. "open-archiver-postgresql". The prefix is shortened before the suffix
is added, so two components never end up with the same name. 52 characters at most: a StatefulSet
adds a hash to its name in the controller-revision-hash label, which allows 63.
Usage: include "open-archiver.componentName" (dict "root" . "component" "postgresql")
*/}}
{{- define "open-archiver.componentName" -}}
{{- $suffix := printf "-%s" .component }}
{{- $base := include "open-archiver.fullname" .root | trunc (int (sub 52 (len $suffix))) | trimSuffix "-" }}
{{- printf "%s%s" $base $suffix }}
{{- end }}

{{- define "open-archiver.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Labels on every resource.
*/}}
{{- define "open-archiver.labels" -}}
helm.sh/chart: {{ include "open-archiver.chart" . }}
app.kubernetes.io/name: {{ include "open-archiver.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: open-archiver
{{- end }}

{{/*
Selector labels for one component. These go into Deployment and StatefulSet selectors, which
Kubernetes does not allow to change after creation, so nothing version-specific belongs here.
Usage: include "open-archiver.selectorLabels" (dict "root" . "component" "app")
*/}}
{{- define "open-archiver.selectorLabels" -}}
app.kubernetes.io/name: {{ include "open-archiver.name" .root }}
app.kubernetes.io/instance: {{ .root.Release.Name }}
app.kubernetes.io/component: {{ .component }}
{{- end }}

{{/*
All labels for one component.
*/}}
{{- define "open-archiver.componentLabels" -}}
{{ include "open-archiver.labels" .root }}
app.kubernetes.io/component: {{ .component }}
{{- end }}

{{- define "open-archiver.image" -}}
{{- if .Values.image.digest }}
{{- printf "%s@%s" .Values.image.repository .Values.image.digest }}
{{- else }}
{{- printf "%s:%s" .Values.image.repository (default .Chart.AppVersion .Values.image.tag) }}
{{- end }}
{{- end }}

{{- define "open-archiver.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "open-archiver.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Name of the Secret holding the app secrets (JWT, encryption keys).
*/}}
{{- define "open-archiver.secretName" -}}
{{- default (include "open-archiver.fullname" .) .Values.secrets.existingSecret }}
{{- end }}

{{/*
Value of a generated secret. Order: the value from values.yaml, then the value already stored in
the release's Secret (so `helm upgrade` never rotates a password the data stores were initialised
with), then a new random value.
Usage: include "open-archiver.secretValue" (dict "root" . "secret" "name-of-secret" "key" "jwt-secret" "value" .Values.secrets.jwtSecret "length" 64)
*/}}
{{- define "open-archiver.secretValue" -}}
{{- if .value }}
{{- .value }}
{{- else }}
{{- $existing := lookup "v1" "Secret" .root.Release.Namespace .secret }}
{{- if and $existing (index $existing.data .key) }}
{{- index $existing.data .key | b64dec }}
{{- else if .hex }}
{{- randAlphaNum 64 | sha256sum }}
{{- else }}
{{- randAlphaNum (.length | default 32) }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Connection details of PostgreSQL, bundled or external.
*/}}
{{- define "open-archiver.database.host" -}}
{{- if .Values.postgresql.enabled }}
{{- include "open-archiver.componentName" (dict "root" . "component" "postgresql") }}
{{- else }}
{{- required "externalDatabase.host is required when postgresql.enabled is false" .Values.externalDatabase.host }}
{{- end }}
{{- end }}

{{- define "open-archiver.database.port" -}}
{{- if .Values.postgresql.enabled }}5432{{ else }}{{ .Values.externalDatabase.port }}{{ end }}
{{- end }}

{{- define "open-archiver.database.name" -}}
{{- if .Values.postgresql.enabled }}{{ .Values.postgresql.auth.database }}{{ else }}{{ .Values.externalDatabase.database }}{{ end }}
{{- end }}

{{- define "open-archiver.database.user" -}}
{{- if .Values.postgresql.enabled }}{{ .Values.postgresql.auth.username }}{{ else }}{{ required "externalDatabase.username is required when postgresql.enabled is false" .Values.externalDatabase.username }}{{ end }}
{{- end }}

{{- define "open-archiver.database.secretName" -}}
{{- if .Values.postgresql.enabled }}
{{- default (include "open-archiver.componentName" (dict "root" . "component" "postgresql")) .Values.postgresql.auth.existingSecret }}
{{- else }}
{{- default (include "open-archiver.componentName" (dict "root" . "component" "external-db")) .Values.externalDatabase.existingSecret }}
{{- end }}
{{- end }}

{{- define "open-archiver.database.secretKey" -}}
{{- if .Values.postgresql.enabled }}{{ .Values.postgresql.auth.existingSecretPasswordKey }}{{ else }}{{ .Values.externalDatabase.existingSecretPasswordKey }}{{ end }}
{{- end }}

{{/*
Connection details of Valkey / Redis, bundled or external.
*/}}
{{- define "open-archiver.redis.host" -}}
{{- if .Values.valkey.enabled }}
{{- include "open-archiver.componentName" (dict "root" . "component" "valkey") }}
{{- else }}
{{- required "externalRedis.host is required when valkey.enabled is false" .Values.externalRedis.host }}
{{- end }}
{{- end }}

{{- define "open-archiver.redis.port" -}}
{{- if .Values.valkey.enabled }}6379{{ else }}{{ .Values.externalRedis.port }}{{ end }}
{{- end }}

{{- define "open-archiver.redis.secretName" -}}
{{- if .Values.valkey.enabled }}
{{- default (include "open-archiver.componentName" (dict "root" . "component" "valkey")) .Values.valkey.auth.existingSecret }}
{{- else }}
{{- default (include "open-archiver.componentName" (dict "root" . "component" "external-redis")) .Values.externalRedis.existingSecret }}
{{- end }}
{{- end }}

{{- define "open-archiver.redis.secretKey" -}}
{{- if .Values.valkey.enabled }}{{ .Values.valkey.auth.existingSecretPasswordKey }}{{ else }}{{ .Values.externalRedis.existingSecretPasswordKey }}{{ end }}
{{- end }}

{{/*
Connection details of Meilisearch, bundled or external.
*/}}
{{- define "open-archiver.meilisearch.url" -}}
{{- if .Values.meilisearch.enabled }}
{{- printf "http://%s:7700" (include "open-archiver.componentName" (dict "root" . "component" "meilisearch")) }}
{{- else }}
{{- required "externalMeilisearch.url is required when meilisearch.enabled is false" .Values.externalMeilisearch.url }}
{{- end }}
{{- end }}

{{- define "open-archiver.meilisearch.secretName" -}}
{{- if .Values.meilisearch.enabled }}
{{- default (include "open-archiver.componentName" (dict "root" . "component" "meilisearch")) .Values.meilisearch.existingSecret }}
{{- else }}
{{- default (include "open-archiver.componentName" (dict "root" . "component" "external-meilisearch")) .Values.externalMeilisearch.existingSecret }}
{{- end }}
{{- end }}

{{- define "open-archiver.meilisearch.secretKey" -}}
{{- if .Values.meilisearch.enabled }}{{ .Values.meilisearch.existingSecretKey }}{{ else }}{{ .Values.externalMeilisearch.existingSecretKey }}{{ end }}
{{- end }}

{{/*
URL of Tika. Empty when Tika is off, which makes the app fall back to its built-in PDF extractor.
*/}}
{{- define "open-archiver.tika.url" -}}
{{- if .Values.tika.enabled }}
{{- printf "http://%s:9998" (include "open-archiver.componentName" (dict "root" . "component" "tika")) }}
{{- else }}
{{- .Values.externalTika.url }}
{{- end }}
{{- end }}

{{/*
Connection URL of PostgreSQL. It carries no password: the app gets that as PGPASSWORD, which
postgres.js reads itself, so passwords with any characters work (the app double-encodes a password
inside the URL up to v0.6.0).
*/}}
{{- define "open-archiver.database.url" -}}
{{- $user := include "open-archiver.database.user" . | urlquery | replace "+" "%20" }}
{{- $url := printf "postgresql://%s@%s:%s/%s" $user (include "open-archiver.database.host" .) (include "open-archiver.database.port" .) (include "open-archiver.database.name" .) }}
{{- if and (not .Values.postgresql.enabled) .Values.externalDatabase.sslMode }}
{{- $url = printf "%s?sslmode=%s" $url .Values.externalDatabase.sslMode }}
{{- end }}
{{- $url }}
{{- end }}

{{/*
"true" when the Redis server needs a password. Bundled Valkey always has one; an external server
may run without.
*/}}
{{- define "open-archiver.redis.hasPassword" -}}
{{- if or .Values.valkey.enabled .Values.externalRedis.existingSecret .Values.externalRedis.password }}true{{ end }}
{{- end }}

{{/*
"true" when Meilisearch needs a master key. Bundled Meilisearch always has one.
*/}}
{{- define "open-archiver.meilisearch.hasKey" -}}
{{- if or .Values.meilisearch.enabled .Values.externalMeilisearch.existingSecret .Values.externalMeilisearch.masterKey }}true{{ end }}
{{- end }}

{{- define "open-archiver.s3.secretName" -}}
{{- default (include "open-archiver.componentName" (dict "root" . "component" "s3")) .Values.storage.s3.existingSecret }}
{{- end }}

{{/*
PersistentVolumeClaim of the local archive, empty when the archive is not on a claim.
*/}}
{{- define "open-archiver.storage.claimName" -}}
{{- if and (eq .Values.storage.type "local") .Values.storage.persistence.enabled }}
{{- default (include "open-archiver.componentName" (dict "root" . "component" "data")) .Values.storage.persistence.existingClaim }}
{{- end }}
{{- end }}
