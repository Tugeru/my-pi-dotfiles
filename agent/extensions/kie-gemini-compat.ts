/**
 * Kie.ai native Gemini (google-generative-ai) compatibility for pi.
 *
 * Kie serves Gemini bodies at:
 *   POST https://api.kie.ai/gemini/v1/models/{id}:streamGenerateContent
 * with Authorization: Bearer <key> (not X-Goog-Api-Key alone).
 *
 * Two quirks vs Google's official API:
 * 1. SSE streams end with `data: [DONE]`, which @google/genai tries to JSON-parse.
 * 2. Hyphenated ids like `gemini-3-6-flash` do not match pi's built-in
 *    Gemini 3 Flash detector, so default streamSimple would send thinkingBudget
 *    instead of thinkingLevel. We route those models through stream() with
 *    explicit thinkingLevel values.
 */
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import {
	type Context,
	type Model,
	type SimpleStreamOptions,
	clampThinkingLevel,
	getApiProvider,
} from "@earendil-works/pi-ai/compat";

const KIE_GEMINI_STREAM_RE = /api\.kie\.ai\/gemini\/.*streamGenerateContent/i;
const DONE_LINE_RE = /^\s*(?:data:\s*)?\[DONE\]\s*$/i;
// Kie often omits finishReason on streamed candidates; pi requires one to finalize.
const SYNTHETIC_STOP_EVENT =
	'data: {"candidates":[{"finishReason":"STOP","content":{"role":"model","parts":[]}}]}\n\n';

let fetchPatched = false;

function isKieGeminiSseUrl(input: RequestInfo | URL): boolean {
	const url =
		typeof input === "string"
			? input
			: input instanceof URL
				? input.href
				: input.url;
	return KIE_GEMINI_STREAM_RE.test(url);
}

function lineHasFinishReason(line: string): boolean {
	if (!line.startsWith("data:")) return false;
	const payload = line.slice(5).trim();
	if (!payload || payload[0] !== "{") return false;
	try {
		const parsed = JSON.parse(payload) as {
			candidates?: Array<{ finishReason?: string }>;
		};
		return Boolean(parsed.candidates?.some((c) => c.finishReason));
	} catch {
		return false;
	}
}

/**
 * Drop OpenAI-style `data: [DONE]` terminators from Kie Gemini SSE bodies and
 * synthesize a STOP finishReason when Kie never sent one.
 */
function installKieGeminiFetchFix(): void {
	if (fetchPatched) return;
	fetchPatched = true;

	const originalFetch = globalThis.fetch.bind(globalThis);
	globalThis.fetch = async (input: RequestInfo | URL, init?: RequestInit): Promise<Response> => {
		const response = await originalFetch(input, init);
		if (!isKieGeminiSseUrl(input) || !response.body) {
			return response;
		}

		const reader = response.body.getReader();
		const decoder = new TextDecoder();
		const encoder = new TextEncoder();
		let buffer = "";
		let sawFinishReason = false;

		const enqueueLines = (
			controller: ReadableStreamDefaultController<Uint8Array>,
			lines: string[],
		) => {
			let out = "";
			for (const line of lines) {
				// Drop OpenAI-style stream terminator; inject STOP later if needed.
				if (DONE_LINE_RE.test(line)) continue;
				if (lineHasFinishReason(line)) {
					sawFinishReason = true;
				}
				out += `${line}\n`;
			}
			if (out.length > 0) {
				controller.enqueue(encoder.encode(out));
			}
		};

		const finalize = (controller: ReadableStreamDefaultController<Uint8Array>) => {
			if (buffer) {
				enqueueLines(controller, buffer.split(/\r?\n/));
				buffer = "";
			}
			if (!sawFinishReason) {
				controller.enqueue(encoder.encode(SYNTHETIC_STOP_EVENT));
			}
			controller.close();
		};

		const stream = new ReadableStream<Uint8Array>({
			async pull(controller) {
				const { done, value } = await reader.read();
				if (done) {
					finalize(controller);
					return;
				}

				buffer += decoder.decode(value, { stream: true });
				const lines = buffer.split(/\r?\n/);
				buffer = lines.pop() ?? "";
				enqueueLines(controller, lines);
			},
			cancel(reason) {
				return reader.cancel(reason);
			},
		});

		return new Response(stream, {
			status: response.status,
			statusText: response.statusText,
			headers: response.headers,
		});
	};
}

function mapGoogleThinkingLevel(
	effort: "minimal" | "low" | "medium" | "high" | "xhigh" | "max",
): "MINIMAL" | "LOW" | "MEDIUM" | "HIGH" {
	switch (effort) {
		case "minimal":
			return "MINIMAL";
		case "low":
			return "LOW";
		case "medium":
			return "MEDIUM";
		case "high":
		case "xhigh":
		case "max":
			return "HIGH";
	}
}

function isKieNativeGeminiModel(model: Model<string>): boolean {
	return (
		model.provider === "kie" &&
		model.api === "google-generative-ai" &&
		typeof model.baseUrl === "string" &&
		model.baseUrl.includes("api.kie.ai/gemini")
	);
}

function googleApi() {
	const api = getApiProvider("google-generative-ai");
	if (!api) {
		throw new Error("google-generative-ai API provider is not registered");
	}
	return api;
}

export default function (pi: ExtensionAPI) {
	installKieGeminiFetchFix();

	// Intercept only google-generative-ai models under the kie provider.
	// Other kie models (OpenAI completions/responses) keep the default path.
	pi.registerProvider("kie", {
		api: "google-generative-ai",
		streamSimple(model, context: Context, options?: SimpleStreamOptions) {
			const api = googleApi();
			if (!isKieNativeGeminiModel(model)) {
				return api.streamSimple(model, context, options);
			}

			const apiKey = options?.apiKey;
			if (!apiKey) {
				throw new Error(`No API key for provider: ${model.provider}`);
			}

			// thinkingLevelMap marks off unsupported; clamp away from it.
			if (!options?.reasoning) {
				// Keep hidden thinking at the lowest level (Gemini 3 Flash cannot fully disable).
				return api.stream(model, context, {
					...options,
					thinking: { enabled: true, level: "MINIMAL" },
				});
			}

			const clamped = clampThinkingLevel(model, options.reasoning);
			const effort = (clamped === "off" ? "high" : clamped) as
				| "minimal"
				| "low"
				| "medium"
				| "high"
				| "xhigh"
				| "max";

			return api.stream(model, context, {
				...options,
				thinking: {
					enabled: true,
					level: mapGoogleThinkingLevel(effort),
				},
			});
		},
	});
}
