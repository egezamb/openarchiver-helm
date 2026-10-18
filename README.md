# openarchiver-helm

A Helm chart for [Open Archiver](https://github.com/LogicLabs-OU/OpenArchiver). See [charts/open-archiver](charts/open-archiver/README.md).

Community chart, offered upstream in [OpenArchiver#242](https://github.com/LogicLabs-OU/OpenArchiver/issues/242). Issues and test reports are welcome.

## Checks

Every pull request that touches the chart runs:

- `ct lint` and `ct install` on kind, with the value sets in `charts/open-archiver/ci/`;
- `kubeconform` on the rendered manifests for Kubernetes 1.27, 1.30 and 1.33;
- a check that the Artifact Hub image list matches the images the chart deploys;
- [Helmbulance](https://github.com/egezamb/helmbulance)'s `upgrade-without-values`: it upgrades the live release without the install-time values and reports Secrets that change and pods that restart for nothing. It also runs weekly, to catch a changed image upstream.
- Helmbulance's `chart-upgrade`: it installs the latest chart published on GHCR and upgrades it to the chart in the PR, the upgrade users make, and reports a failed upgrade, Secrets the new version changes or drops, and workloads that are not healthy afterwards.

## License

[Apache-2.0](LICENSE). Open Archiver itself is licensed separately by its authors.
