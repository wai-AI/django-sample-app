#!/usr/bin/env bash
set -euo pipefail

: "${SSM_REGION:?Missing region}"
: "${SSM_IDS:?Missing instance IDs}"
: "${SSM_COUNT:?Missing instance count}"
export AWS_PAGER=""

for attempt in $(seq 1 90); do
  online=$(aws ssm describe-instance-information \
    --region "$SSM_REGION" \
    --filters "Key=InstanceIds,Values=$SSM_IDS" \
    --query "length(InstanceInformationList[?PingStatus=='Online'])" \
    --output text)
  if [ "$online" = "$SSM_COUNT" ]; then
    echo "All $SSM_COUNT instances are Online in SSM."
    exit 0
  fi
  echo "Waiting for SSM: $online/$SSM_COUNT Online ($attempt/90)."
  sleep 10
done

echo "SSM registration timed out. Check NAT routes, agent and instance IAM role." >&2
exit 1
