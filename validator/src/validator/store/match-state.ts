import type { StoredMatch } from "../types";

export interface MatchStateStore {
  get(key: string): Promise<StoredMatch | null>;
  set(key: string, match: StoredMatch, ttlSeconds: number): Promise<void>;
  delete(key: string): Promise<void>;
  getAll(): Promise<StoredMatch[]>;
}

interface CacheEntry {
  match: StoredMatch;
  expiresAt: number;
}

export class InMemoryMatchStateStore implements MatchStateStore {
  private matchCache: Map<string, CacheEntry> = new Map();
  private cleanupInterval: Timer | null = null;
  /** Fired exactly once when a match leaves the store (expiry or delete). Used
   *  to release the match's pinned catalog version ref. NOT fired on set()
   *  (which only updates an existing entry in place). */
  private onEvict?: (match: StoredMatch) => void;

  constructor(onEvict?: (match: StoredMatch) => void) {
    this.onEvict = onEvict;
    this.startCleanup();
  }

  private startCleanup(): void {
    this.cleanupInterval = setInterval(() => {
      this.cleanup();
    }, 60000);
  }

  /** Remove a key and notify onEvict once (idempotent — no-op if absent). */
  private evict(key: string): void {
    const entry = this.matchCache.get(key);
    if (!entry) return;
    this.matchCache.delete(key);
    this.onEvict?.(entry.match);
  }

  private cleanup(): void {
    const now = Date.now();
    const expiredKeys: string[] = [];

    for (const [key, entry] of this.matchCache.entries()) {
      if (entry.expiresAt < now) {
        expiredKeys.push(key);
      }
    }

    for (const key of expiredKeys) {
      this.evict(key);
    }
  }

  async get(matchId: string): Promise<StoredMatch | null> {
    const entry = this.matchCache.get(matchId);
    if (!entry) {
      return null;
    }

    if (entry.expiresAt < Date.now()) {
      this.evict(matchId);
      return null;
    }

    return entry.match;
  }

  async set(matchId: string, match: StoredMatch, ttlSeconds: number): Promise<void> {
    const expiresAt = Date.now() + ttlSeconds * 1000;

    this.matchCache.set(matchId, {
      match,
      expiresAt,
    });
  }

  async delete(matchId: string): Promise<void> {
    this.evict(matchId);
  }

  async getAll(): Promise<StoredMatch[]> {
    const now = Date.now();
    const matches: StoredMatch[] = [];

    for (const [_, entry] of this.matchCache.entries()) {
      if (entry.expiresAt >= now) {
        matches.push(entry.match);
      }
    }

    return matches;
  }

  stop(): void {
    if (this.cleanupInterval) {
      clearInterval(this.cleanupInterval);
      this.cleanupInterval = null;
    }
  }
}
