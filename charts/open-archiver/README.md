# Open Archiver Helm chart

A Helm chart for [Open Archiver](https://github.com/LogicLabs-OU/OpenArchiver), the self-hosted email archive with full-text search.

> **Status:** community chart, not yet official. It is offered upstream in [OpenArchiver#242](https://github.com/LogicLabs-OU/OpenArchiver/issues/242). Version 0.1.0 deploys Open Archiver v0.6.0. Feedback and test reports are very welcome.

It deploys the Open Archiver application. It can also run PostgreSQL, Valkey (Redis-compatible), Meilisearch and Apache Tika for you; each one can be replaced by an existing service of your own.

## Install

The chart is not in a Helm repository yet, so install it from a clone:

```sh
git clone https://github.com/egezamb/openarchiver-helm && cd openarchiver-helm
helm install archive ./charts/open-archiver \
  --namespace archive --create-namespace \
  --set appUrl=http://localhost:3000

kubectl --namespace archive port-forward svc/archive-open-archiver 3000:3000
```

Then open http://localhost:3000 and create the first admin user.

- **First start takes a few minutes.** The image downloads its Node dependencies from registry.npmjs.org and runs the database migrations every time it starts, so the pod needs egress to the npm registry.
- **`appUrl` must be the address users open.** The app uses it for CORS and the login origin check. A different address makes logins fail.

## With your own PostgreSQL, Redis and Meilisearch

Turn off the bundled services and point the chart at yours. Credentials come from an existing Secret, so they never appear in values:

```sh
kubectl --namespace archive create secret generic archive-external \
  --from-literal=password='…' \
  --from-literal=redis-password='…' \
  --from-literal=meili-master-key='…'
```

```yaml
# values-external.yaml
appUrl: https://archive.example.com

postgresql:
  enabled: false
externalDatabase:
  host: postgres.example.internal
  port: 5432
  database: open_archive
  username: open_archiver
  existingSecret: archive-external        # key: password (the app role's)
  sslMode: verify-full                    # needs TLS on the server; private CA: see "TLS to external services";
                                          # remove for a plaintext in-cluster database

valkey:
  enabled: false
externalRedis:
  host: redis.example.internal
  port: 6379
  existingSecret: archive-external        # key: redis-password
  # username: only for servers with ACL users; leave unset for requirepass

meilisearch:
  enabled: false
externalMeilisearch:
  url: http://meilisearch.example.internal:7700
  existingSecret: archive-external        # key: meili-master-key

tika:
  enabled: false
externalTika:
  url: ""   # empty: the app uses its built-in PDF extractor (no OCR, 50 MB attachments)
```

```sh
helm install archive ./charts/open-archiver -n archive -f values-external.yaml
```

Notes for external services:

- **Database password.** It is passed as `PGPASSWORD`, never inside `DATABASE_URL`, so passwords with characters such as `@ : / # ?` work as they are.
- **Database role.** It needs to own its database, because the app runs migrations on start. It does not need to be a superuser.
- **Redis/Valkey.** A server with `requirepass` only must be used without a username. Set `externalRedis.username` only for ACL users.
- **Meilisearch.** The app uses the master key.

## Settings you should set before production

| Setting | Why |
|---|---|
| `appUrl` with `https://`, plus `ingress.tls` | The login token is kept in a cookie without the `Secure` flag, so plain HTTP exposes it. The chart refuses an Ingress without TLS unless `ingress.allowInsecureHttp: true`. |
| `secrets.storageEncryptionKey` (64 hex characters, `openssl rand -hex 32`) | Encrypts the archived emails at rest. Without it, files are stored unencrypted. Once set, the chart keeps it on upgrades and refuses a different one. Set `secrets.requireStorageEncryptionKey: true` so a missing key stops the pod instead of archiving unencrypted. |
| `secrets.existingSecret` and the other `existingSecret` values, when you use Argo CD | The chart generates missing secrets and keeps them with `lookup`. Argo CD renders without cluster access, so it would generate new ones on every sync. |
| `storage.persistence` or `storage.type: s3` | The archive itself. With persistence disabled it lives in an `emptyDir` and is lost with the pod. |
| `resources` | The defaults suit a small archive. Large imports (PST, mbox) need more memory, and `indexingWorkerMaxOldSpaceMb` must stay well below the memory limit. |

## Backups

Back up these together:
- the PostgreSQL database;
- the archive volume or bucket;
- the chart's Secrets (`kubectl -n <namespace> get secret -l app.kubernetes.io/instance=<release> -o yaml`).

`ENCRYPTION_KEY` protects the stored mailbox credentials, and `STORAGE_ENCRYPTION_KEY` protects the archived files. Without them that data cannot be read.

The Meilisearch index can be rebuilt from the database and the archive. Its snapshots stay on the Meilisearch volume, so copy them elsewhere if you rely on them.

For the bundled PostgreSQL:

```sh
kubectl -n archive exec archive-open-archiver-postgresql-0 -- pg_dump -U postgres -Fc open_archive > open_archive.dump
```

`helm uninstall` keeps the generated Secrets and the archive volume, on purpose. To remove everything:

```sh
kubectl -n archive delete secret,pvc -l app.kubernetes.io/instance=archive
```

## Security

- **App container (Pod Security `baseline`).**
  - The Open Archiver image runs as root, because its entrypoint installs dependencies and writes to `/app` on every start.
  - All capabilities are dropped, privilege escalation is off, and seccomp is `RuntimeDefault`.
  - User namespaces are off by default. Where the cluster supports them (Kubernetes 1.33+), set `hostUsers: false` to map root in the container to an unprivileged user on the node.
- **Bundled services (`restricted`).** They run as fixed non-root users with read-only root filesystems.
- **PostgreSQL roles.** The app connects as its own role, which owns the database but is not a superuser. The `postgres` superuser can only log in through the local socket (`kubectl exec`).
- **NetworkPolicy** (on by default, needs a CNI that enforces it).
  - Only the web UI port of the app is reachable. The internal API port is not.
  - PostgreSQL, Valkey, Meilisearch and Tika accept connections from the app only, and have no egress.
  - Tika parses untrusted attachments and has no authentication of its own. If your CNI does not enforce NetworkPolicy, consider turning Tika off.
- **TLS to external services.**
  - Use `sslMode: verify-full`; `require` encrypts but does not check the server. For a private CA, mount the bundle with `extraVolumes`/`extraVolumeMounts` and set `NODE_EXTRA_CA_CERTS` in `extraEnv`.
  - The app does not verify the certificate of a TLS Redis server, so keep that connection on a private network.

## Upgrading

The bundled services pin exact versions:
- **PostgreSQL:** a major upgrade needs a dump and restore.
- **Meilisearch:** check its upgrade guide before a minor upgrade; `meilisearch.extraEnv` can pass `MEILI_UPGRADE_DB=true`.
- **Volume settings:** sizes and storage classes of the bundled services cannot change after install, because StatefulSet volume templates are immutable. Grow a volume by editing its PVC.

## Values

See [`values.yaml`](values.yaml). Every setting is commented there, and `values.schema.json` rejects unknown keys and invalid values at install time.

## Testing

```sh
helm test archive -n archive --logs
```

The chart is linted and installed on kind in CI with two value sets (`ci/`).
