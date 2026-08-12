/**
 * Persistent error retry
 *
 * When a turn ends in stopReason=error (including errors Pi does not classify
 * as retryable, e.g. Kie "Unexpected end of JSON input"), keep re-kicking the
 * agent after a fixed 2s cooldown until a non-error turn completes or the user
 * aborts / disables the extension.
 *
 * Runs *after* Pi's built-in retry budget is exhausted (hooks agent_settled).
 *
 * Commands:
 *   /persistent-retry          status
 *   /persistent-retry on|off   enable / disable for this process
 *   /persistent-retry reset    clear attempt counter + pending timer
 */
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { Text } from "@earendil-works/pi-tui";

const CUSTOM_TYPE = "persistent-error-retry";
const COOLDOWN_MS = 2000;

/** Hard failures where infinite retry only wastes money / loops forever. */
const FATAL_ERROR_RE =
	/insufficient_quota|out of budget|quota exceeded|billing|invalid api key|incorrect api key|authentication|unauthorized|permission denied|model_not_found|does not exist|context.?length|maximum context|prompt is too long|GoUsageLimitError|FreeUsageLimitError|Monthly usage limit reached/i;

interface LastError {
	message: string;
	model?: string;
	provider?: string;
}

function shortError(msg: string, max = 100): string {
	const oneLine = msg.replace(/\s+/g, " ").trim();
	return oneLine.length <= max ? oneLine : `${oneLine.slice(0, max - 1)}…`;
}

function buildContinuePrompt(err: LastError, attempt: number): string {
	const where = [err.provider, err.model].filter(Boolean).join("/");
	return [
		"[persistent-error-retry] The previous assistant turn failed with a provider/system error before completion.",
		where ? `Model: ${where}` : null,
		`Attempt: ${attempt}`,
		`Error: ${shortError(err.message, 240)}`,
		"",
		"Resume the unfinished work immediately from the last successful step.",
		"Do not restart the entire task from scratch unless the partial result is unusable.",
		"Do not apologize. Continue.",
	]
		.filter((line) => line !== null)
		.join("\n");
}

function isFatalError(message: string): boolean {
	return FATAL_ERROR_RE.test(message);
}

