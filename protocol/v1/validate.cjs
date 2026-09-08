#!/usr/bin/env node
'use strict';

// Artifact validation only; runtime semantics are intentionally not emulated here.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const Ajv = require('../../openspec/tooling/node_modules/ajv');
const load = (name) => JSON.parse(fs.readFileSync(path.join(__dirname, name), 'utf8'));
const schema = load('schema.json');
const examples = load('examples.json');
const validate = new Ajv({ strict: true, allErrors: true }).compile(schema);
const names = new Set();
let checked = 0;
for (const [group, expected] of [['valid', true], ['invalid', false], ['semanticOnly', true]]) {
  assert.ok(Array.isArray(examples[group]) && examples[group].length > 0, `examples.${group}: missing vectors`);
  for (const vector of examples[group]) {
    assert.ok(!names.has(vector.name), `vector.name: duplicate ${vector.name}`);
    names.add(vector.name);
    const envelope = vector.bodyRecipe
      ? { ...vector.baseEnvelope, body: vector.bodyRecipe.text.repeat(vector.bodyRecipe.repeat) }
      : vector.envelope;
    const actual = validate(envelope);
    assert.equal(actual, expected, `${group}/${vector.name}: schema acceptance differs; ${JSON.stringify(validate.errors)}`);
    if (group === 'semanticOnly') {
      assert.ok(schema.definitions.error.properties.code.enum.includes(vector.expectedCode), `${vector.name}: unknown expectedCode`);
      if (vector.bodyRecipe) {
        assert.ok(Buffer.byteLength(envelope.body, 'utf8') > 65536, `${vector.name}: body recipe must exceed UTF-8 byte cap`);
      }
    }
    checked += 1;
  }
  console.log(`${group}: ${examples[group].length} classifications PASS`);
}
console.log(`Schema compiled; ${checked} vectors PASS. Semantic-only expected error codes were NOT runtime-tested.`);
