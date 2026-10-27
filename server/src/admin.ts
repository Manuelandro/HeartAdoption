import { connectDatabase, migrate } from './database.js';
const [email, ...countries] = process.argv.slice(2);
if (!email || !countries.length || countries.some(c => !/^[A-Z]{2}$/.test(c))) throw new Error('Usage: npm run admin -- EMAIL IT GR [more country codes]');
const db = await connectDatabase(process.env.DATABASE_URL ?? 'pglite://.data/local');
try {
  await migrate(db);
  await db.transaction(async tx => {
    const [user] = await tx.query('SELECT id FROM users WHERE email=$1', [email.toLowerCase()]);
    if (!user) throw new Error('This person must create an account first.');
    for (const code of countries) await tx.query('INSERT INTO country_admins(user_id, country_code) VALUES($1,$2) ON CONFLICT DO NOTHING', [user.id, code]);
  });
  console.log(`Assigned ${email} to ${countries.join(', ')}.`);
} finally { await db.close(); }
