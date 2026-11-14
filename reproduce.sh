#!/usr/bin/env bash
# Run Report #RR14, §4 (Reproduction). Every line of the report's §4 block appears below, in order and exactly as printed;
# each step then runs the commands its lines print, one step per invocation. rr14-users.ldif and rr14-ldap-provider.json
# are the report's files, byte for byte; the passwords in them and below are lab-only values. The helpers printed in §4
# are defined before any step runs.
#   ./reproduce.sh 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9
# Exit codes: in step 5 the log filter (grep) exits 1 when nothing matches. Step 8's login attempt is refused by design, but
# curl still exits 0 and jq prints the error. The script runs under `set -uo pipefail` without `-e`, so a non-zero exit does
# not stop a step.
set -uo pipefail
cd "$(dirname "$0")"

step_0() {
# 0. A Docker network; the LDAP server (389 Directory Server 3.1, the project's image, digest-pinned) with the
#    suffix dc=rr14,dc=test; Keycloak 26.7.4 (official image, digest-pinned) in dev mode, with the
#    UserStorageManager log category at DEBUG and everything else at INFO. Keycloak's port on 127.0.0.1 only.
#      docker network create rr14-net
#      docker run -d --name rr14-ldap --network rr14-net -e DS_DM_PASSWORD=rr14-dm-dummy -e DS_SUFFIX_NAME=dc=rr14,dc=test docker.io/389ds/dirsrv@sha256:af99ccf42c1cd02799d674ffdee3612a1bbd426c1a8a636da67ea349659ee5e0
#      for i in $(seq 1 60); do docker logs rr14-ldap 2>&1 | grep '389-ds-container started.' && break; sleep 3; done   # at most 3 minutes; then the backend and the suffix entry:
#      docker exec rr14-ldap dsconf localhost backend create --suffix dc=rr14,dc=test --be-name userroot --create-suffix
#      docker run -d --name rr14-kc --network rr14-net -p 127.0.0.1:8080:8080 -e KC_BOOTSTRAP_ADMIN_USERNAME=admin -e KC_BOOTSTRAP_ADMIN_PASSWORD=change_me quay.io/keycloak/keycloak:26.7.4@sha256:82a77884f3af238beab1e7afd63b5f530e1b5c0590bd7aa60b40a40463e29b2c start-dev --log-level="INFO,org.keycloak.storage.UserStorageManager:debug"
#      for i in $(seq 1 90); do docker logs rr14-kc 2>&1 | grep -E 'Keycloak 26\.7\.4 on JVM .* started in' && break; sleep 2; done   # the startup line, at most 3 minutes
docker network create rr14-net
docker run -d --name rr14-ldap --network rr14-net -e DS_DM_PASSWORD=rr14-dm-dummy -e DS_SUFFIX_NAME=dc=rr14,dc=test docker.io/389ds/dirsrv@sha256:af99ccf42c1cd02799d674ffdee3612a1bbd426c1a8a636da67ea349659ee5e0
for i in $(seq 1 60); do docker logs rr14-ldap 2>&1 | grep '389-ds-container started.' && break; sleep 3; done   # at most 3 minutes; then the backend and the suffix entry:
docker exec rr14-ldap dsconf localhost backend create --suffix dc=rr14,dc=test --be-name userroot --create-suffix
docker run -d --name rr14-kc --network rr14-net -p 127.0.0.1:8080:8080 -e KC_BOOTSTRAP_ADMIN_USERNAME=admin -e KC_BOOTSTRAP_ADMIN_PASSWORD=change_me quay.io/keycloak/keycloak:26.7.4@sha256:82a77884f3af238beab1e7afd63b5f530e1b5c0590bd7aa60b40a40463e29b2c start-dev --log-level="INFO,org.keycloak.storage.UserStorageManager:debug"
for i in $(seq 1 90); do docker logs rr14-kc 2>&1 | grep -E 'Keycloak 26\.7\.4 on JVM .* started in' && break; sleep 2; done   # the startup line, at most 3 minutes
}

step_1() {
# 1. Load the test users (rr14-users.ldif below) and list them in LDAP.
#      docker exec -i rr14-ldap ldapadd -x -H ldap://localhost:3389 -D "cn=Directory Manager" -w rr14-dm-dummy < rr14-users.ldif
#      docker exec rr14-ldap ldapsearch -x -H ldap://localhost:3389 -D "cn=Directory Manager" -w rr14-dm-dummy -b ou=people,dc=rr14,dc=test "(uid=rr14-*)" dn
docker exec -i rr14-ldap ldapadd -x -H ldap://localhost:3389 -D "cn=Directory Manager" -w rr14-dm-dummy < rr14-users.ldif
docker exec rr14-ldap ldapsearch -x -H ldap://localhost:3389 -D "cn=Directory Manager" -w rr14-dm-dummy -b ou=people,dc=rr14,dc=test "(uid=rr14-*)" dn
}

