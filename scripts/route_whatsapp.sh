#!/usr/bin/env bash
# Points the WhatsApp_BYOC messaging channel at the LoanSeva Omni-Flow (Messaging Settings > Routing Type = Omni-Flow).
# Omni-Flow routing = MessagingChannel.SessionHandlerId holding the flow definition id. Idempotent.
# Rollback: ./scripts/route_whatsapp.sh --queue  (routes straight to the SDO_Service_Messaging queue again)
set -euo pipefail
ORG=${ORG:-kotak-demo}
q() { sf data query -o "$ORG" -q "$1" --json | python3 -c "import json,sys; r=json.load(sys.stdin)['result']['records']; print(r[0]['Id'] if r else '')"; }
CHANNEL=$(q "SELECT Id FROM MessagingChannel WHERE DeveloperName='WhatsApp_BYOC'")
QUEUE=$(q "SELECT Id FROM Group WHERE Type='Queue' AND DeveloperName='SDO_Service_Messaging'")
if [[ "${1:-}" == "--queue" ]]; then
  sf data update record -s MessagingChannel -i "$CHANNEL" -v "SessionHandlerId=$QUEUE FallbackQueueId=''" -o "$ORG"
  exit 0
fi
FLOW=$(sf data query -o "$ORG" -q "SELECT DurableId FROM FlowDefinitionView WHERE ApiName='LoanSeva_WhatsApp_Inbound_Routing'" --json | python3 -c "import json,sys; print(json.load(sys.stdin)['result']['records'][0]['DurableId'])")
sf data update record -s MessagingChannel -i "$CHANNEL" -v "SessionHandlerId=$FLOW FallbackQueueId=$QUEUE" -o "$ORG"
