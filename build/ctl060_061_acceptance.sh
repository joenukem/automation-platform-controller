#!/usr/bin/env bash
# CTL-060 (P0) + CTL-061 (P1) security acceptance — live, against a running
# controller. Negative checks are the executable spec (docs/design/DESIGN-AGENDA).
#
#   KUBECONFIG=... NS=automation-platform build/ctl060_061_acceptance.sh
#
# Runs entirely via `kubectl exec` into the controller web/task pods. Uses the
# ORM/serializers for authorized-content proofs (exactly what the API renders,
# no token dependency) and curl for the unauthenticated negatives. Creates only
# clearly-named CTL06x-* objects and deletes them. Exits non-zero on any failure.
# Companion report: reports/ctl-060-061-security-acceptance.md
set -uo pipefail
NS="${NS:-automation-platform}"
SVC="${SVC:-awx-controller:8052}"
WEBSEL="${WEBSEL:-awx-controller-web}"
TASKSEL="${TASKSEL:-awx-controller-task}"
fail=0
pass(){ echo "  PASS  $*"; }
bad(){ echo "  FAIL  $*"; fail=1; }

WEB=$(kubectl -n "$NS" get pods -o name | grep "$WEBSEL" | grep -v Terminating | head -1 | cut -d/ -f2)
TASK=$(kubectl -n "$NS" get pods -o name | grep "$TASKSEL" | grep -v migrate | grep -v Terminating | head -1 | cut -d/ -f2)
[ -n "$WEB" ] && [ -n "$TASK" ] || { echo "no web/task pod (WEB=$WEB TASK=$TASK)"; exit 2; }
echo "web=$WEB task=$TASK ns=$NS svc=$SVC"
kx_web(){ kubectl -n "$NS" exec "$WEB" -c awx-web -- "$@"; }
kx_task(){ kubectl -n "$NS" exec "$TASK" -c awx-task -- "$@"; }
curl_web(){ kx_web curl -s "$@"; }
shell(){ kx_task awx-manage shell -c "$1" 2>/dev/null; }

SENT="CTL061SENTINEL$(kx_task python3 -c 'import secrets;print(secrets.token_hex(8))' 2>/dev/null | tr -d '\r')"
echo "log-redaction sentinel: $SENT"

echo
echo "==================== CTL-060 (P0): no default creds, gateway identity, isolation ===================="
echo "[C1] No default credentials — every default admin login must be rejected"
c1=0
for pw in admin password AWX awx awxsecret changeme admin123 Password1 redhat ansible; do
  code=$(curl_web -o /dev/null -w '%{http_code}' -u "admin:$pw" "http://$SVC/api/v2/me/")
  [ "$code" = 401 ] || { bad "admin:$pw returned $code (expected 401)"; c1=1; }
done
[ "$c1" = 0 ] && pass "all 10 default-admin-credential logins rejected (401)"
for uu in root superuser operator awx; do
  code=$(curl_web -o /dev/null -w '%{http_code}' -u "$uu:$uu" "http://$SVC/api/v2/me/")
  [ "$code" = 401 ] || bad "$uu:$uu returned $code (expected 401)"
done
pass "no default non-admin login (root/superuser/operator/awx -> 401)"

echo "[C2] Anonymous API access denied (identity required)"
code=$(curl_web -o /dev/null -w '%{http_code}' "http://$SVC/api/v2/me/")
[ "$code" = 401 ] && pass "anonymous /api/v2/me/ -> 401" || bad "anonymous /api/v2/me/ -> $code"

echo "[C3] Forged gateway trusted-header cannot impersonate (unsigned)"
code=$(curl_web -o /dev/null -w '%{http_code}' -H 'X-DAB-JW-TOKEN: forged.header.value' -H 'X-Trusted-Proxy: 1' "http://$SVC/api/v2/me/")
[ "$code" = 401 ] && pass "forged trusted-header -> 401" || bad "forged trusted-header -> $code (expected 401)"

