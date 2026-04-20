/**
 * LLM Judge - Semantic analysis of test results using Ollama.
 *
 * Uses a language model to evaluate test execution logs against criteria.
 * Catches silent failures that exit code checking misses.
 *
 * Judges one test at a time with structured JSON prompts and Ollama JSON mode
 * for reliable parsing. Includes observability logging for debugging CI failures.
 */

import axios from 'axios';
import { TestResult, Judgment } from '../types.js';
import { CONFIG } from '../config.js';

export class LLMJudge {
  private ollamaUrl: string;
  private model: string;

  constructor(
    ollamaUrl: string = CONFIG.llm.defaultUrl,
    model: string = CONFIG.llm.defaultModel
  ) {
    this.ollamaUrl = ollamaUrl;
    this.model = model;
  }

  async isAvailable(): Promise<boolean> {
    try {
      const response = await axios.get(`${this.ollamaUrl}/api/tags`, {
        timeout: 5000,
      });
      return response.status === 200;
    } catch {
      return false;
    }
  }

  /**
   * Truncate a string to a maximum length.
   */
  private truncate(text: string, limit: number): string {
    if (text.length <= limit) return text;
    return text.substring(0, limit) + '... (truncated)';
  }

  /**
   * Build the system + user messages for LLM evaluation of a single test.
   *
   * Per-test framing comes from the YAML, not from this file:
   *   - objective    — what the test proves and why it matters
   *   - judgeContext — what evidence the steps produce and what silent
   *                    failures look like in this domain
   *   - criteria     — pass/fail conditions
   * The system message defines the role, the mission ("hunt silent failures"),
   * and the output schema. It does not encode mechanical rules like "exit
   * code 0 = pass" — those are the test author's call, expressed in the
   * judgeContext / criteria.
   */
  private buildPrompt(result: TestResult): { system: string; user: string } {
    const r = result;

    const system = [
      `# ROLE`,
      `You are a senior QA engineer reviewing one automated test run for ${CONFIG.projectName}.`,
      ``,
      `# MISSION`,
      `Decide whether the test PASSED or FAILED. The author of the test has provided:`,
      `- OBJECTIVE: what the test is trying to prove and why it matters.`,
      `- CONTEXT:   what each step is supposed to produce, and what silent failures look like in this domain.`,
      `- CRITERIA:  the pass/fail conditions for this specific test.`,
      `- OBSERVATIONS: what actually happened (commands, exit codes, stdout, stderr, container logs).`,
      `Read the OBJECTIVE and CONTEXT first to understand what you are looking at.`,
      `Then read the CRITERIA to know what counts as success.`,
      `Then read the OBSERVATIONS and decide whether the criteria were met.`,
      `Apply judgment, not pattern matching: a step that exits 0 can still be a silent failure if the output shows it skipped its real work; a step that exits non-zero can be a pass if the criteria expected an error.`,
      ``,
      `# OUTPUT`,
      `Respond with exactly one JSON object — no prose, no code fences, no thinking tokens. Schema:`,
      `{"testId": string, "pass": boolean, "reason": string, "evidence": string}`,
      `- testId   : echo the test id from the OBJECTIVE block verbatim.`,
      `- pass     : true if criteria met, false otherwise. Must agree with the reason — if your reason describes success, pass must be true.`,
      `- reason   : one short sentence (<= 25 words) grounded in the observations.`,
      `- evidence : a short quote (<= 120 characters) copied verbatim from OBSERVATIONS — a single field value, not a step block. Do NOT escape newlines or embed multi-line XML; pick the shortest substring that proves your verdict. Empty string ("") is acceptable if no single short quote is representative.`,
      ``,
      `Example pass : {"testId":"TC-X-001","pass":true,"reason":"Login page returned the expected 'Login' marker.","evidence":"STDOUT: Login"}`,
      `Example fail : {"testId":"TC-X-002","pass":false,"reason":"Build exited 0 but skipped composer install.","evidence":"CACHED [stage 3/5]"}`,
    ].join('\n');

    const stepsBlock = r.steps.map((step, j) => {
      const stepDef = r.testCase.steps[j];
      const limit = stepDef?.timeout || r.testCase.timeout;
      const stdout = this.truncate(step.stdout, CONFIG.llm.stdoutLimit).trim() || '(empty)';
      const stderr = this.truncate(step.stderr, CONFIG.llm.stderrLimit).trim() || '(empty)';
      return [
        `Step ${j + 1}: ${step.name}`,
        `  command   : ${step.command.trim().split('\n').join(' \\n ')}`,
        `  exit_code : ${step.exitCode}`,
        `  duration  : ${step.duration}ms (timeout ${limit}ms)`,
        `  stdout    : ${stdout}`,
        `  stderr    : ${stderr}`,
      ].join('\n');
    }).join('\n\n');

    const logs = this.truncate(r.logs, CONFIG.llm.logsLimit).trim() || '(none)';
    const objective = (r.testCase.objective || r.testCase.goal || r.testCase.name).trim();
    const judgeContext = (r.testCase.judgeContext || '').trim() ||
      `(none provided — read the criteria carefully and watch for silent failures: steps that exited 0 but did not actually achieve the test's objective.)`;
    const criteria = (r.testCase.criteria || '(none provided)').trim();

    const user = [
      `# OBJECTIVE`,
      `Test id   : ${r.testCase.id}`,
      `Suite     : ${r.testCase.suite}`,
      `Name      : ${r.testCase.name}`,
      ``,
      objective,
      ``,
      `# CONTEXT`,
      judgeContext,
      ``,
      `# CRITERIA`,
      criteria,
      ``,
      `# OBSERVATIONS`,
      `Total duration: ${r.totalDuration}ms (test timeout ${r.testCase.timeout}ms)`,
      ``,
      stepsBlock,
      ``,
      `## Container logs`,
      logs,
      ``,
      `# VERDICT`,
      `Return the JSON object specified in the system message. Use testId="${r.testCase.id}".`,
    ].join('\n');

    const totalStdout = r.steps.reduce((sum, s) => sum + s.stdout.length, 0);
    const totalStderr = r.steps.reduce((sum, s) => sum + s.stderr.length, 0);
    process.stderr.write(`  [LLM] Prompt for ${r.testCase.id}: logs ${r.logs.length} chars, stdout ${totalStdout} chars, stderr ${totalStderr} chars\n`);
    process.stderr.write(`  [LLM] Prompt size: system ${system.length} + user ${user.length} = ${system.length + user.length} chars\n`);

    return { system, user };
  }

