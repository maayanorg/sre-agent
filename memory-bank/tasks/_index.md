# Tasks Index

## In Progress
- [TASK001] Build and deploy reusable Azure SRE incident lab - 85%. All 28 additional fault scripts and operational dashboard implemented; nine additional scenarios live rehearsed and recovered so far. Remaining rehearsals, final UI deployment and baseline verification underway. SRE Agent investigation remains unverified.

## Completed
- [TASK008] Repair baseline redeployment - Completed on 2026-10-29. Existing VM bootstrap and subnet NSGs preserved; real ARM deployment Succeeded; route injection dry run, telemetry baseline, local checks and public checkout passed. No fault injected.
- [TASK007] All scenario recovery verification - Completed on 2026-10-29. All 28 resets attempted without saved state; all 28 recovered observations and final public checkout passed. No restoration mutations performed.
- [TASK006] Lab verification after failed redeployment - Completed on 2026-10-29. Scoped metadata recovery and regression tests; exact live telemetry baseline passed. ARM redeployment remains failed on immutable VM customData.
- [TASK005] Public shop recovery - Completed on 2026-10-29. Restored missing client data mount and service; public checkout and persisted lookup passed. Reboot resilience not tested.
- [TASK004] Ordered test runbook - Completed on 2026-09-22. All 29 tests, five phases each, SRE prompts, alert expectations and recovery gates; static coverage and command checks passed, no faults executed.
- [TASK003] Public HTTPS shop - Completed on 2026-09-22. Public HTTPS, four images, persisted checkout/lookup, desktop/mobile and refresh timing verified; data/operations remain private. See SHOP.md.
- [TASK002] Migrate to resource-dependent Fieldnote shop - Completed on 2026-09-22. Deployed AKS/VM shop, private Blob/Vault data, persisted checkout; three real dependency failures/recoveries and final telemetry baseline verified. Exhaustive scenario rehearsals remain in TASK001. See SHOP.md.