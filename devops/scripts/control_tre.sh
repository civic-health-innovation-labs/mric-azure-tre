#!/bin/bash
set -o errexit
set -o pipefail
set -o nounset
# set -o xtrace

if [[ -z ${TRE_ID:-} ]]; then
    echo "TRE_ID environment variable must be set."
    exit 1
fi

core_rg_name="rg-${TRE_ID}"
fw_name="fw-${TRE_ID}"
agw_name="agw-$TRE_ID"
fw_pip_name="pip-${fw_name}"
vnet_name="vnet-${TRE_ID}"

# if the resource group doesn't exist, no need to continue this script.
# most likely this is an automated execution before calling make tre-deploy.
if [[ $(az group list --output json --query "[?name=='${core_rg_name}'] | length(@)") == 0 ]]; then
  echo "TRE resource group doesn't exist. Exiting..."
  exit 0
fi

az config set extension.use_dynamic_install=yes_without_prompt
az --version

if [[ "$1" == *"start"* ]]; then
  if [[ $(az network firewall list --output json --query "[?resourceGroup=='${core_rg_name}'&&name=='${fw_name}'] | length(@)") != 0 ]]; then
    CURRENT_PUBLIC_IP=$(az network firewall ip-config list -f "${fw_name}" -g "${core_rg_name}" --query "[0].publicIpAddress" -o tsv)
    if [ -z "$CURRENT_PUBLIC_IP" ]; then
      FW_SKU_TIER=$(az network firewall show --n "${fw_name}" -g "${core_rg_name}" --query "sku.tier" -o tsv)
      if [ "$FW_SKU_TIER" == "Basic" ]; then
        echo "Starting Firewall (Basic SKU) - creating ip-config and management-ip-config"
        az network firewall ip-config create -f "${fw_name}" -g "${core_rg_name}" -n "fw-ip-configuration" --public-ip-address "${fw_pip_name}" --vnet-name "${vnet_name}" --m-name "fw-management-ip-configuration" --m-public-ip-address "pip-fw-management-$TRE_ID" --m-vnet-name "${vnet_name}"> /dev/null 
      else
        echo "Starting Firewall - creating ip-config"
        az network firewall ip-config create -f "${fw_name}" -g "${core_rg_name}" -n "fw-ip-configuration" --public-ip-address "${fw_pip_name}" --vnet-name "${vnet_name}" > /dev/null 
      fi
    else
      echo "Firewall ip-config already exists"
    fi
  fi

  for gateway_name in "agw-${TRE_ID}" "agw-certs-${TRE_ID}"; do
    gateway_state=$(az network application-gateway show \
      --resource-group "${core_rg_name}" \
      --name "${gateway_name}" \
      --query operationalState \
      --output tsv)

    if [[ "${gateway_state}" == "Stopped" ]]; then
      echo "Starting Application Gateway ${gateway_name}"
      az network application-gateway start \
        --resource-group "${core_rg_name}" \
        --name "${gateway_name}"
    fi
  done

  az mysql server list --resource-group "${core_rg_name}" --query "[?userVisibleState=='Stopped'].name" -o tsv |
  while read -r mysql_name; do
    echo "Starting MySQL ${mysql_name}"
    az mysql server start --resource-group "${core_rg_name}" --name "${mysql_name}" 
  done

  az vmss list --resource-group "${core_rg_name}" --query "[].name" -o tsv |
  while read -r vmss_name; do
    matching_instances=$(az vmss list-instances \
      --resource-group "${core_rg_name}" \
      --name "${vmss_name}" \
      --expand instanceView \
      --output json |
      jq '[.[] | .instanceView.statuses[]? |
        select(.code=="PowerState/deallocated" or
               .code=="PowerState/stopped")] | length')

    if [[ "${matching_instances}" -gt 0 ]]; then
      echo "Starting VMSS ${vmss_name}"
      az vmss start \
        --resource-group "${core_rg_name}" \
        --name "${vmss_name}"
    fi
  done

  az vm list -d --resource-group "${core_rg_name}" --query "[?powerState=='VM deallocated' || powerState=='VM stopped'].name" -o tsv |
  while read -r vm_name; do
    echo "Starting VM ${vm_name}"
    az vm start --resource-group "${core_rg_name}" --name "${vm_name}" 
  done

  # We don't start workspace VMs despite maybe stopping them because we don't know if they need to be on.

