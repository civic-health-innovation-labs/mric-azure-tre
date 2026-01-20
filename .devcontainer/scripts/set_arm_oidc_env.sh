#!/usr/bin/env bash
set -euo pipefail

# Configure Azure ARM OIDC environment variables and mirrors for AZURE_*
# Usage: source set_arm_oidc_env.sh <ARM_CLIENT_ID>

ARM_USE_OIDC=true
ARM_TENANT_ID="fcf34a50-eb04-4b34-8021-2a082db131a7"
ARM_SUBSCRIPTION_ID="92397f1e-d02e-4cb4-bd67-47f4045e553f"
ARM_CLIENT_ID="${1:?ARM_CLIENT_ID is required. Usage: source set_arm_oidc_env.sh <ARM_CLIENT_ID>}"

export ARM_USE_OIDC ARM_TENANT_ID ARM_SUBSCRIPTION_ID ARM_CLIENT_ID

export AZURE_TENANT_ID="$ARM_TENANT_ID"
export AZURE_SUBSCRIPTION_ID="$ARM_SUBSCRIPTION_ID"
export AZURE_CLIENT_ID="$ARM_CLIENT_ID"

printf "Configured OIDC envs:\n"
printf "  ARM_USE_OIDC=%s\n" "$ARM_USE_OIDC"
printf "  ARM_TENANT_ID=%s\n" "$ARM_TENANT_ID"
printf "  ARM_SUBSCRIPTION_ID=%s\n" "$ARM_SUBSCRIPTION_ID"
printf "  ARM_CLIENT_ID=%s\n" "$ARM_CLIENT_ID"
printf "  AZURE_TENANT_ID=%s\n" "$AZURE_TENANT_ID"
printf "  AZURE_SUBSCRIPTION_ID=%s\n" "$AZURE_SUBSCRIPTION_ID"
printf "  AZURE_CLIENT_ID=%s\n" "$AZURE_CLIENT_ID"
