# QBZ RPM Repository

Official RPM repository for [QBZ](https://github.com/vicrodh/qbz), including
the Qt desktop player (`qbz`) and the standalone headless daemon (`qbzd`).

The repository currently targets:

- supported Fedora releases;
- recent openSUSE Tumbleweed snapshots;
- other RPM distributions meeting QBZ's glibc floor.

The released desktop binary requires glibc 2.35 on x86_64 and 2.39 on
aarch64. The standalone `qbzd` binary requires glibc 2.35 on both
architectures.

## Install

With DNF, add the repository:

```bash
sudo curl --fail --location \
  --output /etc/yum.repos.d/qbz.repo \
  https://vicrodh.github.io/qbz-rpm/qbz.repo
```

Then install either the desktop package:

```bash
sudo dnf install qbz
```

or the smaller daemon-only package:

```bash
sudo dnf install qbzd
```

With Zypper, place the same repository definition under its native path:

```bash
sudo curl --fail --location \
  --output /etc/zypp/repos.d/qbz.repo \
  https://vicrodh.github.io/qbz-rpm/qbz.repo
sudo zypper refresh qbz
sudo zypper install qbz
```

The desktop package already includes `qbzd`. Choose `qbzd` by itself for a
headless installation; the package manager treats the two packages as
alternatives and replaces one with the other when requested.

The signing key fingerprint is published on the
[repository landing page](https://vicrodh.github.io/qbz-rpm/). DNF asks for
confirmation before importing it.

`qbzd` does not require systemd. A user unit is included for convenience,
and the binary can generate definitions for systemd, OpenRC, or runit:

```bash
qbzd service --user YOUR_USER --bin /usr/bin/qbzd
```

## Repository contents

Every successful stable QBZ release publishes exactly four RPMs:

- `QBZ-X.Y.Z-1.x86_64.rpm`
- `QBZ-X.Y.Z-1.aarch64.rpm`
- `qbzd-X.Y.Z-1.x86_64.rpm`
- `qbzd-X.Y.Z-1.aarch64.rpm`

This repository waits until all four assets exist, verifies their embedded
name/version/architecture metadata, signs every RPM, builds and signs the
`createrepo_c` metadata, and deploys one atomic GitHub Pages artifact.
Only stable `vX.Y.Z` releases are accepted.
The Pages repository contains the latest stable version; older RPMs remain
available from the corresponding GitHub Release.

Published layout:

```text
qbz.repo
qbz-rpm-key.gpg
repo/
  x86_64/
    *.rpm
    repodata/
  aarch64/
    *.rpm
    repodata/
```

Both package signatures (`gpgcheck=1`) and repository metadata signatures
(`repo_gpgcheck=1`) are required by [qbz.repo](qbz.repo).

## Maintainer setup

The workflow needs one Actions secret:

- `GPG_PRIVATE_KEY`: ASCII-armored private key dedicated to repository
  signing. It must be usable non-interactively; keep an offline backup.

The release assets are public, so no download PAT is stored here.

The `APT_REPO_TOKEN` secret in `vicrodh/qbz`, used by the release workflows
for `repository_dispatch`, must also have access to `vicrodh/qbz-rpm`.
After the workflow lands on `main`, configure GitHub Pages to use
**GitHub Actions** as its source.

Manual publication is available from the Actions tab by supplying an existing
stable tag. It signs and deploys Pages, so it must follow the release gate.

## Local verification

`scripts/build-repository.sh` is the same implementation used in CI. It
expects the four final RPM filenames, `rpm`/RPM signing tools,
`createrepo_c`, and an imported GPG secret key:

```bash
scripts/build-repository.sh 2.1.0 staging public SIGNING_KEY_FINGERPRINT
```

It never deletes the destination and refuses to operate unless that directory
is empty.