elif [[ "$1" == *"stop"* ]]; then
  if [[ $(az network firewall list --output json --query "[?resourceGroup=='${core_rg_name}'&&name=='${fw_name}'] | length(@)") != 0 ]]; then
    IPCONFIG_NAME=$(az network firewall ip-config list -f "${fw_name}" -g "${core_rg_name}" --query "[0].name" -o tsv)

    if [ -n "$IPCONFIG_NAME" ]; then
      echo "Deleting Firewall ip-config"
      az network firewall update --name "${fw_name}" --resource-group "${core_rg_name}" --remove ipConfigurations --remove managementIpConfiguration 
    else
      echo "No Firewall ip-config found"
    fi
  fi

  for gateway_name in "agw-${TRE_ID}" "agw-certs-${TRE_ID}"; do
    gateway_state=$(az network application-gateway show \
      --resource-group "${core_rg_name}" \
      --name "${gateway_name}" \
      --query operationalState \
      --output tsv)

    if [[ "${gateway_state}" == "Running" ]]; then
      echo "Stopping Application Gateway ${gateway_name}"
      az network application-gateway stop \
        --resource-group "${core_rg_name}" \
        --name "${gateway_name}"
    fi
  done

  az mysql server list --resource-group "${core_rg_name}" --query "[?userVisibleState=='Ready'].name" -o tsv |
  while read -r mysql_name; do
    echo "Stopping MySQL ${mysql_name}"
    az mysql server stop --resource-group "${core_rg_name}" --name "${mysql_name}" 
  done

  az vmss list --resource-group "${core_rg_name}" --query "[].name" -o tsv |
  while read -r vmss_name; do
    matching_instances=$(az vmss list-instances \
      --resource-group "${core_rg_name}" \
      --name "${vmss_name}" \
      --expand instanceView \
      --output json |
      jq '[.[] | .instanceView.statuses[]? |
        select(.code=="PowerState/running" or
               .code=="PowerState/stopped")] | length')

    if [[ "${matching_instances}" -gt 0 ]]; then
      echo "Deallocating VMSS ${vmss_name}"
      az vmss deallocate \
        --resource-group "${core_rg_name}" \
        --name "${vmss_name}"
    fi
  done

  az vm list -d --resource-group "${core_rg_name}" --query "[?powerState=='VM running' || powerState=='VM stopped'].name" -o tsv |
  while read -r vm_name; do
    echo "Deallocating VM ${vm_name}"
    az vm deallocate --resource-group "${core_rg_name}" --name "${vm_name}" 
  done

  # deallocating all VMs in workspaces
  # RG is in uppercase here (which is odd). Checking both cases for future compatability.
  az vm list -d --query "[?(starts_with(resourceGroup,'${core_rg_name}-ws-') || starts_with(resourceGroup,'${core_rg_name^^}-WS-')) && (powerState=='VM running' || powerState=='VM stopped')][name, resourceGroup]" -o tsv |
  while read -r vm_name rg_name; do
    echo "Deallocating VM ${vm_name} in ${rg_name}"
    az vm deallocate --resource-group "${rg_name}" --name "${vm_name}" 
  done
fi


# Report final FW status
FW_STATE="Stopped"
if [[ $(az network firewall list --output json --query "[?resourceGroup=='${core_rg_name}'&&name=='${fw_name}'] | length(@)") != 0 ]]; then
  PUBLIC_IP=$(az network firewall ip-config list -f "${fw_name}" -g "${core_rg_name}" --query "[0].publicIpAddress" -o tsv)
  if [ -n "$PUBLIC_IP" ]; then
    FW_STATE="Running"
  fi
fi

# Report final AGW status
# Verify final states. These commands only read Azure resource status.
case "${1:-}" in
  start)
    expected_gateway="Running"
    expected_vm="PowerState/running"
    ;;
  stop)
    expected_gateway="Stopped"
    expected_vm="PowerState/deallocated"
    ;;
  *)
    echo "ERROR: Expected start or stop." >&2
    exit 1
    ;;
