"""Review findings survive corrections; reviewer verdicts share one candidate."""
import copy
import json
from skalling_budget import validate_budget


def adopt_active_review(state):
    """Upgrade the protocol on resume without inventing evidence or resetting work."""
    if not state or state.get('review_protocol') or state.get('state') in {
            'completed', 'cancelled', 'failed', 'abandoned', 'superseded'}:
        return state
    state['review_protocol'] = 2
    verdicts = state.setdefault('review_verdicts', {})
    if state['state'] in {'quality_reviewed', 'documented'} or (state['state'] == 'verified'
            and (state['risk'] == 'high' or (state.get('verification') or {}).get('agent') == 'jhon')):
        verdicts['jhon'] = 'approved'
    if state['state'] in {'quality_reviewed', 'documented'}:
        verdicts['luz'] = 'approved'
    rejection = state.get('last_rejection')
    if rejection and state['state'] in {'implementation_ready', 'blocked'} and not state.get('review_findings'):
        add_findings(state, rejection['agent'], None, rejection['reason'])
    return state


def pending_reviewers(state):
    roles = ['jhon', 'luz'] if state['risk'] == 'high' else ['jhon']
    return [role for role in roles if role not in state.get('review_verdicts', {})]


def archive_review(state):
    if state.get('checks') or state.get('review_verdicts'):
        state.setdefault('review_history', []).append(copy.deepcopy({key: state.get(key) for key in
            ('digest', 'delivery_number', 'checks', 'oracle', 'coverage', 'review_verdicts')}))
    state['checks'] = []
    state['coverage'] = None
    state['review_verdicts'] = {}


def add_findings(state, actor, findings, reason):
    # Older callers serialize findings inside the JSON payload's string field.
    # Decode only arrays; free-text diagnostics retain their legacy identity.
    if isinstance(findings, str):
        try:
            decoded = json.loads(findings)
        except json.JSONDecodeError:
            decoded = None
        if isinstance(decoded, list):
            findings = decoded
    if not isinstance(findings, list) and state.get('finding_contract') == 1:
        raise ValueError('reject requiere findings con outcome_id o risk y files del pedido; opcionales usan defer')
    if not isinstance(findings, list):
        findings = [{'id': str(state['delivery_number']), 'problem': str(findings or reason)[:2000],
                     'expected': 'Resolver el diagnóstico y verificar la aceptación declarada'}]
    if not 1 <= len(findings) <= 30:
        raise ValueError('findings requiere 1..30 hallazgos {id,problem,expected}')
    prepared, seen = [], set()
    for item in findings:
        if (not isinstance(item, dict) or any(not isinstance(item.get(k), str) or not item[k].strip()
                for k in ('id', 'problem', 'expected')) or len(item['id']) > 100
                or any(len(item[k]) > 2000 for k in ('problem', 'expected'))):
            raise ValueError('Cada finding requiere id único, problem y expected no vacíos')
        fid = item['id'] if item['id'].startswith(actor + ':') else actor + ':' + item['id']
        if fid in seen:
            raise ValueError('Cada finding requiere id único, problem y expected no vacíos')
        seen.add(fid)
        if 'blocking' in item and item['blocking'] is not True:
            raise ValueError('Hallazgo opcional: usar defer {note_id,suggestion,reason}; no bloquea la entrega')
        outcome = item.get('outcome_id')
        if outcome is not None and (not isinstance(outcome, str) or outcome not in {o['id'] for o in state.get('outcomes', [])}):
            raise ValueError('outcome_id debe identificar un resultado de este pedido')
        risk = item.get('risk')
        files = item.get('files', [])
        if risk is not None and (not isinstance(risk, str) or not risk.strip() or len(risk) > 1000
                or not isinstance(files, list) or not files
                or any(not isinstance(f, str) or f not in state.get('files', []) for f in files)):
            raise ValueError('risk requiere impacto concreto y files dentro del alcance revisado')
        if state.get('finding_contract') == 1 and outcome is None and risk is None:
            raise ValueError('Cada bloqueo debe referir outcome_id o risk y files del pedido; opcionales usan defer')
        prepared.append({'id': fid, 'owner': actor, 'problem': item['problem'],
                         'expected': item['expected'], 'status': 'open', 'delivery_number': state['delivery_number'],
                         **({'outcome_id': outcome} if outcome is not None else {}),
                         **({'risk': risk, 'files': list(dict.fromkeys(files))} if risk is not None else {})})
    existing = {item['id']: item for item in state.get('review_findings', [])}
    for item in prepared:
        existing[item['id']] = item
    state['review_findings'] = list(existing.values())


