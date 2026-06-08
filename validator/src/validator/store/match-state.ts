import type { StoredMatch } from "../types";

export interface MatchStateStore {
  get(key: string): Promise<StoredMatch | null>;
  set(key: string, match: StoredMatch, ttlSeconds: number): Promise<void>;
  delete(key: string): Promise<void>;
  getByConnectionId(connectionId: string): Promise<StoredMatch | null>;
  getAll(): Promise<StoredMatch[]>;
}

interface CacheEntry {
  match: StoredMatch;
  expiresAt: number;
}

export class InMemoryMatchStateStore implements MatchStateStore {
  private matchCache: Map<string, CacheEntry> = new Map();
  private connectionToMatchCache: Map<string, string> = new Map();
  private cleanupInterval: Timer | null = null;

  constructor() {
    this.startCleanup();
  }

  private startCleanup(): void {
    this.cleanupInterval = setInterval(() => {
      this.cleanup();
    }, 60000);
  }

  private cleanup(): void {
    const now = Date.now();
    const expiredKeys: string[] = [];

    for (const [key, entry] of this.matchCache.entries()) {
      if (entry.expiresAt < now) {
        expiredKeys.push(key);
        this.connectionToMatchCache.delete(entry.match.connection_id);
      }
    }

    for (const key of expiredKeys) {
      this.matchCache.delete(key);
    }
  }

  async get(matchId: string): Promise<StoredMatch | null> {
    const entry = this.matchCache.get(matchId);
    if (!entry) {
      return null;
    }

    if (entry.expiresAt < Date.now()) {
      this.matchCache.delete(matchId);
      this.connectionToMatchCache.delete(entry.match.connection_id);
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

    this.connectionToMatchCache.set(match.connection_id, matchId);
  }

  async delete(matchId: string): Promise<void> {
    const entry = this.matchCache.get(matchId);
    if (entry) {
      this.connectionToMatchCache.delete(entry.match.connection_id);
    }
    this.matchCache.delete(matchId);
  }

  async getByConnectionId(connectionId: string): Promise<StoredMatch | null> {
    const matchId = this.connectionToMatchCache.get(connectionId);
    if (!matchId) {
      return null;
    }
    return this.get(matchId);
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