esac

verification_failed=0

# Verify both Application Gateways.
for gateway_name in "agw-${TRE_ID}" "agw-certs-${TRE_ID}"; do
  gateway_state=$(az network application-gateway show \
    --resource-group "${core_rg_name}" \
    --name "${gateway_name}" \
    --query operationalState \
    --output tsv)

  echo "${gateway_name}: ${gateway_state}"

  if [[ "${gateway_state}" != "${expected_gateway}" ]]; then
    echo "ERROR: Expected ${expected_gateway}." >&2
    verification_failed=1
  fi
done

# Verify firewall provisioning and IP configuration.
firewall_json=$(az network firewall show \
  --resource-group "${core_rg_name}" \
  --name "${fw_name}" \
  --output json)

firewall_provisioning=$(jq -r '.provisioningState' <<< "${firewall_json}")

if [[ "${firewall_provisioning}" != "Succeeded" ]]; then
  echo "ERROR: Firewall provisioning state: ${firewall_provisioning}" >&2
  verification_failed=1
fi

if [[ "$1" == "start" ]]; then
  public_ip_count=$(jq '
    [.ipConfigurations[]?
     | select((.publicIPAddress.id // "") != "")]
    | length
  ' <<< "${firewall_json}")

  if [[ "${public_ip_count}" -eq 0 ]]; then
    echo "ERROR: Firewall has no public IP configuration." >&2
    verification_failed=1
  else
    echo "${fw_name}: public IP configuration present"
  fi
else
  ipconfig_count=$(jq '
    (.ipConfigurations // []) | length
  ' <<< "${firewall_json}")

  if [[ "${ipconfig_count}" -ne 0 ]]; then
    echo "ERROR: Firewall still has IP configurations." >&2
    verification_failed=1
  else
    echo "${fw_name}: IP configurations removed"
  fi
fi

# Verify every instance in each core VM scale set.
vmss_names=$(az vmss list \
  --resource-group "${core_rg_name}" \
  --query "[].name" \
  --output tsv)

while IFS= read -r vmss_name; do
  [[ -n "${vmss_name}" ]] || continue

  instances_json=$(az vmss list-instances \
    --resource-group "${core_rg_name}" \
    --name "${vmss_name}" \
    --expand instanceView \
    --output json)

  mismatch_count=$(jq --arg expected "${expected_vm}" '
    [.[] | select(
      ([.instanceView.statuses[]?
        | select(.code == $expected)] | length) == 0
    )] | length
  ' <<< "${instances_json}")

  echo "${vmss_name}: ${mismatch_count} instances outside expected state"

  if [[ "${mismatch_count}" -ne 0 ]]; then
    verification_failed=1
  fi
done <<< "${vmss_names}"

# Verify core VMs and, when stopping, this TRE's workspace VMs.
all_vms_json=$(az vm list --output json)

target_vms=$(jq -r \
  --arg core "${core_rg_name,,}" \
  --arg action "$1" '
    .[]
    | (.resourceGroup | ascii_downcase) as $rg
    | select(
        ($rg == $core) or
        ($action == "stop" and ($rg | startswith($core + "-ws-")))
      )
    | [.name, .resourceGroup]
    | @tsv
  ' <<< "${all_vms_json}")

while IFS=$'\t' read -r vm_name resource_group; do
  [[ -n "${vm_name}" ]] || continue

  vm_state=$(az vm get-instance-view \
    --resource-group "${resource_group}" \
    --name "${vm_name}" \
    --query "instanceView.statuses[?starts_with(code, 'PowerState/')].code | [0]" \
    --output tsv)

  echo "${vm_name}: ${vm_state}"

  if [[ "${vm_state}" != "${expected_vm}" ]]; then
    echo "ERROR: Expected ${expected_vm}." >&2
    verification_failed=1
  fi
done <<< "${target_vms}"

if [[ "${verification_failed}" -ne 0 ]]; then
  echo "ERROR: Some resources have not reached the expected state." >&2
  echo "Review the messages above before retrying."
  exit 1
fi

echo "Verified TRE $1: firewall, both gateways and targeted compute."
echo "Other retained services can still incur charges."