  /**
   * Judge a single test result.
   */
  private async judgeOne(result: TestResult): Promise<Judgment> {
    const { system, user } = this.buildPrompt(result);
    const testId = result.testCase.id;

    const response = await axios.post(
      `${this.ollamaUrl}/api/chat`,
      {
        model: this.model,
        messages: [
          { role: 'system', content: system },
          { role: 'user', content: user },
        ],
        stream: false,
        format: 'json',
        options: {
          temperature: 0.1,
          // Default context is 4096 tokens — our multi-step prompts can
          // hit ~5000-7000 and Ollama silently truncates the END of the
          // prompt (which is where OBSERVATIONS live). 8192 fits every
          // current test with headroom; raise if logsLimit/stdoutLimit grow.
          num_ctx: 8192,
          // Output cap: a typical verdict is 50-200 tokens, but FAIL
          // verdicts may quote 5-10 lines of evidence. 512 covers honest
          // verbosity with headroom; well below "the model went rogue".
          num_predict: 512,
        },
      },
      {
        timeout: CONFIG.llm.timeout,
      }
    );

    const responseText = response.data.message?.content ?? '';
    const promptTokens = response.data.prompt_eval_count ?? '?';
    const responseTokens = response.data.eval_count ?? '?';
    process.stderr.write(`  [LLM] Tokens for ${testId}: prompt=${promptTokens}, response=${responseTokens}\n`);

    // Handle empty response
    if (!responseText) {
      process.stderr.write(`  [LLM] WARNING: Empty response for ${testId}\n`);
      return {
        testId,
        pass: false,
        reason: 'LLM returned empty response',
      };
    }

    process.stderr.write(`  [LLM] Raw response for ${testId} (${responseText.length} chars): ${responseText.substring(0, 500)}\n`);

    try {
      const judgment = JSON.parse(responseText) as Judgment;

      // Validate testId matches
      if (judgment.testId !== testId) {
        process.stderr.write(`  [LLM] WARNING: Response testId "${judgment.testId}" doesn't match expected "${testId}"\n`);
        judgment.testId = testId;
      }

      // Coerce string "true"/"false" to boolean (LLMs often return strings)
      if (typeof judgment.pass === 'string') {
        judgment.pass = (judgment.pass as unknown as string).toLowerCase() === 'true';
      }

      // Validate required fields
      if (typeof judgment.pass !== 'boolean') {
        process.stderr.write(`  [LLM] WARNING: Response missing "pass" field for ${testId}\n`);
        return {
          testId,
          pass: false,
          reason: `LLM response missing "pass" field: ${responseText.substring(0, 200)}`,
        };
      }

      if (!judgment.reason) {
        judgment.reason = judgment.pass ? 'Passed (no reason provided)' : 'Failed (no reason provided)';
      }

      // Post-process: evidence grounding + reason/pass consistency checks.
      // These don't override the verdict — they annotate it so downstream
      // reporting and human triage can spot suspect verdicts.
      this.annotateVerdict(judgment, result);

      return judgment;
    } catch {
      process.stderr.write(`  [LLM] WARNING: Failed to parse JSON for ${testId}\n`);
      process.stderr.write(`  [LLM] Full response: ${responseText}\n`);
      return {
        testId,
        pass: false,
        reason: `Failed to parse LLM response: ${responseText.substring(0, 200)}`,
      };
    }
  }

