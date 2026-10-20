#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Deskside tokenomics monitoring (Prometheus + Grafana), shared by all recipes.
# Sourced by common.sh; also runnable:
#   recipes/lib/monitoring.sh up   <container> <port> [label]   # add/refresh target
#   recipes/lib/monitoring.sh down                               # remove both containers (keeps data volume)
#   recipes/lib/monitoring.sh status
# See monitoring/README.md for knobs and cost assumptions.
# ---------------------------------------------------------------------------
_DSM_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_DSM_ROOT="$(cd "${_DSM_LIB}/../.." && pwd)"
DS_MON_DIR="${DESKSIDE_MON_DIR:-$HOME/.deskside/monitoring}"
DS_MON_BIND="${DESKSIDE_MON_BIND:-127.0.0.1}"
DS_PROM_IMAGE="${DESKSIDE_PROM_IMAGE:-prom/prometheus:v2.53.1}"
DS_GRAFANA_IMAGE="${DESKSIDE_GRAFANA_IMAGE:-grafana/grafana:11.1.0}"
DS_PROM_NAME=deskside-prometheus
DS_GRAFANA_NAME=deskside-grafana
DS_PROM_URL=""; DS_GRAFANA_URL=""

_dsm_log() { echo "[deskside-monitoring] $*" >&2; }