# Helpers for the admin REST calls (the token is never printed):
#      admin_token() { curl -s -d grant_type=password -d client_id=admin-cli -d username=admin -d password=change_me http://127.0.0.1:8080/realms/master/protocol/openid-connect/token | jq -r .access_token; }
#      kc() { curl -s -H "Authorization: Bearer $(admin_token)" -H 'Content-Type: application/json' "$@"; }
#      A=http://127.0.0.1:8080/admin/realms
#      ldap_id() { kc "$A/$1/components?type=org.keycloak.storage.UserStorageProvider" | jq -r '.[0].id'; }
admin_token() { curl -s -d grant_type=password -d client_id=admin-cli -d username=admin -d password=change_me http://127.0.0.1:8080/realms/master/protocol/openid-connect/token | jq -r .access_token; }
kc() { curl -s -H "Authorization: Bearer $(admin_token)" -H 'Content-Type: application/json' "$@"; }
A=http://127.0.0.1:8080/admin/realms
ldap_id() { kc "$A/$1/components?type=org.keycloak.storage.UserStorageProvider" | jq -r '.[0].id'; }

step_2() {
# 2. Two realms that differ in one setting, each with the LDAP provider (rr14-ldap-provider.json below), saved
#    admin and user events, and a realm role that exists only in Keycloak.
#      for R in rr14 rr14-keep; do
#        kc -X POST $A -d "{\"id\":\"$R\",\"realm\":\"$R\",\"enabled\":true,\"eventsEnabled\":true,\"adminEventsEnabled\":true,\"adminEventsDetailsEnabled\":true}"
#        kc -X POST $A/$R/roles -d '{"name":"rr14-local-role"}'
#      done
#      kc -X POST $A/rr14/components -d @rr14-ldap-provider.json
#      jq '.parentId = "rr14-keep" | .config.removeInvalidUsersEnabled = ["false"]' rr14-ldap-provider.json | kc -X POST $A/rr14-keep/components -d @-
#      for R in rr14 rr14-keep; do kc "$A/$R/components/$(ldap_id $R)" | jq -c .config; done
for R in rr14 rr14-keep; do
  kc -X POST $A -d "{\"id\":\"$R\",\"realm\":\"$R\",\"enabled\":true,\"eventsEnabled\":true,\"adminEventsEnabled\":true,\"adminEventsDetailsEnabled\":true}"
  kc -X POST $A/$R/roles -d '{"name":"rr14-local-role"}'
done
kc -X POST $A/rr14/components -d @rr14-ldap-provider.json
jq '.parentId = "rr14-keep" | .config.removeInvalidUsersEnabled = ["false"]' rr14-ldap-provider.json | kc -X POST $A/rr14-keep/components -d @-
for R in rr14 rr14-keep; do kc "$A/$R/components/$(ldap_id $R)" | jq -c .config; done
}

step_3() {
# 3. T0: a full sync in both realms, then the users count; give rr14-user2 the local role in rr14 and list the role's members.
#      for R in rr14 rr14-keep; do kc -X POST "$A/$R/user-storage/$(ldap_id $R)/sync?action=triggerFullSync" | jq -c .; kc "$A/$R/users/count"; echo; done
#      U=$(kc "$A/rr14/users?username=rr14-user2&exact=true" | jq -r '.[0].id')
#      kc -X POST $A/rr14/users/$U/role-mappings/realm -d "[$(kc $A/rr14/roles/rr14-local-role)]"
#      kc $A/rr14/roles/rr14-local-role/users | jq -r '.[].username'
for R in rr14 rr14-keep; do kc -X POST "$A/$R/user-storage/$(ldap_id $R)/sync?action=triggerFullSync" | jq -c .; kc "$A/$R/users/count"; echo; done
U=$(kc "$A/rr14/users?username=rr14-user2&exact=true" | jq -r '.[0].id')
kc -X POST $A/rr14/users/$U/role-mappings/realm -d "[$(kc $A/rr14/roles/rr14-local-role)]"
kc $A/rr14/roles/rr14-local-role/users | jq -r '.[].username'
}

step_4() {
# 4. Delete rr14-user2 in LDAP and confirm it is gone there.
#      docker exec rr14-ldap ldapdelete -x -H ldap://localhost:3389 -D "cn=Directory Manager" -w rr14-dm-dummy "uid=rr14-user2,ou=people,dc=rr14,dc=test"
#      docker exec rr14-ldap ldapsearch -x -H ldap://localhost:3389 -D "cn=Directory Manager" -w rr14-dm-dummy -b ou=people,dc=rr14,dc=test "(uid=rr14-user2)" dn
docker exec rr14-ldap ldapdelete -x -H ldap://localhost:3389 -D "cn=Directory Manager" -w rr14-dm-dummy "uid=rr14-user2,ou=people,dc=rr14,dc=test"
docker exec rr14-ldap ldapsearch -x -H ldap://localhost:3389 -D "cn=Directory Manager" -w rr14-dm-dummy -b ou=people,dc=rr14,dc=test "(uid=rr14-user2)" dn
}

step_5() {
# 5. In both realms: a full sync, then a changed-users sync; after each, the users count (not a lookup),
#    the admin and user events, and the server log since the sync.
#      T=$(date -u +%Y-%m-%dT%H:%M:%SZ)   # T = the time of the first sync
#      for R in rr14 rr14-keep; do
#        kc -X POST "$A/$R/user-storage/$(ldap_id $R)/sync?action=triggerFullSync" | jq -c .; kc "$A/$R/users/count"; echo
#        kc -X POST "$A/$R/user-storage/$(ldap_id $R)/sync?action=triggerChangedUsersSync" | jq -c .; kc "$A/$R/users/count"; echo
#      done
#      kc "$A/rr14/admin-events?max=100" | jq -c '.[] | {time, operationType, resourceType, resourcePath}'
#      kc "$A/rr14/events?max=100" | jq -c '.[] | {time, type, userId, error}'
#      docker logs --timestamps --since "$T" rr14-kc 2>&1 | grep -E 'rr14-user2|UserStorageManager|Sync (all|changed) users finished'   # T = the time of the first sync
T=$(date -u +%Y-%m-%dT%H:%M:%SZ)   # T = the time of the first sync
for R in rr14 rr14-keep; do
  kc -X POST "$A/$R/user-storage/$(ldap_id $R)/sync?action=triggerFullSync" | jq -c .; kc "$A/$R/users/count"; echo
  kc -X POST "$A/$R/user-storage/$(ldap_id $R)/sync?action=triggerChangedUsersSync" | jq -c .; kc "$A/$R/users/count"; echo
done
kc "$A/rr14/admin-events?max=100" | jq -c '.[] | {time, operationType, resourceType, resourcePath}'
kc "$A/rr14/events?max=100" | jq -c '.[] | {time, type, userId, error}'
docker logs --timestamps --since "$T" rr14-kc 2>&1 | grep -E 'rr14-user2|UserStorageManager|Sync (all|changed) users finished'   # T = the time of the first sync
}

step_6() {
# 6. The one planned lookup in rr14 (an exact username search), then the users count, the events and the log as in step 5.
#      kc "$A/rr14/users?username=rr14-user2&exact=true" | jq -c .
#      kc "$A/rr14/users/count"
kc "$A/rr14/users?username=rr14-user2&exact=true" | jq -c .
kc "$A/rr14/users/count"
}

step_7() {
# 7. The local role's members in rr14 after the lookup.
#      kc $A/rr14/roles/rr14-local-role/users | jq -r '.[].username'
kc $A/rr14/roles/rr14-local-role/users | jq -r '.[].username'
}

step_8() {
# 8. The option off (rr14-keep): the same lookup, the users count, and one login attempt as the user.
#      kc "$A/rr14-keep/users?username=rr14-user2&exact=true" | jq -c .
#      kc "$A/rr14-keep/users/count"
#      curl -s -d grant_type=password -d client_id=admin-cli -d username=rr14-user2 -d password=rr14-user-dummy http://127.0.0.1:8080/realms/rr14-keep/protocol/openid-connect/token | jq -c '{error, error_description}'
kc "$A/rr14-keep/users?username=rr14-user2&exact=true" | jq -c .
kc "$A/rr14-keep/users/count"
curl -s -d grant_type=password -d client_id=admin-cli -d username=rr14-user2 -d password=rr14-user-dummy http://127.0.0.1:8080/realms/rr14-keep/protocol/openid-connect/token | jq -c '{error, error_description}'
}

step_9() {
# 9. Remove our containers and network.
#      docker rm -f rr14-kc rr14-ldap && docker network rm rr14-net
docker rm -f rr14-kc rr14-ldap && docker network rm rr14-net
}

case "${1:-}" in
  0) step_0 ;;
  1) step_1 ;;
  2) step_2 ;;
  3) step_3 ;;
  4) step_4 ;;
  5) step_5 ;;
  6) step_6 ;;
  7) step_7 ;;
  8) step_8 ;;
  9) step_9 ;;
  *) echo "usage: $0 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9  (one step per run; see README)"; exit 2 ;;
esac
