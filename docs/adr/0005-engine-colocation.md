# ADR 0005: iii Engine Placement - Co-located with Gateway VM

**Status:** Accepted

## Context
The iii engine is the WebSocket coordinator that workers connect to. Placement options:
- A: Own VM (3 VMs total)
- B: Co-located with gateway/caller-worker VM
- C: Co-located with inference VM

## Decision
Option B: engine + caller-worker run on the gateway VM together.

## Consequences
**Positive:**
- Saves one VM ($13-$50/mo)
- Eliminates one network hop (caller → engine is loopback `127.0.0.1:49134` instead of a VPC hop)
- The engine WebSocket port (49134) is only reachable from the private subnet - firewall scoped to `10.10.2.0/24`
- Inference worker connects outbound to `<gateway-internal-ip>:49134` - a single stable internal IP

**Negative:**
- If gateway VM is rebooted, both the engine and HTTP gateway restart simultaneously (~5s outage)
- Gateway VM needs slightly more RAM (engine + caller-worker together vs just caller)

**vs Option A (own VM):** The engine is a lightweight coordinator, not a compute-heavy service. A dedicated VM for it provides no reliability advantage at this scale - a 3-VM failure mode analysis is the same as 2-VM since the engine is always a dependency of the caller anyway.