_dsm_port_free() {  # 0 when nothing listens on $1
  ! (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null
}
_dsm_pick_port() {  # first free port >= $1
  local p="$1"; while ! _dsm_port_free "${p}"; do p=$((p + 1)); done; echo "${p}"
}
_dsm_container_port() {  # recorded port for an existing deskside container, else empty
  docker inspect -f '{{index .Config.Labels "deskside.port"}}' "$1" 2>/dev/null || true
}
_dsm_running() { [[ "$(docker inspect -f '{{.State.Running}}' "$1" 2>/dev/null)" == "true" ]]; }

_dsm_render() {  # copy config/dashboards into DS_MON_DIR with cost defaults substituted
  mkdir -p "${DS_MON_DIR}/targets" "${DS_MON_DIR}/grafana/provisioning/datasources" \
           "${DS_MON_DIR}/grafana/provisioning/dashboards" "${DS_MON_DIR}/grafana/dashboards"
  cp "${_DSM_ROOT}/monitoring/prometheus.yml" "${DS_MON_DIR}/prometheus.yml"
  cp "${_DSM_ROOT}/monitoring/alerts.yml" "${DS_MON_DIR}/alerts.yml"
  sed -e "s/__CLOUD_IN__/${DESKSIDE_CLOUD_IN_PER_M:-3.00}/g" \
      -e "s/__CLOUD_OUT__/${DESKSIDE_CLOUD_OUT_PER_M:-15.00}/g" \
      "${_DSM_ROOT}/monitoring/model-prices.yml" > "${DS_MON_DIR}/model-prices.yml"
  sed -e "s/__SYSTEM_PRICE__/${DESKSIDE_SYSTEM_PRICE:-20000}/g" \
      -e "s/__AMORT_MONTHS__/${DESKSIDE_AMORT_MONTHS:-24}/g" \
      -e "s/__WATTS__/${DESKSIDE_WATTS:-600}/g" \
      -e "s/__KWH__/${DESKSIDE_KWH_PRICE:-0.15}/g" \
      "${_DSM_ROOT}/monitoring/tokenomics.dashboard.template.json" > "${DS_MON_DIR}/grafana/dashboards/tokenomics.json"
  cat > "${DS_MON_DIR}/grafana/provisioning/dashboards/deskside.yml" <<'Y'
apiVersion: 1
providers:
  - name: deskside
    type: file
    allowUiUpdates: true
    options: {path: /var/lib/grafana/dashboards}
Y
  if [[ ! -s "${DS_MON_DIR}/grafana-admin-password" ]]; then
    ( umask 077; head -c 18 /dev/urandom | base64 | tr -d '/+=\n' > "${DS_MON_DIR}/grafana-admin-password" )
  fi
}

ds_monitoring_up() {
  local c="$1" port="$2" label="${3:-$1}" pport gport pass tmp
  command -v docker >/dev/null || { _dsm_log "docker not found"; return 1; }
  _dsm_render || return 1
  tmp="${DS_MON_DIR}/targets/.${c}.tmp"
  printf '[{"targets":["%s:%s"],"labels":{"instance_name":"%s","container":"%s"}}]\n' "${DESKSIDE_PROBE_HOST:-127.0.0.1}" "${port}" "${label}" "${c}" > "${tmp}"
  mv "${tmp}" "${DS_MON_DIR}/targets/${c}.json"

  pport="$(_dsm_container_port "${DS_PROM_NAME}")"
  if ! _dsm_running "${DS_PROM_NAME}"; then
    docker rm -f "${DS_PROM_NAME}" >/dev/null 2>&1 || true
    pport="${DESKSIDE_PROM_PORT:-$(_dsm_pick_port 9090)}"
    docker run -d --restart unless-stopped --name "${DS_PROM_NAME}" --network host \
      --label "deskside.port=${pport}" \
      -v "${DS_MON_DIR}/prometheus.yml:/etc/prometheus/prometheus.yml:ro" \
      -v "${DS_MON_DIR}/alerts.yml:/etc/prometheus/alerts.yml:ro" \
      -v "${DS_MON_DIR}/model-prices.yml:/etc/prometheus/model-prices.yml:ro" \
      -v "${DS_MON_DIR}/targets:/etc/prometheus/targets:ro" \
      -v deskside-prometheus-data:/prometheus \
      "${DS_PROM_IMAGE}" \
      --config.file=/etc/prometheus/prometheus.yml \
      --web.listen-address="${DS_MON_BIND}:${pport}" \
      --storage.tsdb.retention.time="${DESKSIDE_PROM_RETENTION:-30d}" >/dev/null || return 1
  fi
  DS_PROM_URL="http://${DS_MON_BIND}:${pport}"

  gport="$(_dsm_container_port "${DS_GRAFANA_NAME}")"
  if ! _dsm_running "${DS_GRAFANA_NAME}"; then
    docker rm -f "${DS_GRAFANA_NAME}" >/dev/null 2>&1 || true
    gport="${DESKSIDE_GRAFANA_PORT:-$(_dsm_pick_port 3000)}"
    cat > "${DS_MON_DIR}/grafana/provisioning/datasources/prometheus.yml" <<Y
apiVersion: 1
datasources:
  - name: deskside-prometheus
    uid: deskside-prom
    type: prometheus
    access: proxy
    url: http://127.0.0.1:${pport}
    isDefault: true
Y
    pass="$(cat "${DS_MON_DIR}/grafana-admin-password")"
    docker run -d --restart unless-stopped --name "${DS_GRAFANA_NAME}" --network host \
      --label "deskside.port=${gport}" \
      -e GF_SERVER_HTTP_ADDR="${DS_MON_BIND}" -e GF_SERVER_HTTP_PORT="${gport}" \
      -e GF_SECURITY_ADMIN_PASSWORD="${pass}" -e GF_USERS_DEFAULT_THEME=light \
      -e GF_ANALYTICS_REPORTING_ENABLED=false -e GF_ANALYTICS_CHECK_FOR_UPDATES=false \
      -e GF_DASHBOARDS_DEFAULT_HOME_DASHBOARD_PATH=/var/lib/grafana/dashboards/tokenomics.json \
      -v "${DS_MON_DIR}/grafana/provisioning:/etc/grafana/provisioning:ro" \
      -v "${DS_MON_DIR}/grafana/dashboards:/var/lib/grafana/dashboards" \
      -v deskside-grafana-data:/var/lib/grafana \
      "${DS_GRAFANA_IMAGE}" >/dev/null || return 1
  fi
  DS_GRAFANA_URL="http://${DS_MON_BIND}:${gport}/d/deskside-tokenomics"
  _dsm_log "prometheus ${DS_PROM_URL}  grafana ${DS_GRAFANA_URL}"
  return 0
}

ds_monitoring_down() {
  docker rm -f "${DS_GRAFANA_NAME}" "${DS_PROM_NAME}" >/dev/null 2>&1 || true
  _dsm_log "removed containers (volumes deskside-*-data and ${DS_MON_DIR} kept)"
}

ds_monitoring_status() {
  local n p
  for n in "${DS_PROM_NAME}" "${DS_GRAFANA_NAME}"; do
    if _dsm_running "${n}"; then
      p="$(_dsm_container_port "${n}")"; echo "${n}: running on ${DS_MON_BIND}:${p}"
    else echo "${n}: not running"; fi
  done
  ls "${DS_MON_DIR}/targets" 2>/dev/null | sed 's/^/target: /'
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  set -euo pipefail
  case "${1:-}" in
    up) shift; ds_monitoring_up "${1:?container}" "${2:?port}" "${3:-}" ;;
    down) ds_monitoring_down ;;
    status) ds_monitoring_status ;;
    *) echo "usage: $0 up <container> <port> [label] | down | status"; exit 2 ;;
  esac
fi