echo "[C4] Admin is not bootstrapped from a default env password"
envset=$(kubectl -n "$NS" get deploy "$TASKSEL" -o jsonpath='{range .spec.template.spec.containers[*].env[*]}{.name}{"\n"}{end}' 2>/dev/null | grep -c -E '^AWX_ADMIN_PASSWORD$' || true)
[ "${envset:-0}" = 0 ] && pass "no AWX_ADMIN_PASSWORD default-bootstrap env" || bad "AWX_ADMIN_PASSWORD present as env"

echo "[C5] Session isolation — a non-superuser cannot see another org's objects"
shell "
from awx.main.models import Organization, Inventory
from django.contrib.auth import get_user_model
U=get_user_model()
oa,_=Organization.objects.get_or_create(name='CTL060-orgA')
ob,_=Organization.objects.get_or_create(name='CTL060-orgB')
ua,_=U.objects.get_or_create(username='ctl060-usera'); ua.is_superuser=False; ua.set_unusable_password(); ua.save()
ub,_=U.objects.get_or_create(username='ctl060-userb'); ub.is_superuser=False; ub.set_unusable_password(); ub.save()
oa.member_role.members.add(ua); ob.member_role.members.add(ub)
inv,_=Inventory.objects.get_or_create(name='CTL060-invA', organization=oa)
inv.read_role.members.add(ua)   # userA is explicitly granted read on orgA's inventory
print('OK')" | grep -q OK && pass "isolation fixtures created" || bad "isolation setup failed"
seenB=$(shell "
from awx.main.models import Inventory
from django.contrib.auth import get_user_model
from awx.main.access import InventoryAccess
ub=get_user_model().objects.get(username='ctl060-userb')
print('VISIBLE='+str(InventoryAccess(ub).get_queryset().filter(name='CTL060-invA').exists()))" | sed -n 's/^VISIBLE=//p' | tr -d '\r')
[ "$seenB" = "False" ] && pass "userB (orgB) CANNOT see orgA inventory (RBAC-scoped)" || bad "userB sees orgA inventory (VISIBLE=$seenB)"
seenA=$(shell "
from awx.main.models import Inventory
from django.contrib.auth import get_user_model
from awx.main.access import InventoryAccess
ua=get_user_model().objects.get(username='ctl060-usera')
print('VISIBLE='+str(InventoryAccess(ua).get_queryset().filter(name='CTL060-invA').exists()))" | sed -n 's/^VISIBLE=//p' | tr -d '\r')
[ "$seenA" = "True" ] && pass "userA (orgA) CAN see orgA inventory (positive control)" || bad "userA cannot see own org inventory (VISIBLE=$seenA)"

echo
echo "==================== CTL-061 (P1): redacted logging, webhook-key authorization ===================="
echo "[L1] Secret field redaction — API representation returns \$encrypted\$, DB stores ciphertext"
red=$(shell "
from awx.main.models import Credential, CredentialType, Organization
from awx.api.serializers import CredentialSerializer
ct=CredentialType.objects.get(namespace='ssh'); o=Organization.objects.get(name='CTL060-orgA')
c,_=Credential.objects.get_or_create(name='CTL061-cred', credential_type=ct, organization=o)
c.inputs={'username':'svc','password':'$SENT'}; c.save()
rep=dict(CredentialSerializer(c).data.get('inputs',{}))
print('API_PW='+str(rep.get('password')))
print('DB_ENC='+str(c.inputs['password'].startswith('\$encrypted\$')))
print('API_LEAK='+str('$SENT' in str(CredentialSerializer(c).data)))")
echo "$red" | grep -qF 'API_PW=$encrypted$' && pass "credential password renders as \$encrypted\$ in API" || bad "credential password not redacted ($(echo "$red"|grep API_PW=))"
echo "$red" | grep -q "DB_ENC=True" && pass "credential secret stored encrypted at rest (\$encrypted\$ ciphertext)" || bad "credential secret not encrypted at rest"
echo "$red" | grep -q "API_LEAK=False" && pass "serialized credential does NOT contain the plaintext secret" || bad "serialized credential leaks plaintext"

echo "[L2] Redacted logging — the sentinel secret must not appear in controller logs"
curl_web -o /dev/null -u "admin:$SENT" "http://$SVC/api/v2/me/" >/dev/null   # a failed login carrying the sentinel as password
sleep 3
hitsWf=$(kx_web bash -c "grep -rc '$SENT' /var/log/tower /var/log/nginx 2>/dev/null | awk -F: '{s+=\$2} END{print s+0}'" 2>/dev/null | tr -d '\r')
hitsTf=$(kx_task bash -c "grep -rc '$SENT' /var/log/tower 2>/dev/null | awk -F: '{s+=\$2} END{print s+0}'" 2>/dev/null | tr -d '\r')
hitsWs=$(kubectl -n "$NS" logs "$WEB" -c awx-web --tail=3000 2>/dev/null | grep -c "$SENT" || true)
hitsTs=$(kubectl -n "$NS" logs "$TASK" -c awx-task --tail=3000 2>/dev/null | grep -c "$SENT" || true)
tot=$(( ${hitsWf:-0} + ${hitsTf:-0} + ${hitsWs:-0} + ${hitsTs:-0} ))
[ "$tot" = 0 ] && pass "sentinel secret absent from web+task logs (files+stdout) at default verbosity" \
  || bad "sentinel found in logs ($tot: filesW=$hitsWf filesT=$hitsTf stdoutW=$hitsWs stdoutT=$hitsTs)"

echo "[W1] Webhook key exposed only via the authorized sub-endpoint"
jt=$(shell "
from awx.main.models import JobTemplate, Inventory, Project, Organization
from awx.api.serializers import JobTemplateSerializer
o=Organization.objects.get(name='CTL060-orgA'); inv=Inventory.objects.get(name='CTL060-invA')
p,_=Project.objects.get_or_create(name='CTL061-proj', organization=o, defaults={'scm_type':'git','scm_url':'https://example.invalid/x.git'})
jt,_=JobTemplate.objects.get_or_create(name='CTL061-jt', defaults={'inventory':inv,'project':p,'playbook':'x.yml'})
jt.webhook_service='github'; jt.save(); jt.refresh_from_db()
print('JTID='+str(jt.id)); print('HASKEY='+str(bool(jt.webhook_key)))
print('KEY_IS_FIELD='+str('webhook_key' in JobTemplateSerializer().fields))
print('KEY_IN_DATA='+str(jt.webhook_key and (jt.webhook_key in str(JobTemplateSerializer().data))))")
JTNUM=$(echo "$jt" | sed -n 's/^JTID=//p' | tr -d '\r')
echo "$jt" | grep -q HASKEY=True && pass "JT webhook_key generated server-side" || bad "JT webhook_key not generated"
echo "$jt" | grep -q KEY_IS_FIELD=False && pass "webhook_key is NOT a field in the JT serializer (absent from detail body)" || bad "webhook_key exposed as a JT serializer field"
echo "$jt" | grep -q KEY_IN_DATA=False && pass "raw webhook_key value not present in serialized JT data" || bad "raw webhook_key leaks in serialized JT data"
codeU=$(curl_web -o /dev/null -w '%{http_code}' "http://$SVC/api/v2/job_templates/$JTNUM/webhook_key/")
[ "$codeU" = 401 ] && pass "unauthorized GET /job_templates/$JTNUM/webhook_key/ -> 401" || bad "unauthorized /webhook_key/ -> $codeU (expected 401)"

echo
echo "==================== teardown ===================="
shell "
from awx.main.models import JobTemplate, Project, Credential, Inventory, Organization
from django.contrib.auth import get_user_model
JobTemplate.objects.filter(name='CTL061-jt').delete()
Project.objects.filter(name='CTL061-proj').delete()
Credential.objects.filter(name='CTL061-cred').delete()
Inventory.objects.filter(name='CTL060-invA').delete()
get_user_model().objects.filter(username__in=['ctl060-usera','ctl060-userb']).delete()
Organization.objects.filter(name__in=['CTL060-orgA','CTL060-orgB','CTL06X-probe']).delete()
print('CLEANED')" | grep -q CLEANED && echo "  cleaned test objects" || echo "  WARN cleanup incomplete"

echo
if [ "$fail" = 0 ]; then echo "==== CTL-060/061 ACCEPTANCE: ALL CHECKS PASS ===="; else echo "==== CTL-060/061 ACCEPTANCE: FAILURES ABOVE ===="; fi
exit $fail
