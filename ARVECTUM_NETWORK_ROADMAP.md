# Arvectum Network roadmap

Updated: 2026-09-27

## MVP infrastructure
- [x] Corporate Timeweb Cloud account for ООО Арвектум created.
- [ ] Confirm hosting terms for the planned commercial service.
- [ ] Buy/provision `apl-control-ru-01` in Moscow; initial target 2 vCPU / 4 GB / 50 GB.
- [ ] Buy/provision the first foreign pilot node `apl-de-01` in Frankfurt.
- [ ] Do not buy additional countries or dedicated infrastructure until the pilot is validated.

## Personal data and Russian control plane
- [ ] Obtain exact Moscow hosting/database location details needed for company compliance records.
- [ ] Review the existing Arvectum.com personal-data policy against the actual production architecture.
- [ ] Appoint the person responsible for personal-data processing.
- [ ] Prepare and submit the required Roskomnadzor operator notification.
- [ ] Verify the company entry in the operator register.
- [ ] Keep the primary production customer database on Russian infrastructure, not the home Mac mini.

## Database
- [ ] Self-host PostgreSQL on `apl-control-ru-01` for MVP.
- [x] Managed PostgreSQL is deferred at MVP stage.
- [ ] Encrypt persistent database storage.
- [ ] Configure automatic daily backups.
- [ ] Keep encrypted off-host backups in Russia.
- [ ] Test database restore before production launch.
- [ ] Reconsider Managed PostgreSQL only when scale or availability requirements justify it.

## Control plane
- [ ] Harden the Moscow server, SSH and firewall.
- [ ] Deploy APL backend/control API.
- [ ] Add monitoring, logging and alerts.
- [ ] Store accounts, devices, subscriptions/orders, payment metadata, node assignments and audit data in the Russian database.

## First exit-node pilot
- [ ] Deploy the first Germany node in Frankfurt.
- [ ] Configure the selected secure transport stack.
- [ ] Implement per-user/device technical credentials.
- [ ] Implement node health and capacity telemetry.
- [ ] Minimize personal data on foreign nodes; use technical identifiers where possible.
- [ ] Validate the complete APL -> Germany -> Internet path.

## End-to-end MVP gate
- [ ] Backend can provision and revoke access.
- [ ] APL receives connection configuration automatically.
- [ ] User can select a location and connect without handling low-level credentials manually.
- [ ] Validate accounting/traffic approach.
- [ ] Test failure and recovery.
- [ ] Run load tests to establish realistic capacity per VPS.
- [ ] Pass security review and backup restore drill.

## Billing and commercial pilot
- [ ] Add orders/subscriptions only after legal and technical gates.
- [ ] Add channel-appropriate payment adapters.
- [ ] Implement entitlement, expiry, renewal and revocation.
- [ ] Add abuse/support workflow.
- [ ] Run a small controlled pilot before public scaling.

## Expansion after successful Germany pilot
- [ ] Add Netherlands.
- [ ] Add Kazakhstan.
- [ ] Add Finland or a second infrastructure provider where justified.
- [ ] Add capacity-aware resource routing.
- [ ] Automate node creation through provider APIs/infrastructure-as-code.

## Deferred marketplace layer
Only after Arvectum Network is operational:
- [ ] Third-party datacenter proxy adapters.
- [ ] ISP/residential/mobile supplier adapters.
- [ ] Traffic-priced products.
- [ ] Own dedicated servers/IP ranges when economics justify them.

## Fixed decisions
- VPS-first infrastructure is the MVP; third-party proxy suppliers are deferred.
- Russian control plane and primary personal-data database remain in Russia.
- PostgreSQL is self-hosted on the Moscow VPS for MVP.
- Managed PostgreSQL is deferred.
- Mac mini remains development/build/admin infrastructure, not the production customer-data database.
- Start with Moscow control + one Frankfurt pilot node and scale only after E2E/load validation.
- Paid infrastructure purchase, production mutation, Roskomnadzor submission and billing activation are HUMAN/Owner gates.
