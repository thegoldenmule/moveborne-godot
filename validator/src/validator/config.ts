import type { ValidatorConfig } from "./types";

function getEnvVar(name: string, defaultValue?: string): string {
  const value = process.env[name] || defaultValue;
  if (!value) {
    throw new Error(`Missing required environment variable: ${name}`);
  }
  return value;
}

function getEnvNumber(name: string, defaultValue: number): number {
  const value = process.env[name];
  if (!value) {
    return defaultValue;
  }
  const parsed = parseInt(value, 10);
  if (isNaN(parsed)) {
    throw new Error(`Invalid number for environment variable ${name}: ${value}`);
  }
  return parsed;
}

export function loadConfig(): ValidatorConfig {
  return {
    sharedSecret: getEnvVar("VALIDATOR_SHARED_SECRET"),
    connectionTokenTTL: getEnvNumber("CONNECTION_TOKEN_TTL", 300),
    matchSessionTTL: getEnvNumber("MATCH_SESSION_TTL", 3600),
    port: getEnvNumber("PORT", 3000),
    snapserGatewayUrl: getEnvVar("SNAPSER_GATEWAY_URL", "https://gateway.snapser.com/c4n1awfs"),
    snapserApiKey: process.env.SNAPSER_API_KEY || undefined,
    // Platform-injected inside the snapend; absent in local dev.
    inventoryInternalUrl: process.env.SNAPEND_INVENTORY_HTTP_URL || undefined,
    internalHeader: process.env.SNAPEND_INTERNAL_HEADER || undefined,
  };
}

let cachedConfig: ValidatorConfig | null = null;

export function getConfig(): ValidatorConfig {
  if (!cachedConfig) {
    cachedConfig = loadConfig();
  }
  return cachedConfig;
}
