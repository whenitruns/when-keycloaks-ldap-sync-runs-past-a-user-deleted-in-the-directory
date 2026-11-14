# When Keycloak's LDAP Sync Runs Past a User Deleted in the Directory — reproduction

When It Runs — Run Report #RR14 · Testing what infrastructure actually does.

Run Report: https://whenitruns.substack.com/p/when-keycloaks-ldap-sync-runs-past

This repository holds the reproduction from the report above: the two files printed in its §4 (Reproduction), byte for byte, and the commands its §4 prints, run one step at a time. Nothing here adds versions, configurations, or findings beyond the report. All passwords here are lab-only values.

## Setup pinned in the report

- Keycloak 26.7.4 from the official image `quay.io/keycloak/keycloak:26.7.4`, pinned by digest (`sha256:82a77884f3af238beab1e7afd63b5f530e1b5c0590bd7aa60b40a40463e29b2c`), started with `start-dev` and the bootstrap-admin variables from Keycloak's container guide, with the log level `INFO,org.keycloak.storage.UserStorageManager:debug` — INFO everywhere, and DEBUG for the class that removes invalid users. In the report's lab, the linux/amd64 image in that digest (`sha256:3d911baa186f352563854039b95f21a7e2c01c76b527fdc64f24a0885b927bdf`) is what ran.
- The LDAP server: 389 Directory Server from the project's image `docker.io/389ds/dirsrv:3.1` (`sha256:af99ccf42c1cd02799d674ffdee3612a1bbd426c1a8a636da67ea349659ee5e0`), with the suffix `dc=rr14,dc=test` and the three test users of `rr14-users.ldif`.
- Both containers on one Docker network, `rr14-net`; Keycloak's port bound to 127.0.0.1 only; `curl` and `jq` for the REST calls.
- Two realms that differ in one setting — "Remove invalid users during searches" not set (so on) in `rr14`, and `false` in `rr14-keep` — each with the LDAP provider of `rr14-ldap-provider.json` (*Import users* on, edit mode `READ_ONLY`, periodic syncs off), admin and user events saved, and a realm role, `rr14-local-role`, that exists only in Keycloak.
- Verified on: 2026-09-28 (desk sources re-checked; 26.7.4 was the latest release) · lab measured 2026-09-28 on Keycloak 26.7.4 — re-verification against the then-current release happens at publication.

## Not scripted here

The report describes these without printing a command for them, so they are not scripted:

- step 6's events and log — §4 says "the events and the log as in step 5" without printing those commands again; run step 5's last three commands after step 6 (with `T` set to the time of the lookup);
- reading the results side by side — for each step, the sync results, the users count, the admin and user events, and the server log lines around the syncs and the lookup.

## Files

| File | From the report |
|---|---|
| `rr14-users.ldif` | §4 — the three test users (lab-only values), byte for byte |
| `rr14-ldap-provider.json` | §4 — the LDAP provider for `rr14`, byte for byte (step 2 derives the `rr14-keep` provider from it) |
| `reproduce.sh` | §4 — every line of its block, with the commands it prints, one step per run |

## Run order

On a test machine with Docker, `curl` and `jq` (all times UTC):

1. `./reproduce.sh 0` — the Docker network, the LDAP server (with its backend and suffix entry) and Keycloak 26.7.4; waits until each has started.
2. `./reproduce.sh 1` — load the three test users and list them in LDAP.
3. `./reproduce.sh 2` — the two realms, their LDAP providers, events and the local role; prints each provider's stored configuration.
4. `./reproduce.sh 3` — T0: a full sync in both realms and the users count; gives `rr14-user2` the local role in `rr14` and lists the role's members.
5. `./reproduce.sh 4` — delete `rr14-user2` in LDAP and confirm it is gone there.
6. `./reproduce.sh 5` — in both realms, a full sync and a changed-users sync with the users count after each; then the admin and user events and the server log since the first sync.
7. `./reproduce.sh 6` — the one planned lookup in `rr14` (an exact username search) and the users count.
8. `./reproduce.sh 7` — the local role's members in `rr14`.
9. `./reproduce.sh 8` — the option off (`rr14-keep`): the same lookup, the users count and one login attempt as the user.
10. `./reproduce.sh 9` — remove the containers and the network.

## Expected observation

From the report (§3):

