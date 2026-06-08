import { Hono } from "hono";
import type {
  ValidatorInitRequest,
  ValidatorInitResponse,
  ValidatorInitFromHistoryRequest,
  StoredMatch,
  StateHistorySnapshot,
  StateHistoryFile,
} from "../types";
import { getConfig } from "../config";
import { verifyNakamaSignature, generateConnectionId } from "../utils/crypto";
import type { MatchStateStore } from "../store/match-state";
import type { IHistoryStore } from "../store/history-store";
import { readFile } from "node:fs/promises";
import { join } from "node:path";

export function createMatchRoutes(store: MatchStateStore, historyStore: IHistoryStore) {
  const app = new Hono();

  app.post("/init", async (c) => {
    try {
      const body = (await c.req.json()) as ValidatorInitRequest;
      const { match_id, starting_state, player_id, signature } = body;

      if (!match_id || !starting_state || !player_id || !signature) {
        return c.json(
          {
            error: "VALIDATION_ERROR",
            message: "Missing required fields: match_id, starting_state, player_id, signature",
          },
          400,
        );
      }

      const config = getConfig();

      if (!config.devMode) {
        const isValid = verifyNakamaSignature(
          match_id,
          starting_state,
          player_id,
          signature,
          config.sharedSecret,
        );

        if (!isValid) {
          return c.json(
            {
              error: "INVALID_SIGNATURE",
              message: "Failed to verify Nakama signature",
            },
            401,
          );
        }
      } else {
        console.warn("⚠️  DEV MODE: Skipping Nakama signature verification");
      }

      const connection_id = generateConnectionId();
      const now = Date.now();
      const expires_at = now + config.connectionTokenTTL * 1000;

      const state_history = new Map<number, typeof starting_state>();
      state_history.set(starting_state.moveIndex, starting_state);

      const storedMatch: StoredMatch = {
        match_id,
        current_state: starting_state,
        connection_id,
        player_id,
        created_at: now,
        last_action_at: now,
        action_count: 0,
        state_history,
      };

      console.log(`Match initialized: ${match_id} for player ${player_id}`);
      console.log(`Starting state received:`, {
        tiles: starting_state.board.tiles.filter(t => !t.isEmpty),
        rngIndices: starting_state.rngIndices,
        gameStatus: starting_state.gameStatus,
        moveIndex: starting_state.moveIndex,
      });

      await store.set(match_id, storedMatch, config.matchSessionTTL);

      const response: ValidatorInitResponse = {
        connection_id,
        expires_at,
      };

      return c.json(response, 200);
    } catch (error) {
      console.error("Error initializing match:", error);
      return c.json(
        {
          error: "INTERNAL_ERROR",
          message: "Failed to initialize match",
        },
        500,
      );
    }
  });

  app.post("/init-from-history", async (c) => {
    try {
      const body = (await c.req.json()) as ValidatorInitFromHistoryRequest;
      const { history_file_id, history_data, start_from_index, player_id } = body;

      if (!player_id) {
        return c.json(
          {
            error: "VALIDATION_ERROR",
            message: "Missing required field: player_id",
          },
          400,
        );
      }

      if (!history_file_id && !history_data) {
        return c.json(
          {
            error: "VALIDATION_ERROR",
            message: "Either history_file_id or history_data must be provided",
          },
          400,
        );
      }

      let states: StateHistorySnapshot[];
      let match_id: string;

      if (history_file_id) {
        const statesFromStore = await historyStore.get(history_file_id);

        if (statesFromStore) {
          states = statesFromStore;
          match_id = `replay-${history_file_id}`;
          console.log(`Loading state history from store: ${history_file_id}`);
        } else {
          try {
            const fixturePath = join(process.cwd(), "..", "game", "fixtures", "history", `${history_file_id}.json`);
            const fileContents = await readFile(fixturePath, "utf-8");
            const historyFile: StateHistoryFile = JSON.parse(fileContents);

            states = historyFile.states;
            match_id = historyFile.match_id;

            console.log(`Loading state history from file: ${history_file_id}`);
            console.log(`Description: ${historyFile.description}`);
          } catch (error) {
            console.error("Error loading history:", error);
            return c.json(
              {
                error: "NOT_FOUND",
                message: `History not found in store or filesystem: ${history_file_id}`,
              },
              404,
            );
          }
        }
      } else if (history_data) {
        states = history_data;
        match_id = `replay-${Date.now()}`;

        console.log(`Loading state history from request data`);
      } else {
        return c.json(
          {
            error: "VALIDATION_ERROR",
            message: "Invalid history data",
          },
          400,
        );
      }

      if (!states || states.length === 0) {
        return c.json(
          {
            error: "VALIDATION_ERROR",
            message: "State history is empty",
          },
          400,
        );
      }

      const state_history = new Map(
        states.map(snapshot => [snapshot.moveIndex, snapshot.state])
      );

      const startIndex = start_from_index ?? states[states.length - 1].moveIndex;
      const currentState = state_history.get(startIndex);

      if (!currentState) {
        return c.json(
          {
            error: "VALIDATION_ERROR",
            message: `No state found at moveIndex ${startIndex}`,
          },
          400,
        );
      }

      const config = getConfig();
      const connection_id = generateConnectionId();
      const now = Date.now();
      const expires_at = now + config.connectionTokenTTL * 1000;

      const storedMatch: StoredMatch = {
        match_id,
        current_state: currentState,
        connection_id,
        player_id,
        created_at: now,
        last_action_at: now,
        action_count: 0,
        state_history,
      };

      console.log(`Match initialized from history: ${match_id} for player ${player_id}`);
      console.log(`Loaded ${states.length} states, starting from moveIndex ${startIndex}`);
      console.log(`Current state:`, {
        tiles: currentState.board.tiles.filter(t => !t.isEmpty),
        rngIndices: currentState.rngIndices,
        gameStatus: currentState.gameStatus,
        moveIndex: currentState.moveIndex,
      });

      await store.set(match_id, storedMatch, config.matchSessionTTL);

      const response: ValidatorInitResponse = {
        connection_id,
        expires_at,
      };

      return c.json(response, 200);
    } catch (error) {
      console.error("Error initializing match from history:", error);
      return c.json(
        {
          error: "INTERNAL_ERROR",
          message: "Failed to initialize match from history",
        },
        500,
      );
    }
  });

  app.post("/save-history", async (c) => {
    try {
      const body = await c.req.json();
      const states = body.states as StateHistorySnapshot[];

      if (!states || !Array.isArray(states) || states.length === 0) {
        return c.json(
          {
            error: "VALIDATION_ERROR",
            message: "Invalid or empty states array",
          },
          400,
        );
      }

      const config = getConfig();
      const historyId = await historyStore.save(states, config.matchSessionTTL);

      console.log(`Saved history: ${historyId} (${states.length} states)`);

      return c.json({
        history_id: historyId,
        state_count: states.length,
      }, 200);
    } catch (error) {
      console.error("Error saving history:", error);
      return c.json(
        {
          error: "INTERNAL_ERROR",
          message: "Failed to save history",
        },
        500,
      );
    }
  });

  app.get("/load-history/:id", async (c) => {
    try {
      const historyId = c.req.param("id");

      if (!historyId) {
        return c.json(
          {
            error: "VALIDATION_ERROR",
            message: "History ID is required",
          },
          400,
        );
      }

      const states = await historyStore.get(historyId);

      if (!states) {
        return c.json(
          {
            error: "NOT_FOUND",
            message: `History ${historyId} not found or expired`,
          },
          404,
        );
      }

      return c.json({
        history_id: historyId,
        state_count: states.length,
        states,
      }, 200);
    } catch (error) {
      console.error("Error loading history:", error);
      return c.json(
        {
          error: "INTERNAL_ERROR",
          message: "Failed to load history",
        },
        500,
      );
    }
  });

  return app;
}
