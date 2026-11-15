# Native dependency source delivery — design only

This plan applies to a future explicitly selected native release artifact, not the currently published proxy application. No distribution is authorized by this document or by a successful research inventory.

## Build-bound materials

- Select exact linked artifacts, including their platform, source commit, patches, toolchain and SHA-256. Generate the final linked dependency inventory from that build, not from the union of research candidates.
- Keep original notices with attribution and version, with a manifest linking each entry to the actual component. Keep the existing pinned research inventory immutable; resolve additional obligations in a new build-specific package.
- Prepare corresponding source for covered components, including local modifications, pinned module archives and necessary build instructions. Three verified MPL module archives already exist for the local Xray candidate. Legal review must determine the complete source scope, notices and the actual delivery method; the archives are not evidence that a distribution obligation has been fulfilled.
- Keep documents and corresponding-source downloads separated from credentials, private build logs, signing/provisioning material and owner data. Build in an allowlisted isolated staging directory; reject symlinks, absolute or traversing paths, unexpected entries and digest mismatches. No automatic upload from research scripts.

## Proposed distribution path (subject to approval)

Use a versioned third-party notices section in the application and a stable public support-page link to the versioned release materials, with archive SHA-256 and reproducibility instructions. The exact product URL and hosting retention policy are undecided. Review accessibility, offline notices, applicable license terms, App Store disclosures and availability of corresponding source before using that path. Do not publish internal filesystem paths or claim the linked upstream binary is identical to the source-built candidate.

## Blocking gaps

The original MIT notice for tproxy-config 7.0.9 has not been located. The locked crate metadata declares MIT; this does not establish its exact copyright attribution. Do not fabricate a generic notice. Keep this item open for upstream evidence or a separately reviewed dependency decision. The original WTFPL header for tun is preserved. Complete final linked closure, source/notice obligations, exact artifact comparison and approval remain open. Existing physical20 receipts do not authorize a different independently built binary.

## Release decision

Produce a new manifest for the final artifact only after scope approval. Independent review checks artifact identity, notice/source completeness, public access (only after approved publication), and the final signed candidate. Research audit continues to return release_authorized=false; no automated promotion, signing or submission.