> **Design check (before measuring):** the stored provider configuration had no `removeInvalidUsersEnabled` key in `rr14` and `["false"]` in `rr14-keep`, and the provider's authentication test against the LDAP server passed (HTTP 204). The first full sync (07:47:11) returned `{"ignored":false,"added":3,"updated":0,"removed":0,"failed":0,"status":"3 imported users, 0 updated users"}` in each realm, and the users count was 3. Called just before and just after `rr14-user2` was deleted in LDAP (07:47:12.3), the users count returned 3 in both realms, with no new admin or user event and no "Removed invalid user" line in the log — so calling it does not look users up.

> **After the LDAP deletion — a full sync and a changed-users sync (both realms):** after the deletion, an LDAP search for `rr14-user2` returned no entry. In both realms, the full sync (07:47:14.7 in `rr14`, 07:47:14.9 in `rr14-keep`) returned `{"ignored":false,"added":0,"updated":2,"removed":0,"failed":0,"status":"0 imported users, 2 updated users"}` and the changed-users sync right after it `{"ignored":false,"added":0,"updated":0,"removed":0,"failed":0,"status":"0 imported users, 0 updated users"}`; the users count was 3 after each. Each sync added one admin event, an `ACTION` on `user-storage/<provider id>/sync` whose representation holds the result above; there were no user events. The server log had INFO lines for each sync, such as `Sync all users finished: 0 imported users, 2 updated users`, and no line mentioning `rr14-user2`.

> **The planned lookup (`rr14`):** the exact-username search for `rr14-user2` (07:47:15.2) returned `[]`, and the users count right after was 2. The admin events were the same six as before the search — the role's and the provider's creation, the role mapping and the three syncs — with no entry for the user's removal; there were no user events. The server log had one line about it, at DEBUG, written while the search ran: `2026-09-28 07:47:15,441 DEBUG [org.keycloak.storage.UserStorageManager] (executor-thread-1) Removed invalid user 'rr14-user2'`. No line at INFO mentioned the user.

> **The role mapping held only in Keycloak (`rr14`):** at T0 the role's members were `rr14-user2` (the mapping was saved as a `CREATE` `REALM_ROLE_MAPPING` admin event at 07:47:12.0); after the lookup, the role's members were `[]`, with no admin event for the mapping's removal.

> **The option off (`rr14-keep`):** the same search (07:47:17.7) returned the user with `"enabled":false`; the response has no field that marks a user read-only, and we did not try to edit it. The users count stayed 3. The login attempt as `rr14-user2` returned `{"error":"invalid_grant","error_description":"Invalid user credentials"}`, and the realm saved a `LOGIN_ERROR` user event with the error `user_disabled`, also logged at WARN. There was no "Removed invalid user" line and no new admin event in this realm.

> "Stayed" in this section means the users count did not drop and the sync reported no removal — measured without looking the user up, because any lookup can itself remove the user; "removed" means the count dropped by one and the exact search returned no user. "No admin event" means the realm's admin events (saved with representations) have no entry for the user's removal; "no log line at INFO" means the server log, captured in full with timestamps, has no line about the user at INFO level around the lookup.

The report's own limits (§6):

> **Other LDAP servers.** We measured one LDAP server, 389 Directory Server 3.1; Active Directory, OpenLDAP and other servers were not measured.

> **Directory size and periodic syncs.** Our directory had three users and we ran each sync by hand; large directories and the timing of periodic syncs were not measured.

> **Cached users.** The option text says the removal "will only happen when the user is not yet cached", and by the source a user served from Keycloak's cache is not validated (`UserStorageManager.java` L154–157); we did not measure how long a user deleted in LDAP can be served from the cache.

> **Other versions.** Only Keycloak 26.7.4 was measured; 26.7.5, 26.8.0, 26.8.1 and 26.8.2, released on 2026-09-30, 2026-10-01, 2026-10-13 and 2026-11-05, were not measured; all four include security fixes; the reports quoted in §1 are from 23.0.4 and 26.0.5.

> **Where this is heading.** Issue #35235 is open as an enhancement, and pull requests that would delete users during a sync ([#36359](https://github.com/keycloak/keycloak/pull/36359), "Delete users on ldap sync"; [#36256](https://github.com/keycloak/keycloak/pull/36256), "Delete users during LDAP Sync") were closed without being merged. A release that deletes users during a sync would change this result; we re-check before publishing.

---

The team behind When It Runs maintains its own test environments and re-verifies findings when new releases change things; that is what the "Verified on" date means.

Licensed under the Apache License 2.0 — see `LICENSE`.
