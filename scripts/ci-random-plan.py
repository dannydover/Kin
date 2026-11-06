#!/usr/bin/env python3
"""Generate a disposable random-order UI test plan from the production scheme."""
import json
from pathlib import Path
import uuid
import xml.etree.ElementTree as ET


def generate(root):
    root = Path(root)
    source = root / 'Kin.xcodeproj/xcshareddata/xcschemes/Kin.xcscheme'
    scheme = source.with_name('KinRandomOrder.xcscheme')
    plan = root / 'KinRandomOrder.xctestplan'
    if scheme.exists() or plan.exists():
        raise ValueError('Refusing to overwrite an existing test plan or scheme')
    tree = ET.parse(source)
    action = tree.getroot().find('TestAction')
    testables = action.find('Testables') if action is not None else None
    if testables is None:
        raise ValueError('Production test scheme structure changed')
    references = testables.findall('TestableReference')
    targets = []
    for item in references:
        ref = item.find('BuildableReference')
        if item.get('skipped') != 'NO' or ref is None:
            raise ValueError('Unexpected skipped or missing test target')
        targets.append({'parallelizable': False, 'target': {
            'containerPath': ref.get('ReferencedContainer'),
            'identifier': ref.get('BlueprintIdentifier'),
            'name': ref.get('BlueprintName')}})
    if sorted(t['target']['name'] for t in targets) != ['KinTests', 'KinUITests']:
        raise ValueError('Production test targets changed')
    if any(not t['target']['identifier'] or t['target']['containerPath'] != 'container:Kin.xcodeproj'
           for t in targets) or len({t['target']['identifier'] for t in targets}) != len(targets):
        raise ValueError('Production test target references changed')
    action.remove(testables)
    plans = ET.SubElement(action, 'TestPlans')
    ET.SubElement(plans, 'TestPlanReference', {
        'reference': 'container:KinRandomOrder.xctestplan', 'default': 'YES'})
    ET.indent(tree, space='  ')
    content = {
        'configurations': [{'id': str(uuid.uuid4()).upper(), 'name': 'Random order',
                            'options': {'testExecutionOrdering': 'random'}}],
        'defaultOptions': {'testTimeoutsEnabled': True},
        'testTargets': targets,
        'version': 1,
    }
    scheme.parent.mkdir(parents=True, exist_ok=True)
    # Both files exist only in this disposable diagnostic runner.
    plan.write_text(json.dumps(content, indent=2) + '\n')
    tree.write(scheme, encoding='utf-8', xml_declaration=True)
    return 'KinRandomOrder'
