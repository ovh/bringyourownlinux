#!/bin/bash

set -euxo pipefail

OVH_APP_KEY=""
OVH_APP_SECRET=""
OVH_CONSUMER_KEY=""

postdata=$(jq -M -c . "${1}")
method="POST"
timestamp="$(date +%s)"
api_url="https://api.ovh.com/1.0"

service_url="/dedicated/server/{myServer}/install/start"

# shellcheck disable=SC2016,SC2046
curl -s -w "\n%{http_code}\n" -X $method \
    --header 'Content-Type:application/json;charset=utf-8' \
    --header "X-Ovh-Application:$OVH_APP_KEY" \
    --header "X-Ovh-Timestamp:$timestamp" \
    --header "X-Ovh-Signature:"'$1$'$(echo -n "$OVH_APP_SECRET+$OVH_CONSUMER_KEY+${method}+${api_url}${service_url}+${postdata}+$timestamp" | sha1sum - | cut -d' ' -f1) \
    --header "X-Ovh-Consumer:$OVH_CONSUMER_KEY" \
    --data "$postdata" ${api_url}${service_url}