def submit_resolutions(state, payload):
    pending = [f for f in state.get('review_findings', []) if f['status'] != 'resolved']
    if not pending:
        return
    items = payload.get('resolutions')
    valid_shape = isinstance(items, list) and all(
            isinstance(i, dict) and isinstance(i.get('finding_id'), str)
            and isinstance(i.get('change'), str) and i['change'].strip() for i in items)
    supplied = [i['finding_id'] for i in items if isinstance(i, dict) and isinstance(i.get('finding_id'), str)] if isinstance(items, list) else []
    expected = {f['id'] for f in pending}
    if not valid_shape or len(supplied) != len(set(supplied)) or set(supplied) != expected:
        recovery = {
            'missing': sorted(expected - set(supplied)),
            'unexpected': sorted(set(supplied) - expected),
            'duplicados': sorted({fid for fid in supplied if supplied.count(fid) > 1}),
            'review_findings': [{k: f[k] for k in ('id', 'problem', 'expected')} for f in pending],
            'retry': {'action': 'deliver', 'payload': {'id': state['id'], 'resolutions': [
                {'finding_id': f['id'], 'change': ''} for f in pending]}},
        }
        raise ValueError('deliver requiere resolutions [{finding_id,change}] con IDs de review_findings; '
                         'no son outcomes. Completar change con la corrección real de cada hallazgo. '
                         'Este error no consume entrega ni ejecuta pruebas. No reiniciar el workflow. '
                         + json.dumps(recovery, ensure_ascii=False))
    mapping = {i['finding_id']: i['change'] for i in items}
    for finding in pending:
        finding.update(status='addressed', change=mapping[finding['id']])


def resolve_findings(state, actor):
    for finding in state.get('review_findings', []):
        if finding['owner'] != actor or finding['status'] == 'resolved':
            continue
        if finding['status'] != 'addressed':
            raise ValueError('Hay hallazgos sin respuesta de Teo; no aprobar')
        finding.update(status='resolved', verified_digest=state['digest'])


def validate_start(payload):
    # Reject misspelled contracts before the default acceptance can hide them.
    allowed = {'id', 'request_kind', 'intent', 'outcomes', 'risk', 'scope', 'clarity', 'decision', 'sensitive', 'visual',
               'files', 'acceptance', 'reuse', 'task', 'supersedes', 'execution_mode', 'planning_required',
               'memory_required', 'context_seen', 'constraints', 'non_goals', 'commit_policy', 'focus_revision', 'resource_budget'}
    unknown = set(payload) - allowed
    if unknown:
        raise ValueError('Campos de start desconocidos: ' + ', '.join(sorted(unknown)) +
                         '. Resultados: outcomes [{id,expected}]. No se creó el workflow')
    focus_limits(payload)


def focus_limits(payload, previous=None):
    """Keep explicit request boundaries in TeamDB, including across reclassification."""
    revision = payload.get('focus_revision')
    if revision is not None:
        if (not payload.get('supersedes') or not isinstance(revision, dict)
                or set(revision) != {'feedback_id', 'evidence'}
                or any(not isinstance(revision.get(k), str) or not revision[k].strip()
                       or len(revision[k]) > limit for k, limit in [('feedback_id', 200), ('evidence', 1000)])):
            raise ValueError('focus_revision requiere supersedes y {feedback_id,evidence} del cambio pedido por el usuario')
    result = {}
    for key in ('constraints', 'non_goals'):
        values = payload.get(key, [])
        if (not isinstance(values, list) or len(values) > 12
                or any(not isinstance(v, str) or not v.strip() or len(v) > 500 for v in values)):
            raise ValueError(f'{key} requiere hasta 12 textos no vacíos de hasta 500 caracteres')
        inherited = (previous or {}).get(key, [])
        result[key] = list(dict.fromkeys(values if revision and key in payload else [*inherited, *values]))
        if len(result[key]) > 12:
            raise ValueError(f'{key} excede 12 restricciones tras supersedes')
    if len(json.dumps(result, ensure_ascii=False).encode()) > 4000:
        raise ValueError('constraints/non_goals exceden 4000 bytes; resumir sin omitir restricciones')
    inherited_policy = (previous or {}).get('commit_policy', 'required' if previous else 'allowed')
    policy = payload.get('commit_policy', inherited_policy)
    if not isinstance(policy, str) or policy not in {'required', 'allowed', 'forbidden'}:
        raise ValueError('commit_policy debe ser required, allowed o forbidden')
    if previous and policy != inherited_policy and not revision:
        raise ValueError('Cambiar commit_policy heredada requiere focus_revision del usuario')
    budget = payload.get('resource_budget', (previous or {}).get('resource_budget'))
    if 'resource_budget' in payload or budget is not None:
        result['resource_budget'] = validate_budget(budget)
    if previous and 'resource_budget' in payload and budget != previous.get('resource_budget') and not revision:
        raise ValueError('Cambiar resource_budget heredado requiere focus_revision del usuario')
    result['commit_policy'] = policy
    if revision:
        result['focus_revision'] = revision
    return result


def defer_note(state, actor, payload):
    note = {key: payload.get(key) for key in ('note_id', 'suggestion', 'reason')}
    if any(not isinstance(value, str) or not value.strip() or len(value) > limit
           for value, limit in zip(note.values(), (100, 400, 400))):
        raise ValueError('defer requiere note_id (100), suggestion y reason (400 caracteres cada uno)')
    note['owner'] = actor
    notes = state.setdefault('deferred', [])
    previous = next((n for n in notes if n['note_id'] == note['note_id'] and n['owner'] == actor), None)
    if previous:
        if previous != note:
            raise ValueError('note_id ya registrado con otro contenido')
        return False
    if len(notes) >= 12:
        raise ValueError('Ya hay 12 sugerencias diferidas; no ampliar esta revisión')
    notes.append(note)
    return True
