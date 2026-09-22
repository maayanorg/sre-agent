'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const page = fs.readFileSync(path.join(__dirname, '../workload/frontend/index.html'), 'utf8');
const source = page.match(/function operationalSummary\([\s\S]*?\n\}/)[0];
const context = vm.createContext({ operationDefinitions: [['operator'], ['ama']] });
vm.runInContext(`${source}; this.summarize = operationalSummary`, context);
const now = Date.now();
const snapshot = { checks: [
  { id: 'operator', state: 'failed', observedAt: new Date(now).toISOString(), detail: 'Authorization denied' },
  { id: 'ama', state: 'healthy', observedAt: new Date(now).toISOString(), detail: 'Agent active' }
] };
test('authorization failure is visible independently from application checks', () => {
  const result = context.summarize(snapshot, false, now);
  assert.equal(result.failed, 1); assert.equal(result.unknown, 0);
  assert.equal(result.checks[0].detail, 'Authorization denied');
  assert.equal(result.title, '1 operational failure');
});
test('stale, paused and absent operations cannot imply a current failure or health', () => {
  for (const result of [context.summarize(snapshot, false, now + 180001), context.summarize(snapshot, true, now), context.summarize(null, false, now)]) {
    assert.equal(result.failed, 0); assert.equal(result.unknown, 2);
  }
});
test('telemetry failure does not need an application failure', () => {
  const changed = structuredClone(snapshot);
  changed.checks[0].state = 'healthy'; changed.checks[1].state = 'failed';
  const result = context.summarize(changed, false, now);
  assert.equal(result.checks[0].state, 'healthy'); assert.equal(result.checks[1].state, 'failed');
});