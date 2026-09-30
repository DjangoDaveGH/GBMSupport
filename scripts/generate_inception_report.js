const admin = require('firebase-admin');
const fs = require('fs');
const sa = require('./service-account.json');
admin.initializeApp({credential: admin.credential.cert(sa)});
const db = admin.firestore();
const plain = v => { if (v && typeof v.toDate === 'function') return v.toDate().toISOString(); if (Array.isArray(v)) return v.map(plain); if (v && typeof v === 'object') return Object.fromEntries(Object.entries(v).map(([k,x])=>[k,plain(x)])); return v; };
const docs = snap => snap.docs.map(d => ({id:d.id,...plain(d.data())}));
const dateOf = x => new Date(x);
const month = x => x ? x.slice(0,7) : '(none)';
const weekday = iso => dateOf(iso).getUTCDay();
const countBy = (xs, fn) => xs.reduce((m,x)=>{const k=fn(x)??'(none)';m[k]=(m[k]||0)+1;return m;},{});
const sortTime = (a,b) => (a.timestamp||a.createdAt||a.updatedAt||'').localeCompare(b.timestamp||b.createdAt||b.updatedAt||'');
const startEnd = xs => { const ys=xs.flatMap(x=>[x.createdAt,x.timestamp,x.updatedAt].filter(Boolean)).sort(); return {first:ys[0]||null,last:ys.at(-1)||null}; };
const csvCell = v => { if(v===null||v===undefined)return ''; const s=typeof v==='object'?JSON.stringify(v):String(v); return /[",\n]/.test(s)?`"${s.replace(/"/g,'""')}"`:s; };
function csv(name, cols, rows) { fs.writeFileSync(`./scripts/${name}`, [cols.join(','),...rows.map(x=>cols.map(c=>csvCell(x[c])).join(','))].join('\n')); }

async function main() {
  const [us,ts,ns,as,acs] = await Promise.all([db.collection('users').get(),db.collection('tickets').get(),db.collection('notifications').get(),db.collection('audit_logs').get(),db.collectionGroup('activity').get()]);
  const users=docs(us), tickets=docs(ts), notifications=docs(ns), auditLogs=docs(as), activities=docs(acs);
  const userById=new Map(users.map(x=>[x.id,x])); const ticketById=new Map(tickets.map(x=>[x.id,x]));
  const creator=t=>userById.get(t.createdBy); const ticketRef=id=>ticketById.get(id)?.ticketReference||id||'';
  const isMmdaTest=t=>{const u=creator(t); return u?.institutionType==='MMDA' && t.createdAt?.slice(0,10) <= '2026-09-23' && [2,5].includes(weekday(t.createdAt));};
  const excluded=tickets.filter(isMmdaTest), included=tickets.filter(t=>!isMmdaTest(t)), excludedIds=new Set(excluded.map(x=>x.id));
  const operationalActivities=activities.filter(x=>!excludedIds.has(x.ticketId));
  const operationalNotifications=notifications.filter(x=>!x.ticketId||!excludedIds.has(x.ticketId));
  const userCreatedAudit=auditLogs.filter(x=>x.action==='user_created');
  const report={generatedAt:new Date().toISOString(), inception:{firstRetainedRecord:startEnd([...users,...tickets,...notifications,...auditLogs,...activities]).first,lastRetainedRecord:startEnd([...users,...tickets,...notifications,...auditLogs,...activities]).last}, rules:{testTicketRule:'Excluded only when creator institutionType is MMDA, the ticket creation date is on or before 2026-09-23, and the UTC creation date is Tuesday or Friday. Tickets created after 2026-09-23 are treated as live.',excludedTestTicketCount:excluded.length}, coverage:{allUsers:users.length,allTickets:tickets.length,allNotifications:notifications.length,allAuditLogs:auditLogs.length,allTicketActivities:activities.length}, included:{users, tickets:included, notifications:operationalNotifications, auditLogs, activities:operationalActivities}, excludedTestTickets:excluded.map(t=>({...t,creatorName:creator(t)?.name||'',creatorEmail:creator(t)?.email||'',creatorInstitutionType:creator(t)?.institutionType||''})), breakdowns:{
    usersByRole:countBy(users,x=>x.role), usersByInstitutionType:countBy(users,x=>x.institutionType), usersCreatedByMonth:countBy(users,x=>month(x.createdAt)),
    ticketsByMonth:countBy(included,x=>month(x.createdAt)), ticketsByStatus:countBy(included,x=>x.status), ticketsByPriority:countBy(included,x=>x.priority), ticketsByCategory:countBy(included,x=>x.category), ticketsByInstitutionType:countBy(included,x=>creator(x)?.institutionType||'(missing)'), ticketsByCreatorRole:countBy(included,x=>creator(x)?.role||'(missing)'), ticketsByDay:countBy(included,x=>['Sun','Mon','Tue','Wed','Thu','Fri','Sat'][weekday(x.createdAt)]),
    activitiesByAction:countBy(operationalActivities,x=>x.action), activitiesByMonth:countBy(operationalActivities,x=>month(x.timestamp)), notificationsByType:countBy(operationalNotifications,x=>x.type), notificationsByMonth:countBy(operationalNotifications,x=>month(x.createdAt)), auditByAction:countBy(auditLogs,x=>x.action), auditByMonth:countBy(auditLogs,x=>month(x.timestamp)), excludedTestsByMonth:countBy(excluded,x=>month(x.createdAt)),
  }};
  fs.writeFileSync('./scripts/inception_activity.json',JSON.stringify(report,null,2));
  const uById=userById;
  csv('inception_ticket_activity.csv',['timestamp','ticketReference','ticketId','actorId','actorName','action','fromValue','toValue','note'],operationalActivities.sort(sortTime).map(x=>({...x,ticketReference:ticketRef(x.ticketId),actorName:uById.get(x.actorId)?.name||x.actorId||'System'})));
  csv('inception_audit_logs.csv',['timestamp','auditId','actorId','action','targetType','targetId','metadata'],auditLogs.sort(sortTime).map(x=>({...x,auditId:x.id})));
  csv('inception_notifications.csv',['createdAt','notificationId','recipientId','type','ticketId','ticketReference','title','body','read'],operationalNotifications.sort(sortTime).map(x=>({...x,notificationId:x.id,ticketReference:ticketRef(x.ticketId)})));
  csv('inception_users_created.csv',['timestamp','userId','actorId','email','role','institutionId','institutionType','source'],userCreatedAudit.sort(sortTime).map(x=>({timestamp:x.timestamp,userId:x.targetId,actorId:x.actorId,email:x.metadata?.email,role:x.metadata?.role,institutionId:x.metadata?.institutionId,institutionType:uById.get(x.targetId)?.institutionType,source:x.metadata?.source})));
  csv('excluded_test_tickets.csv',['ticketReference','id','createdAt','creatorName','creatorEmail','creatorInstitutionType','institutionId','status','category','priority'],report.excludedTestTickets);
  console.log(JSON.stringify({coverage:report.coverage,inception:report.inception,excludedTestTickets:report.excludedTestTickets.length,breakdowns:report.breakdowns},null,2));
}
main().catch(e=>{console.error(e);process.exit(1)});
