// Minimal stand-in for Cloudflare D1, backed by node:sqlite, so tests run the
// relay's real SQL against the real schema. Covers only what the relay uses:
// prepare().bind().first()/all()/run() and batch().

import { readFileSync } from 'node:fs';
import { DatabaseSync } from 'node:sqlite';

const SCHEMA = new URL('../migrations/0001_relay.sql', import.meta.url);

export function createTestDB() {
  const sqlite = new DatabaseSync(':memory:');
  sqlite.exec(readFileSync(SCHEMA, 'utf8'));

  const plain = (row) => (row ? { ...row } : null);
  const returnsRows = (sql) => /^\s*SELECT/i.test(sql) || /\bRETURNING\b/i.test(sql);

  class Statement {
    constructor(sql, params = []) {
      this.sql = sql;
      this.params = params;
    }
    bind(...params) {
      return new Statement(this.sql, params);
    }
    async first() {
      return plain(sqlite.prepare(this.sql).get(...this.params));
    }
    async all() {
      return this.exec();
    }
    async run() {
      return this.exec();
    }
    exec() {
      const stmt = sqlite.prepare(this.sql);
      if (returnsRows(this.sql)) {
        const results = stmt.all(...this.params).map(plain);
        return { results, meta: { changes: results.length } };
      }
      const { changes } = stmt.run(...this.params);
      return { results: [], meta: { changes: Number(changes) } };
    }
  }

  return {
    sqlite,
    prepare: (sql) => new Statement(sql),
    async batch(statements) {
      sqlite.exec('BEGIN');
      try {
        const out = statements.map((s) => s.exec());
        sqlite.exec('COMMIT');
        return out;
      } catch (err) {
        sqlite.exec('ROLLBACK');
        throw err;
      }
    },
  };
}
