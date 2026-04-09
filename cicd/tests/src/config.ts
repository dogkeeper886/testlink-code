/**
 * Project configuration for the test framework.
 * 
 * Customize this file for your project's needs.
 */

/**
 * Available test suites - extend this for your project.
 */
export const SUITES = ['build', 'integration', 'e2e'] as const;
export type Suite = typeof SUITES[number];

/**
 * Project configuration.
 */
export const CONFIG = {
  // Project identification
  projectName: 'testlink-code',
  
  // Session file prefix for log collection
  sessionPrefix: 'testlink-code-session',
  
  // Default timeouts (in milliseconds)
  defaultTimeout: 120000,
  defaultStepTimeout: 60000,
  
  // LLM Judge defaults
  llm: {
    defaultUrl: 'http://localhost:11434',
    defaultModel: 'llama3:8b',
    timeout: 300000,
    stdoutLimit: 1000,
    stderrLimit: 500,
    logsLimit: 3000,
  },
  
  // Log collection settings
  logs: {
    cleanupAge: 24 * 60 * 60 * 1000, // 24 hours
    maxBuffer: 50 * 1024 * 1024, // 50MB
  },

  // MCP client settings (for projects using mcp-client.ts)
  mcp: {
    serverCommand: 'node dist/mcpServer.js', // Override via MCP_SERVER_COMMAND env var
  },
};

/**
 * Error patterns to detect in logs.
 * The Simple Judge will fail tests if any of these patterns are found.
 * 
 * Customize for your project's specific error indicators.
 */
export const ERROR_PATTERNS: RegExp[] = [
  /\berror\b/i,
  /\bfailed\b/i,
  /\bexception\b/i,
  /\bpanic\b/i,
  /segmentation fault/i,
  /out of memory/i,
  /OOM/,
];

/**
 * Patterns that indicate a test should NOT be failed.
 * Use these to exclude false positives from ERROR_PATTERNS.
 */
export const ERROR_EXCLUSIONS: RegExp[] = [
  /error.*handled/i,
  /expected.*error/i,
  /No syntax errors detected/i,
  /error_reporting/i,
  /error_handler/i,
  /error\.class\.php/i,
  /faultCode|faultString/i,  // XML-RPC expected response fields
];
