import { StreamableHTTPTransport } from "@hono/mcp";
import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { ListToolsRequestSchema, CallToolRequestSchema } from "@modelcontextprotocol/sdk/types.js";
import { Hono } from "hono";
import type { MatchStateStore } from "./store/match-state";
import { executeAction, RandomGenerator, computeStateHash, OperationType } from "@spyre-io/moveborne-logic";
import type { GameAction } from "./types";

export function createValidatorMCP(store: MatchStateStore) {
  const app = new Hono();
  const transport = new StreamableHTTPTransport();

  const server = new Server(
    {
      name: "moveborne-validator",
      version: "0.1.0",
    },
    {
      capabilities: {
        tools: {},
      },
    }
  );

  server.setRequestHandler(ListToolsRequestSchema, async () => ({
      tools: [
        {
          name: "get_match_state",
          description: "Get the current state for a match",
          inputSchema: {
            type: "object",
            properties: {
              match_id: {
                type: "string",
                description: "The match ID to inspect",
              },
            },
            required: ["match_id"],
          },
        },
        {
          name: "list_matches",
          description: "List all active matches in the validator store",
          inputSchema: {
            type: "object",
            properties: {},
          },
        },
        {
          name: "simulate_action",
          description: "Simulate an action without applying it to see the result",
          inputSchema: {
            type: "object",
            properties: {
              match_id: {
                type: "string",
                description: "The match ID to simulate the action for",
              },
              action_type: {
                type: "string",
                description: "The action type (SWIPE or PLAY_CARD)",
              },
              action_payload: {
                type: "string",
                description: 'JSON string of the action payload (e.g., {"direction":"up"} for swipe)',
              },
            },
            required: ["match_id", "action_type", "action_payload"],
          },
        },
        {
          name: "clear_match",
          description: "Remove a match from the validator store",
          inputSchema: {
            type: "object",
            properties: {
              match_id: {
                type: "string",
                description: "The match ID to remove",
              },
            },
            required: ["match_id"],
          },
        },
        {
          name: "get_state_history",
          description: "Get the full state history for a match (moveIndex -> state mapping)",
          inputSchema: {
            type: "object",
            properties: {
              match_id: {
                type: "string",
                description: "The match ID to get history for",
              },
            },
            required: ["match_id"],
          },
        },
      ],
    }));

  server.setRequestHandler(CallToolRequestSchema, async (request) => {
      const { name, arguments: args } = request.params;

      if (!args) {
        return {
          content: [
            {
              type: "text",
              text: JSON.stringify({
                error: "NO_ARGUMENTS",
                message: "No arguments provided",
              }, null, 2),
            },
          ],
        };
      }

      if (name === "get_match_state") {
        const match_id = args.match_id as string;
        const match = await store.get(match_id);

        if (!match) {
          return {
            content: [
              {
                type: "text",
                text: JSON.stringify({
                  error: "MATCH_NOT_FOUND",
                  message: `Match ${match_id} not found in store`,
                }, null, 2),
              },
            ],
          };
        }

        const result = {
          match_id: match.match_id,
          player_id: match.player_id,
          action_count: match.action_count,
          mode: match.mode,
          rewards_granted: match.rewards_granted,
          created_at: new Date(match.created_at).toISOString(),
          last_action_at: new Date(match.last_action_at).toISOString(),
          current_state: {
            moveIndex: match.current_state.moveIndex,
            score: match.current_state.score,
            shards: match.current_state.shards,
            combo: match.current_state.combo,
            comboMultiplier: match.current_state.comboMultiplier,
            tiles: match.current_state.board.tiles.filter(t => !t.isEmpty).map(t => ({
              row: t.row,
              col: t.col,
              value: t.value,
              status: t.status,
            })),
            rngIndices: match.current_state.rngIndices,
            randomSeeds: match.current_state.randomSeeds,
            hand: match.current_state.hand,
            deck: match.current_state.deck,
          },
          state_hash: computeStateHash(match.current_state),
        };

        return {
          content: [
            {
              type: "text",
              text: JSON.stringify(result, null, 2),
            },
          ],
        };
      }

      if (name === "list_matches") {
        const allMatches = await store.getAll();

        const matchList = allMatches.map(match => ({
          match_id: match.match_id,
          player_id: match.player_id,
          action_count: match.action_count,
          moveIndex: match.current_state.moveIndex,
          mode: match.mode,
          rewards_granted: match.rewards_granted,
          created_at: new Date(match.created_at).toISOString(),
          last_action_at: new Date(match.last_action_at).toISOString(),
        }));

        return {
          content: [
            {
              type: "text",
              text: JSON.stringify({
                total: matchList.length,
                matches: matchList,
              }, null, 2),
            },
          ],
        };
      }

      if (name === "simulate_action") {
        const match_id = args.match_id as string;
        const action_type = args.action_type as OperationType;
        const action_payload = args.action_payload as string;

        const match = await store.get(match_id);

        if (!match) {
          return {
            content: [
              {
                type: "text",
                text: JSON.stringify({
                  error: "MATCH_NOT_FOUND",
                  message: `Match ${match_id} not found`,
                }, null, 2),
              },
            ],
          };
        }

        try {
          const payload = JSON.parse(action_payload);
          const action: GameAction = {
            type: action_type,
            payload,
          };

          const rng = new RandomGenerator(
            match.current_state.randomSeeds,
            match.current_state.rngIndices,
          );

          const executionResult = executeAction(match.current_state, action, rng);

          if (!executionResult.success) {
            return {
              content: [
                {
                  type: "text",
                  text: JSON.stringify({
                    success: false,
                    error: executionResult.error,
                  }, null, 2),
                },
              ],
            };
          }

          let newState = executionResult.newState;
          newState.rngIndices = rng.getIndices();

          const result = {
            success: true,
            current_state_hash: computeStateHash(match.current_state),
            new_state_hash: computeStateHash(newState),
            score_added: executionResult.scoreAdded || 0,
            shards_added: executionResult.shardsAdded || 0,
            tiles_changed: newState.board.tiles.filter(t => !t.isEmpty).length !==
              match.current_state.board.tiles.filter(t => !t.isEmpty).length,
            new_rng_indices: newState.rngIndices,
          };

          return {
            content: [
              {
                type: "text",
                text: JSON.stringify(result, null, 2),
              },
            ],
          };
        } catch (error) {
          return {
            content: [
              {
                type: "text",
                text: JSON.stringify({
                  error: "INVALID_ACTION",
                  message: error instanceof Error ? error.message : String(error),
                }, null, 2),
              },
            ],
          };
        }
      }

      if (name === "clear_match") {
        const match_id = args.match_id as string;
        const match = await store.get(match_id);

        if (!match) {
          return {
            content: [
              {
                type: "text",
                text: JSON.stringify({
                  error: "MATCH_NOT_FOUND",
                  message: `Match ${match_id} not found`,
                }, null, 2),
              },
            ],
          };
        }

        await store.delete(match_id);

        return {
          content: [
            {
              type: "text",
              text: JSON.stringify({
                success: true,
                message: `Match ${match_id} removed from store`,
              }, null, 2),
            },
          ],
        };
      }

      if (name === "get_state_history") {
        const match_id = args.match_id as string;
        const match = await store.get(match_id);

        if (!match) {
          return {
            content: [
              {
                type: "text",
                text: JSON.stringify({
                  error: "MATCH_NOT_FOUND",
                  message: `Match ${match_id} not found`,
                }, null, 2),
              },
            ],
          };
        }

        const historyArray = Array.from(match.state_history.entries())
          .sort((a, b) => a[0] - b[0])
          .map(([moveIndex, state]) => ({
            moveIndex,
            score: state.score,
            shards: state.shards,
            combo: state.combo,
            comboMultiplier: state.comboMultiplier,
            tiles: state.board.tiles.filter(t => !t.isEmpty).map(t => ({
              row: t.row,
              col: t.col,
              value: t.value,
              status: t.status,
            })),
            rngIndices: state.rngIndices,
            randomSeeds: state.randomSeeds,
            hand: state.hand,
            deck: state.deck,
            state_hash: computeStateHash(state),
          }));

        return {
          content: [
            {
              type: "text",
              text: JSON.stringify({
                match_id: match.match_id,
                player_id: match.player_id,
                total_states: historyArray.length,
                history: historyArray,
              }, null, 2),
            },
          ],
        };
      }

      return {
        content: [
          {
            type: "text",
            text: JSON.stringify({
              error: "UNKNOWN_TOOL",
              message: `Unknown tool: ${name}`,
            }, null, 2),
          },
        ],
      };
    });

  server.connect(transport);

  app.get("/*", async (c) => {
    return await transport.handleRequest(c);
  });

  app.post("/*", async (c) => {
    const body = await c.req.json();
    return await transport.handleRequest(c, body);
  });

  app.delete("/*", async (c) => {
    return await transport.handleRequest(c);
  });

  return app;
}
