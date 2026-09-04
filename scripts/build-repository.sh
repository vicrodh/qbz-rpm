#!/usr/bin/env bash

set -euo pipefail

usage() {
  echo "Usage: $0 VERSION STAGING_DIR OUTPUT_DIR GPG_FINGERPRINT" >&2
}

if (( $# != 4 )); then
  usage
  exit 2
fi

version="$1"
staging_dir="$2"
output_dir="$3"
requested_fingerprint="${4//[[:space:]]/}"

if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "VERSION must have the stable X.Y.Z form: $version" >&2
  exit 2
fi
if [[ ! -d "$staging_dir" ]]; then
  echo "Staging directory does not exist: $staging_dir" >&2
  exit 2
fi
if [[ ! "$requested_fingerprint" =~ ^[[:xdigit:]]{40}([[:xdigit:]]{24})?$ ]]; then
  echo "GPG_FINGERPRINT must be a full 40- or 64-hex-digit fingerprint" >&2
  exit 2
fi
if [[ -e "$output_dir" ]] &&
   [[ -n "$(find "$output_dir" -mindepth 1 -maxdepth 1 -print -quit)" ]]; then
  echo "Output directory must be absent or empty: $output_dir" >&2
  exit 2
fi

required_commands=(createrepo_c find gpg install rpm rpmkeys rpmsign sha256sum)
for command_name in "${required_commands[@]}"; do
  if ! command -v "$command_name" >/dev/null; then
    echo "Required command is missing: $command_name" >&2
    exit 2
  fi
done

mapfile -d '' -t staged_rpms < <(
  find "$staging_dir" -maxdepth 1 -type f -name '*.rpm' -print0
)
if (( ${#staged_rpms[@]} != 4 )); then
  echo "Expected exactly four RPMs in $staging_dir; found ${#staged_rpms[@]}" >&2
  exit 1
fi

expected_files=(
  "QBZ-${version}-1.x86_64.rpm"
  "QBZ-${version}-1.aarch64.rpm"
  "qbzd-${version}-1.x86_64.rpm"
  "qbzd-${version}-1.aarch64.rpm"
)
for filename in "${expected_files[@]}"; do
  if [[ ! -f "$staging_dir/$filename" ]]; then
    echo "Missing expected RPM: $filename" >&2
    exit 1
  fi
done

mapfile -t secret_fingerprints < <(
  gpg --batch --with-colons --fingerprint --list-secret-keys \
    "$requested_fingerprint" |
    awk -F: '$1 == "sec" { primary = 1; next }
               primary && $1 == "fpr" { print toupper($10); primary = 0 }'
)
if (( ${#secret_fingerprints[@]} != 1 )); then
  echo "Signing fingerprint does not identify one primary secret key" >&2
  exit 1
fi
signing_fingerprint="${secret_fingerprints[0]}"
if [[ "${requested_fingerprint^^}" != "$signing_fingerprint" ]]; then
  echo "Signing key fingerprint did not match the requested key" >&2
  exit 1
fi

mkdir -p "$output_dir/repo/x86_64" "$output_dir/repo/aarch64"
touch "$output_dir/.nojekyll"
printf '%s\n' "$signing_fingerprint" > \
  "$output_dir/SIGNING-KEY-FINGERPRINT"
gpg --batch --armor --export "$signing_fingerprint" > \
  "$output_dir/qbz-rpm-key.gpg"

rpm_db="$(mktemp -d)"
cleanup() {
  rm -rf -- "$rpm_db"
}
trap cleanup EXIT
rpm --dbpath "$rpm_db" --initdb
rpmkeys --dbpath "$rpm_db" --import "$output_dir/qbz-rpm-key.gpg"

for package_name in qbz qbzd; do
  for arch in x86_64 aarch64; do
    if [[ "$package_name" == "qbz" ]]; then
      filename="QBZ-${version}-1.${arch}.rpm"
    else
      filename="qbzd-${version}-1.${arch}.rpm"
    fi

    source_rpm="$staging_dir/$filename"
    destination_rpm="$output_dir/repo/$arch/$filename"
    metadata="$(rpm -qp --queryformat \
      '%{NAME}|%{VERSION}|%{RELEASE}|%{ARCH}' "$source_rpm")"
    expected_metadata="${package_name}|${version}|1|${arch}"
    if [[ "$metadata" != "$expected_metadata" ]]; then
      echo "Unexpected metadata in $filename" >&2
      echo "Expected: $expected_metadata" >&2
      echo "Found:    $metadata" >&2
      exit 1
    fi

    install -m 0644 "$source_rpm" "$destination_rpm"
    rpmsign --define "_gpg_name $signing_fingerprint" \
      --define "__gpg $(command -v gpg)" \
      --resign "$destination_rpm"
    rpmkeys --dbpath "$rpm_db" --checksig "$destination_rpm"
  done
done

for arch in x86_64 aarch64; do
  arch_dir="$output_dir/repo/$arch"
  createrepo_c --database "$arch_dir"

  gpg --batch --yes --armor --local-user "$signing_fingerprint" \
    --detach-sign \
    --output "$arch_dir/repodata/repomd.xml.asc" \
    "$arch_dir/repodata/repomd.xml"
  gpg --batch --verify \
    "$arch_dir/repodata/repomd.xml.asc" \
    "$arch_dir/repodata/repomd.xml"

  (
    cd "$arch_dir"
    LC_ALL=C sha256sum ./*.rpm repodata/repomd.xml > SHA256SUMS
  )
  gpg --batch --yes --armor --local-user "$signing_fingerprint" \
    --detach-sign \
    --output "$arch_dir/SHA256SUMS.asc" \
    "$arch_dir/SHA256SUMS"
  gpg --batch --verify \
    "$arch_dir/SHA256SUMS.asc" \
    "$arch_dir/SHA256SUMS"
done

echo "Built signed QBZ RPM repository for $version"
