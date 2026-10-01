"""Review findings survive corrections; reviewer verdicts share one candidate."""
import copy


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
    if not isinstance(findings, list):
        findings = [{'id': str(state['delivery_number']), 'problem': str(findings or reason)[:2000],
                     'expected': 'Resolver el diagnóstico y verificar la aceptación declarada'}]
    if not 1 <= len(findings) <= 30:
        raise ValueError('findings requiere 1..30 hallazgos {id,problem,expected}')
    prepared, seen = [], set()
    for item in findings:
        if (not isinstance(item, dict) or any(not isinstance(item.get(k), str) or not item[k].strip()
                for k in ('id', 'problem', 'expected')) or len(item['id']) > 100 or item['id'] in seen
                or any(len(item[k]) > 2000 for k in ('problem', 'expected'))):
            raise ValueError('Cada finding requiere id único, problem y expected no vacíos')
        seen.add(item['id'])
        prepared.append({'id': actor + ':' + item['id'], 'owner': actor, 'problem': item['problem'],
                         'expected': item['expected'], 'status': 'open', 'delivery_number': state['delivery_number']})
    existing = {item['id']: item for item in state.get('review_findings', [])}
    for item in prepared:
        existing[item['id']] = item
    state['review_findings'] = list(existing.values())


def submit_resolutions(state, payload):
    pending = [f for f in state.get('review_findings', []) if f['status'] != 'resolved']
    if not pending:
        return
    items = payload.get('resolutions')
    if not isinstance(items, list) or len(items) != len(pending) or any(
            not isinstance(i, dict) or not isinstance(i.get('finding_id'), str)
            or not isinstance(i.get('change'), str) or not i['change'].strip() for i in items):
        raise ValueError('deliver requiere resolutions [{finding_id,change}] para cada hallazgo pendiente')
    mapping = {i['finding_id']: i['change'] for i in items}
    if set(mapping) != {f['id'] for f in pending}:
        raise ValueError('resolutions debe cubrir exactamente todos los hallazgos pendientes')
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
    allowed = {'id', 'intent', 'outcomes', 'risk', 'scope', 'clarity', 'decision', 'sensitive', 'visual',
               'files', 'acceptance', 'reuse', 'task', 'supersedes', 'execution_mode', 'planning_required',
               'memory_required', 'context_seen'}
    unknown = set(payload) - allowed
    if unknown:
        raise ValueError('Campos de start desconocidos: ' + ', '.join(sorted(unknown)) +
                         '. Resultados: outcomes [{id,expected}]. No se creó el workflow')