  /**
   * Annotate a parsed verdict with quality flags:
   *   - evidenceGrounded: the evidence field appears as a substring of
   *     the observations (stdout / stderr / container logs). If not,
   *     the model paraphrased a criterion or hallucinated.
   *   - reasonConsistent: the reason's sentiment matches the pass
   *     boolean. A success-shaped reason with pass:false (or the
   *     reverse) usually means JSON-mode commit order got ahead of
   *     the model's reasoning.
   * Neither flag overrides the verdict. They surface suspect verdicts
   * for human triage and for debugging the judge itself.
   */
  private annotateVerdict(judgment: Judgment, result: TestResult): void {
    // --- evidence grounding ---
    // The model often writes evidence as a short narration that includes
    // specific facts lifted from the observations ("Step 4 stderr contains
    // 'case-TC-X-17766...'"). Requiring the full evidence string to be a
    // verbatim substring is too strict — it flags legitimate citations
    // that wrap a real fact in scaffolding.
    //
    // Looser check: treat evidence as "grounded" if any meaningful-length
    // substring (>= 15 chars) of the normalised evidence appears in the
    // normalised observations. 15 chars is enough to filter out common
    // English words but catches entity names, run ids, SHA hashes, status
    // field fragments, etc. Pure fabrication rarely clears this bar.
    const evidence = (judgment.evidence || '').trim();
    if (evidence.length > 0) {
      const haystack = [
        ...result.steps.map((s) => s.stdout),
        ...result.steps.map((s) => s.stderr),
        result.logs,
      ].join('\n');

      const normalise = (s: string) =>
        s
          .replace(/\\[nrt]/g, ' ') // literal \n / \r / \t
          .replace(/\s+/g, ' ')     // actual whitespace
          .trim();

      const normEvidence = normalise(evidence);
      const normHaystack = normalise(haystack);
      const MIN = 15;
      let grounded = normEvidence.length < MIN
        ? normHaystack.includes(normEvidence)        // evidence is short — require full match
        : false;

      if (!grounded && normEvidence.length >= MIN) {
        // Slide a MIN-char window over the evidence; first hit wins.
        for (let i = 0; i <= normEvidence.length - MIN; i++) {
          if (normHaystack.includes(normEvidence.substring(i, i + MIN))) {
            grounded = true;
            break;
          }
        }
      }

      judgment.evidenceGrounded = grounded;

      if (!grounded) {
        process.stderr.write(
          `  [LLM] WARNING: Evidence not grounded for ${judgment.testId}: ${evidence.substring(0, 100)}\n`
        );
      }
    }

    // --- reason ↔ pass consistency ---
    const reason = (judgment.reason || '').toLowerCase();
    // Strong positive / negative markers. Intentionally narrow — false
    // positives on a noisy signal are worse than missed detections.
    const positiveMarkers = [
      'successfully', 'successful', 'as expected', 'correctly', 'works correctly',
      'meeting the criteria', 'met the criteria', 'passed all', 'all steps passed',
      'demonstrating the latest-wins', 'indicating the deletion was successful',
    ];
    const negativeMarkers = [
      'failed to', 'did not', 'does not', 'missing the expected', 'not contain',
      'violating', 'regression', 'silently failed', 'incorrect',
    ];
    const hasPositive = positiveMarkers.some((m) => reason.includes(m));
    const hasNegative = negativeMarkers.some((m) => reason.includes(m));

    // If both or neither, we can't tell — leave the flag undefined.
    if (hasPositive && !hasNegative) {
      judgment.reasonConsistent = judgment.pass === true;
    } else if (hasNegative && !hasPositive) {
      judgment.reasonConsistent = judgment.pass === false;
    }

    if (judgment.reasonConsistent === false) {
      process.stderr.write(
        `  [LLM] WARNING: Reason/pass mismatch for ${judgment.testId} (pass=${judgment.pass}, reason="${reason.substring(0, 100)}")\n`
      );
    }
  }

