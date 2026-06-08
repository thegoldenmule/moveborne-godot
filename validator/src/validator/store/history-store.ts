import type { StateHistorySnapshot, StateHistoryFile } from "../types";
import { writeFile, readFile, readdir, unlink, mkdir } from "node:fs/promises";
import { join } from "node:path";
import { existsSync } from "node:fs";

interface SavedHistory {
  id: string;
  states: StateHistorySnapshot[];
  created_at: number;
  expires_at: number;
}

export interface IHistoryStore {
  save(states: StateHistorySnapshot[], ttlSeconds: number): Promise<string>;
  get(id: string): Promise<StateHistorySnapshot[] | null>;
  delete(id: string): Promise<void>;
  cleanup(): Promise<void>;
}

export class InMemoryHistoryStore implements IHistoryStore {
  private histories: Map<string, SavedHistory> = new Map();

  async save(states: StateHistorySnapshot[], ttlSeconds: number): Promise<string> {
    const id = this.generateId();
    const now = Date.now();

    const history: SavedHistory = {
      id,
      states,
      created_at: now,
      expires_at: now + ttlSeconds * 1000,
    };

    this.histories.set(id, history);

    console.log(`Saved history: ${id} (${states.length} states, expires in ${ttlSeconds}s)`);

    return id;
  }

  async get(id: string): Promise<StateHistorySnapshot[] | null> {
    const history = this.histories.get(id);

    if (!history) {
      return null;
    }

    if (Date.now() > history.expires_at) {
      this.histories.delete(id);
      console.log(`History expired and deleted: ${id}`);
      return null;
    }

    return history.states;
  }

  async delete(id: string): Promise<void> {
    this.histories.delete(id);
  }

  async cleanup(): Promise<void> {
    const now = Date.now();
    const expiredIds: string[] = [];

    for (const [id, history] of this.histories.entries()) {
      if (now > history.expires_at) {
        expiredIds.push(id);
      }
    }

    for (const id of expiredIds) {
      this.histories.delete(id);
    }

    if (expiredIds.length > 0) {
      console.log(`Cleaned up ${expiredIds.length} expired histories`);
    }
  }

  private generateId(): string {
    const timestamp = Date.now().toString(36);
    const random = Math.random().toString(36).substring(2, 9);
    return `${timestamp}-${random}`;
  }
}

export class FileSystemHistoryStore implements IHistoryStore {
  private dataPath: string;

  constructor(dataPath?: string) {
    this.dataPath = dataPath || join(process.cwd(), "..", "..", "data", "matches");
  }

  async save(states: StateHistorySnapshot[], ttlSeconds: number): Promise<string> {
    const id = this.generateId();

    if (!existsSync(this.dataPath)) {
      await mkdir(this.dataPath, { recursive: true });
    }

    const firstState = states[0]?.state;
    const historyFile: StateHistoryFile = {
      id,
      description: `Auto-saved history from validator (${states.length} states)`,
      created_at: new Date().toISOString(),
      match_id: `shared-${id}`,
      player_id: "shared",
      states,
    };

    const filePath = join(this.dataPath, `${id}.json`);
    await writeFile(filePath, JSON.stringify(historyFile, null, 2), "utf-8");

    console.log(`Saved history to disk: ${id} (${states.length} states)`);
    console.log(`File: ${filePath}`);

    return id;
  }

  async get(id: string): Promise<StateHistorySnapshot[] | null> {
    const filePath = join(this.dataPath, `${id}.json`);

    try {
      const fileContents = await readFile(filePath, "utf-8");
      const historyFile: StateHistoryFile = JSON.parse(fileContents);
      return historyFile.states;
    } catch (error) {
      return null;
    }
  }

  async delete(id: string): Promise<void> {
    const filePath = join(this.dataPath, `${id}.json`);

    try {
      await unlink(filePath);
      console.log(`Deleted history file: ${id}`);
    } catch (error) {
      console.error(`Failed to delete history file ${id}:`, error);
    }
  }

  async cleanup(): Promise<void> {
    return;
  }

  private generateId(): string {
    const timestamp = Date.now().toString(36);
    const random = Math.random().toString(36).substring(2, 9);
    return `${timestamp}-${random}`;
  }
}
