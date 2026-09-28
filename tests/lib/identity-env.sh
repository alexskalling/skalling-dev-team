#!/usr/bin/env bash
# tests/lib/identity-env.sh — identidad de runtime para los tests de TeamDB.
#
# v0.11.14 (7befe46) movió la identidad de una variable que escribía el propio
# comando (--actor/--by) a una que inyecta el runtime de OpenCode
# (SKALLING_RUNTIME_AGENT). teamdb_runtime_actor() (lib-teamdb.sh:42) manda la
# del runtime y rechaza como falsificación un --actor/--by distinto; sin
# runtime vale lo declarado. Los tests fijan la variable para que el resultado
# no dependa de QUIÉN corra la suite.
#
# Son dos entornos, no dos atajos:
#
#   as_runtime_agent <agente> <cmd...>  Corre el comando atribuyéndolo al agente
#                                       simulado. Es el camino de un agente de
#                                       OpenCode: teamdb-claim.sh acepta el
#                                       --actor/--by del agente y rechaza el de
#                                       otro. La sesión del runner se saca: la
#                                       identidad la decide el runtime, no un
#                                       --actor/--by del comando.
#
#   without_runtime <cmd...>            Corre el comando como un humano en una
#                                       terminal, fuera de OpenCode. El sellador
#                                       de shell tiene el guard INVERSO
#                                       (teamdb-seal-receipt.sh:63-65): si la
#                                       identidad del runtime está presente se
#                                       NIEGA para cualquier agente, porque
#                                       dentro de OpenCode la aprobación la
#                                       registra skalling_workflow. Ahí la
#                                       variable se unsetea, no se pone.
#
# TEAMDB_CLAIM_* no se tocan en ninguno de los dos: los pone el caller a
# propósito (son la evidencia que el sello exige).
#
# Uso: . "$ROOT/tests/lib/identity-env.sh"

as_runtime_agent() {
  local agent="$1"; shift
  env -u SKALLING_RUNTIME_SESSION "SKALLING_RUNTIME_AGENT=$agent" "$@"
}

without_runtime() {
  env -u SKALLING_RUNTIME_AGENT -u SKALLING_RUNTIME_SESSION -u SKALLING_WORKFLOW_CHECK \
      -u SKALLING_REVIEW_AGENT -u SKALLING_VERIFY_WAIVER "$@"
}