  /**
   * Judge all test results, one at a time.
   */
  async judgeResults(results: TestResult[]): Promise<Judgment[]> {
    const allJudgments: Judgment[] = [];

    for (let i = 0; i < results.length; i++) {
      const result = results[i];
      process.stderr.write(
        `  [LLM] Judging ${i + 1}/${results.length}: ${result.testCase.id}...\n`
      );

      try {
        const judgment = await this.judgeOne(result);
        allJudgments.push(judgment);
        process.stderr.write(`  [LLM] ${result.testCase.id}: ${judgment.pass ? 'PASS' : 'FAIL'} — ${judgment.reason}\n`);
      } catch (error) {
        process.stderr.write(`  [LLM] Failed to judge ${result.testCase.id}: ${error}\n`);
        allJudgments.push({
          testId: result.testCase.id,
          pass: false,
          reason: 'LLM judgment failed: ' + String(error),
        });
      }
    }

    return allJudgments;
  }

  async unloadModel(): Promise<void> {
    try {
      process.stderr.write(`  [LLM] Unloading judge model ${this.model}...\n`);
      // Use /api/generate (not /api/chat) for the unload — it doesn't need
      // conversational semantics and an empty messages[] is awkward.
      // keep_alive=0 is the documented Ollama unload pattern.
      await axios.post(
        `${this.ollamaUrl}/api/generate`,
        {
          model: this.model,
          keep_alive: 0,
        },
        {
          timeout: 30000,
        }
      );
      process.stderr.write(`  [LLM] Judge model unloaded.\n`);
    } catch {
      process.stderr.write(`  [LLM] Warning: Failed to unload judge model\n`);
    }
  }
}
