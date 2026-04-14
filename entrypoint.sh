#!/bin/bash
set -euo pipefail

readonly FLUXZY_USER="fluxzy"
readonly FLUXZY_HOME_DIR="/var/lib/fluxzy"
readonly FLUXZY_HTTPS_PORT="18443"
readonly FLUXZY_CERT_PFX="${FLUXZY_HOME_DIR}/fluxzy-root.pfx"
readonly FLUXZY_CERT_PEM="${FLUXZY_HOME_DIR}/fluxzy-root.pem"
readonly FLUXZY_DUMP_DIR="/dump"

cleanup() {
  set +e

  iptables -t nat -D OUTPUT -j FLUXZY_REDIRECT_OUTPUT 2>/dev/null || true
  iptables -t nat -F FLUXZY_REDIRECT_OUTPUT 2>/dev/null || true
  iptables -t nat -X FLUXZY_REDIRECT_OUTPUT 2>/dev/null || true

  if [[ -n "${FLUXZY_PID:-}" ]]; then
    kill "${FLUXZY_PID}" 2>/dev/null || true
    wait "${FLUXZY_PID}" 2>/dev/null || true
  fi
}

trap cleanup EXIT

run_as_fluxzy() {
  runuser -u "${FLUXZY_USER}" -- env \
    HOME="${FLUXZY_HOME_DIR}" \
    XDG_CONFIG_HOME="${FLUXZY_HOME_DIR}/.config" \
    XDG_DATA_HOME="${FLUXZY_HOME_DIR}/.local/share" \
    "$@"
}

initialize_fluxzy_certificate() {
  install -d -o "${FLUXZY_USER}" -g "${FLUXZY_USER}" -m 755 \
    "${FLUXZY_HOME_DIR}/.fluxzy" \
    "${FLUXZY_HOME_DIR}/.config" \
    "${FLUXZY_HOME_DIR}/.local/share"

  if [[ ! -f "${FLUXZY_CERT_PFX}" ]]; then
    run_as_fluxzy fluxzy cert create "${FLUXZY_CERT_PFX}" "Fluxzy Root CA"
  fi

  run_as_fluxzy fluxzy cert default "${FLUXZY_CERT_PFX}"

  openssl pkcs12 -in "${FLUXZY_CERT_PFX}" -nokeys -passin pass: -out "${FLUXZY_CERT_PEM}.tmp"
  mv "${FLUXZY_CERT_PEM}.tmp" "${FLUXZY_CERT_PEM}"
  chmod 644 "${FLUXZY_CERT_PEM}"

  export AWS_CA_BUNDLE="${FLUXZY_CERT_PEM}"
}

start_fluxzy() {
  install -d -m 755 "${FLUXZY_DUMP_DIR}"

  run_as_fluxzy fluxzy start \
    --mode ReverseSecure \
    --mode-reverse-port 443 \
    -d "${FLUXZY_DUMP_DIR}" \
    -l "127.0.0.1:${FLUXZY_HTTPS_PORT}" \
    > /dev/null 2>&1 &

  FLUXZY_PID=$!
}

wait_for_fluxzy() {
  local attempt=1

  while (( attempt <= 30 )); do
    if ss -ltnH "( sport = :${FLUXZY_HTTPS_PORT} )" | grep -Fq ":${FLUXZY_HTTPS_PORT}"; then
      return 0
    fi

    sleep 1
    (( attempt += 1 ))
  done

  echo "Fluxzy did not start listening on ${FLUXZY_HTTPS_PORT}" >&2
  return 1
}

configure_redirect() {
  local fluxzy_uid
  fluxzy_uid="$(id -u "${FLUXZY_USER}")"

  iptables -t nat -N FLUXZY_REDIRECT_OUTPUT 2>/dev/null || true
  iptables -t nat -F FLUXZY_REDIRECT_OUTPUT
  iptables -t nat -C OUTPUT -j FLUXZY_REDIRECT_OUTPUT 2>/dev/null || iptables -t nat -A OUTPUT -j FLUXZY_REDIRECT_OUTPUT

  iptables -t nat -A FLUXZY_REDIRECT_OUTPUT -o lo -j RETURN
  iptables -t nat -A FLUXZY_REDIRECT_OUTPUT -m owner --uid-owner "${fluxzy_uid}" -j RETURN
  iptables -t nat -A FLUXZY_REDIRECT_OUTPUT -d 169.254.169.254/32 -j RETURN
  iptables -t nat -A FLUXZY_REDIRECT_OUTPUT -p tcp --dport 443 -j REDIRECT --to-ports "${FLUXZY_HTTPS_PORT}"
}

create_test_file() {
  head -c 80388 < /dev/zero | tr '\0' 'x' > /tmp/payload.txt
}

run_default_repro() {
  if [[ -z "${S3_URI:-}" ]]; then
    echo "S3_URI is required to run the default upload." >&2
    return 1
  fi

  create_test_file

  echo "AWS_CA_BUNDLE=${AWS_CA_BUNDLE}"
  if [[ ! -f /tmp/payload.txt ]]; then
    echo "Test file was not created: /tmp/payload.txt" >&2
    return 1
  fi
  ls -lh /tmp/payload.txt
  echo "Uploading /tmp/payload.txt to ${S3_URI}"
  time aws --debug s3 cp /tmp/payload.txt "${S3_URI}"
}

main() {
  initialize_fluxzy_certificate
  start_fluxzy
  wait_for_fluxzy
  configure_redirect
  run_default_repro
}

main "$@"
