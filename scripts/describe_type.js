// Prints the field tree of a Metadata API type (describeValueType). Usage: node scripts/describe_type.js ConversationMessageDefinition
const path = '/usr/local/lib/sf/node_modules/@salesforce/core';
const { Org } = require(path);
(async () => {
  const org = await Org.create({ aliasOrUsername: 'kotak-demo' });
  const conn = org.getConnection('67.0');
  const res = await conn.metadata._invoke('describeValueType', { type: '{http://soap.sforce.com/2006/04/metadata}' + process.argv[2] });
  const walk = (fields, d) => [].concat(fields || []).forEach(f => {
    const pv = [].concat(f.picklistValues || []).map(p => p.value).join('|');
    console.log('  '.repeat(d) + f.name + ' : ' + f.soapType + (pv ? ' [' + pv + ']' : ''));
    walk(f.fields, d + 1);
  });
  walk(res.valueTypeFields, 0);
})().catch(e => { console.error(e.message); process.exit(1); });
