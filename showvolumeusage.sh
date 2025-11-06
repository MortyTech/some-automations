#!/bin/bash

# === Longhorn Volume Usage Reporter v4 ===
# Live monitoring of Longhorn Volume usage with color output (without clearing the screen)

WATCH_INTERVAL=0
NAMESPACE=""

# Colors
RED="\e[31m"
YELLOW="\e[33m"
GREEN="\e[32m"
CYAN="\e[36m"
RESET="\e[0m"
BOLD="\e[1m"

# Parse input arguments
while getopts ":n:w:" opt; do
  case $opt in
    n)
      NAMESPACE=$OPTARG
      ;;
    w)
      WATCH_INTERVAL=$OPTARG
      ;;
    \?)
      echo "❌ Invalid option: -$OPTARG" >&2
      exit 1
      ;;
    :)
      echo "❌ Option -$OPTARG requires a value" >&2
      exit 1
      ;;
  esac
done

# Print report function
print_report() {
  timestamp=$(date +"%Y-%m-%d %H:%M:%S")
  echo -e "\n🕒 [$timestamp] Longhorn Volume Usage Report ${NAMESPACE:+for namespace: $CYAN$NAMESPACE$RESET}\n"
  printf "%-60s %-10s %-10s %-10s %-15s %-20s %-20s\n" "VOLUME" "SIZE" "USED" "USAGE%" "NODE" "NAMESPACE" "POD"
  echo "------------------------------------------------------------------------------------------------------------------------------------------------------"

  kubectl -n longhorn-system get volumes.longhorn.io -o json | \
  jq -r '.items[] | [.metadata.name, .spec.size, .status.actualSize, .status.ownerID] | @tsv' | \
  while IFS=$'\t' read -r volname size actual node; do
    pvc_info=$(kubectl get pvc --all-namespaces -o json | jq -r --arg vol "$volname" '.items[] | select(.spec.volumeName == $vol) | [.metadata.name, .metadata.namespace] | @tsv')
    pvc_name=$(echo "$pvc_info" | cut -f1)
    ns_name=$(echo "$pvc_info" | cut -f2)
    [[ -n "$NAMESPACE" && "$ns_name" != "$NAMESPACE" ]] && continue

    pod_name=$(kubectl -n "$ns_name" get pods -o json 2>/dev/null | jq -r --arg pvc "$pvc_name" '.items[] | select(.spec.volumes[].persistentVolumeClaim.claimName == $pvc) | .metadata.name' | head -n1)
    
    # Convert numeric values
    size_h=$(numfmt --to=iec --suffix=B $size 2>/dev/null)
    used_h=$(numfmt --to=iec --suffix=B $actual 2>/dev/null)

    # Calculate usage percentage
    if [[ "$size" -gt 0 ]]; then
      usage_pct=$((100 * actual / size))
    else
      usage_pct=0
    fi

    # Colorize based on usage
    if (( usage_pct >= 90 )); then
      color=$RED
    elif (( usage_pct >= 70 )); then
      color=$YELLOW
    else
      color=$GREEN
    fi

    printf "%-60s %-10s %-10s ${color}%-10s${RESET} %-15s %-20s %-20s\n" \
      "$volname" "$size_h" "$used_h" "${usage_pct}%" "$node" "${ns_name:-N/A}" "${pod_name:-N/A}"
  done
}

# Live mode
if (( WATCH_INTERVAL > 0 )); then
  while true; do
    print_report
    echo -e "⏱️  Next update in $WATCH_INTERVAL seconds..."
    sleep "$WATCH_INTERVAL"
  done
else
  print_report
fi