export default function (pi: ExtensionAPI) {
	let enabled = true;
	let attempts = 0;
	/** Attempts completed before the run that finally succeeded (for recovery toast). */
	let recoveredAttempts = 0;
	let lastError: LastError | null = null;
	let pendingTimer: ReturnType<typeof setTimeout> | null = null;
	/** True while we are waiting on a cooldown or have just fired a resume. */
	let retryInFlight = false;

	function clearPendingTimer(): void {
		if (pendingTimer !== null) {
			clearTimeout(pendingTimer);
			pendingTimer = null;
		}
	}

	function statusText(): string {
		const state = enabled ? "on" : "off";
		const err = lastError ? shortError(lastError.message, 80) : "(none)";
		const pending = pendingTimer !== null ? "yes" : "no";
		return `persistent-retry: ${state} | attempts=${attempts} | pending=${pending} | lastError=${err}`;
	}

	function scheduleRetry(ctx: ExtensionContext): void {
		if (!enabled || !lastError || pendingTimer !== null) return;
		if (isFatalError(lastError.message)) {
			ctx.ui.notify(
				`persistent-retry: giving up (non-recoverable): ${shortError(lastError.message)}`,
				"error",
			);
			lastError = null;
			attempts = 0;
			retryInFlight = false;
			return;
		}
		if (ctx.hasPendingMessages()) return;

		const err = lastError;
		const nextAttempt = attempts + 1;
		retryInFlight = true;

		ctx.ui.notify(
			`persistent-retry: #${nextAttempt} in ${COOLDOWN_MS / 1000}s — ${shortError(err.message)}`,
			"warning",
		);

		pendingTimer = setTimeout(() => {
			pendingTimer = null;
			if (!enabled || !lastError) {
				retryInFlight = false;
				return;
			}

			attempts = nextAttempt;
			try {
				pi.sendMessage(
					{
						customType: CUSTOM_TYPE,
						content: buildContinuePrompt(err, attempts),
						display: true,
						details: {
							attempt: attempts,
							error: err.message,
							model: err.model,
							provider: err.provider,
							cooldownMs: COOLDOWN_MS,
						},
					},
					{ deliverAs: "followUp", triggerTurn: true },
				);
			} catch (e) {
				retryInFlight = false;
				const msg = e instanceof Error ? e.message : String(e);
				// Best-effort UI; extension errors must not throw out of timer.
				try {
					ctx.ui.notify(`persistent-retry: failed to resume: ${msg}`, "error");
				} catch {
					/* ignore */
				}
			}
		}, COOLDOWN_MS);

		if (typeof pendingTimer.unref === "function") {
			pendingTimer.unref();
		}
	}

	pi.registerMessageRenderer(CUSTOM_TYPE, (message, options, theme) => {
		const attempt =
			typeof message.details === "object" &&
			message.details &&
			"attempt" in message.details
				? Number((message.details as { attempt?: number }).attempt) || "?"
				: "?";
		const err =
			typeof message.details === "object" &&
			message.details &&
			"error" in message.details
				? shortError(String((message.details as { error?: string }).error ?? ""), 120)
				: "";
		const line = theme.fg(
			"warning",
			`⟳ persistent-retry #${attempt}${err ? ` — ${err}` : ""}`,
		);
		return new Text(line, options.outputPad ?? 0, 0);
	});

	pi.registerCommand("persistent-retry", {
		description:
			"Persistent auto-retry on system/provider errors (on|off|reset|status)",
		handler: async (args, ctx) => {
			const cmd = (args ?? "").trim().toLowerCase();
			if (!cmd || cmd === "status") {
				ctx.ui.notify(statusText(), "info");
				return;
			}
			if (cmd === "on" || cmd === "enable") {
				enabled = true;
				ctx.ui.notify("persistent-retry: enabled", "info");
				// If we already settled on an error, kick immediately.
				if (lastError && ctx.isIdle()) {
					scheduleRetry(ctx);
				}
				return;
			}
			if (cmd === "off" || cmd === "disable") {
				enabled = false;
				clearPendingTimer();
				retryInFlight = false;
				ctx.ui.notify("persistent-retry: disabled", "info");
				return;
			}
			if (cmd === "reset") {
				clearPendingTimer();
				attempts = 0;
				recoveredAttempts = 0;
				lastError = null;
				retryInFlight = false;
				ctx.ui.notify("persistent-retry: reset", "info");
				return;
			}
			ctx.ui.notify(
				"Usage: /persistent-retry [status|on|off|reset]",
				"warning",
			);
		},
	});

	pi.on("message_end", (event) => {
		const msg = event.message as {
			role?: string;
			stopReason?: string;
			errorMessage?: string;
			model?: string;
			provider?: string;
		};
		if (msg.role !== "assistant") return;

		if (msg.stopReason === "error") {
			lastError = {
				message: msg.errorMessage || "Unknown error",
				model: msg.model,
				provider: msg.provider,
			};
			return;
		}

		// User abort: stop the loop.
		if (msg.stopReason === "aborted") {
			clearPendingTimer();
			lastError = null;
			attempts = 0;
			recoveredAttempts = 0;
			retryInFlight = false;
			return;
		}

		// Any successful / normal completion ends the retry loop.
		clearPendingTimer();
		lastError = null;
		if (retryInFlight && attempts > 0) {
			recoveredAttempts = attempts;
		}
		attempts = 0;
		retryInFlight = false;
	});

	pi.on("agent_start", () => {
		// A new run started (including our own resume). Drop any stray timer.
		clearPendingTimer();
	});

	pi.on("agent_settled", (_event, ctx) => {
		if (!enabled) return;
		if (!lastError) {
			if (recoveredAttempts > 0) {
				ctx.ui.notify(
					`persistent-retry: recovered after ${recoveredAttempts} resume(s)`,
					"info",
				);
				recoveredAttempts = 0;
			}
			return;
		}
		scheduleRetry(ctx);
	});
}
