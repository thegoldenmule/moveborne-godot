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

function getEnvBoolean(name: string, defaultValue: boolean): boolean {
  const value = process.env[name];
  if (!value) {
    return defaultValue;
  }
  return value.toLowerCase() === "true" || value === "1";
}

export function loadConfig(): ValidatorConfig {
  return {
    sharedSecret: getEnvVar("VALIDATOR_SHARED_SECRET"),
    connectionTokenTTL: getEnvNumber("CONNECTION_TOKEN_TTL", 300),
    matchSessionTTL: getEnvNumber("MATCH_SESSION_TTL", 3600),
    port: getEnvNumber("PORT", 3000),
    devMode: getEnvBoolean("DEV_MODE", false),
  };
}

let cachedConfig: ValidatorConfig | null = null;

export function getConfig(): ValidatorConfig {
  if (!cachedConfig) {
    cachedConfig = loadConfig();
  }
  return cachedConfig;
}
