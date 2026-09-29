const admin = require('firebase-admin');
const sa = require('./service-account.json');
admin.initializeApp({credential: admin.credential.cert(sa)});
const db = admin.firestore();
const val = v => v && typeof v.toDate === 'function' ? v.toDate().toISOString() : v;
const plain = v => { if (v && typeof v.toDate === 'function') return v.toDate().toISOString(); if (Array.isArray(v)) return v.map(plain); if (v && typeof v === 'object') return Object.fromEntries(Object.entries(v).map(([k,x])=>[k,plain(x)])); return v; };
async function main() {
  const [u,t,n,a,acts] = await Promise.all([db.collection('users').get(),db.collection('tickets').get(),db.collection('notifications').get(),db.collection('audit_logs').get(),db.collectionGroup('activity').get()]);
  const users=u.docs.map(d=>({id:d.id,...plain(d.data())})); const tickets=t.docs.map(d=>({id:d.id,...plain(d.data())}));
  const times = arr => arr.flatMap(x=>['createdAt','updatedAt','timestamp'].map(k=>x[k]).filter(Boolean)).sort();
  console.log(JSON.stringify({
    counts:{users:users.length,tickets:tickets.length,notifications:n.size,auditLogs:a.size,activities:acts.size},
    ranges:{users:times(users).slice(0,1).concat(times(users).slice(-1)),tickets:times(tickets).slice(0,1).concat(times(tickets).slice(-1)),notifications:times(n.docs.map(d=>d.data())).slice(0,1).concat(times(n.docs.map(d=>d.data())).slice(-1)),audit:times(a.docs.map(d=>d.data())).slice(0,1).concat(times(a.docs.map(d=>d.data())).slice(-1))},
    userSamples:users.slice(0,5),
    roleCounts:users.reduce((m,x)=>(m[x.role||'(none)']=(m[x.role||'(none)']||0)+1,m),{}),
    ticketCreatorRoleCounts:tickets.reduce((m,x)=>{const u=users.find(y=>y.id===x.createdBy);const k=u?.role||'(missing)';m[k]=(m[k]||0)+1;return m},{}),
    ticketCreatorInstitutionSamples:tickets.slice(0,20).map(x=>{const u=users.find(y=>y.id===x.createdBy);return {ticket:x.ticketReference,createdAt:x.createdAt,createdByRole:u?.role,createdByInstitution:u?.institutionId,ticketInstitution:x.institutionId}})
  },null,2));
}
main().catch(e=>{console.error(e);process.exit(1)});
